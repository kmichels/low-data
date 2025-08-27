//
//  TrafficMonitoringUseCase.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation

/// Use case for recording traffic observations
public actor RecordTrafficObservationUseCase: UseCase {
    
    // MARK: - Dependencies
    
    private let trafficRepository: TrafficDataRepository
    private let processProfileRepository: ProcessProfileRepository
    
    // MARK: - Initialization
    
    public init(trafficRepository: TrafficDataRepository,
                processProfileRepository: ProcessProfileRepository) {
        self.trafficRepository = trafficRepository
        self.processProfileRepository = processProfileRepository
    }
    
    // MARK: - Input
    
    public struct Input {
        public let process: ProcessIdentity
        public let bytesIn: Int64
        public let bytesOut: Int64
        public let packetsIn: Int
        public let packetsOut: Int
        public let networkType: NetworkType
        public let isTrusted: Bool
        
        public init(process: ProcessIdentity,
                   bytesIn: Int64,
                   bytesOut: Int64,
                   packetsIn: Int = 0,
                   packetsOut: Int = 0,
                   networkType: NetworkType,
                   isTrusted: Bool) {
            self.process = process
            self.bytesIn = bytesIn
            self.bytesOut = bytesOut
            self.packetsIn = packetsIn
            self.packetsOut = packetsOut
            self.networkType = networkType
            self.isTrusted = isTrusted
        }
    }
    
    // MARK: - Execution
    
    public func execute(_ input: Input) async throws -> TrafficObservation {
        // Create observation
        let observation = TrafficObservation(
            process: input.process,
            bytesIn: input.bytesIn,
            bytesOut: input.bytesOut,
            packetsIn: input.packetsIn,
            packetsOut: input.packetsOut,
            networkType: input.networkType,
            isTrustedNetwork: input.isTrusted
        )
        
        // Save observation
        try await trafficRepository.save(observation)
        
        // Update process profile
        var profile = try await processProfileRepository.fetch(for: input.process) 
            ?? ProcessProfile(process: input.process)
        
        profile.addObservation(observation)
        try await processProfileRepository.save(profile)
        
        return observation
    }
}

/// Use case for getting traffic statistics
public actor GetTrafficStatisticsUseCase: UseCase {
    
    // MARK: - Dependencies
    
    private let trafficRepository: TrafficDataRepository
    
    // MARK: - Initialization
    
    public init(trafficRepository: TrafficDataRepository) {
        self.trafficRepository = trafficRepository
    }
    
    // MARK: - Input
    
    public struct Input {
        public let startDate: Date
        public let endDate: Date
        public let groupBy: GroupingType
        
        public enum GroupingType {
            case process
            case hour
            case day
            case networkType
        }
        
        public init(startDate: Date,
                   endDate: Date = Date(),
                   groupBy: GroupingType = .process) {
            self.startDate = startDate
            self.endDate = endDate
            self.groupBy = groupBy
        }
    }
    
    // MARK: - Output
    
    public struct Output {
        public let totalBytesIn: Int64
        public let totalBytesOut: Int64
        public let totalPackets: Int
        public let observationCount: Int
        public let groupedStats: [GroupedStatistic]
        public let period: DateInterval
        
        public struct GroupedStatistic {
            public let key: String
            public let bytesIn: Int64
            public let bytesOut: Int64
            public let observationCount: Int
        }
    }
    
    // MARK: - Execution
    
    public func execute(_ input: Input) async throws -> Output {
        guard input.startDate <= input.endDate else {
            throw UseCaseError.invalidInput("Start date must be before end date")
        }
        
        // Get observations
        let observations = try await trafficRepository.fetchObservations(
            from: input.startDate, 
            to: input.endDate
        )
        
        // Calculate totals
        var totalBytesIn: Int64 = 0
        var totalBytesOut: Int64 = 0
        var totalPackets = 0
        
        // Group statistics
        var grouped: [String: (bytesIn: Int64, bytesOut: Int64, count: Int)] = [:]
        
        for observation in observations {
            totalBytesIn += observation.bytesIn
            totalBytesOut += observation.bytesOut
            totalPackets += observation.packetsIn + observation.packetsOut
            
            // Determine grouping key
            let key: String
            switch input.groupBy {
            case .process:
                key = observation.process.displayName
            case .hour:
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:00"
                key = formatter.string(from: observation.timestamp)
            case .day:
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                key = formatter.string(from: observation.timestamp)
            case .networkType:
                key = observation.networkType.rawValue
            }
            
            // Update grouped stats
            if var existing = grouped[key] {
                existing.bytesIn += observation.bytesIn
                existing.bytesOut += observation.bytesOut
                existing.count += 1
                grouped[key] = existing
            } else {
                grouped[key] = (observation.bytesIn, observation.bytesOut, 1)
            }
        }
        
        // Convert to output format
        let groupedStats = grouped.map { key, value in
            Output.GroupedStatistic(
                key: key,
                bytesIn: value.bytesIn,
                bytesOut: value.bytesOut,
                observationCount: value.count
            )
        }.sorted { $0.bytesIn + $0.bytesOut > $1.bytesIn + $1.bytesOut }
        
        return Output(
            totalBytesIn: totalBytesIn,
            totalBytesOut: totalBytesOut,
            totalPackets: totalPackets,
            observationCount: observations.count,
            groupedStats: groupedStats,
            period: DateInterval(start: input.startDate, end: input.endDate)
        )
    }
}

/// Use case for identifying bandwidth-intensive processes
public actor IdentifyBandwidthHogsUseCase: UseCase {
    
    // MARK: - Dependencies
    
    private let processProfileRepository: ProcessProfileRepository
    
    // MARK: - Initialization
    
    public init(processProfileRepository: ProcessProfileRepository) {
        self.processProfileRepository = processProfileRepository
    }
    
    // MARK: - Input
    
    public struct Input {
        public let thresholdMBPerHour: Double
        public let minimumObservations: Int
        
        public init(thresholdMBPerHour: Double = 100.0,
                   minimumObservations: Int = 10) {
            self.thresholdMBPerHour = thresholdMBPerHour
            self.minimumObservations = minimumObservations
        }
    }
    
    // MARK: - Output
    
    public struct Output {
        public let bandwidthHogs: [BandwidthHog]
        
        public struct BandwidthHog {
            public let profile: ProcessProfile
            public let averageMBPerHour: Double
            public let peakMBPerHour: Double
            public let isBursty: Bool
        }
    }
    
    // MARK: - Execution
    
    public func execute(_ input: Input) async throws -> Output {
        // Convert MB to bytes for comparison
        let thresholdBytesPerHour = input.thresholdMBPerHour * 1024 * 1024
        
        // Get all profiles exceeding threshold
        let profiles = try await processProfileRepository.fetchBandwidthIntensive(
            threshold: thresholdBytesPerHour
        )
        
        // Filter and map to output
        let bandwidthHogs = profiles
            .filter { $0.observationCount >= input.minimumObservations }
            .map { profile in
                let avgMBPerHour = (profile.averageBandwidth / 1024 / 1024)
                let peakMBPerHour = (profile.peakBandwidth / 1024 / 1024)
                
                return Output.BandwidthHog(
                    profile: profile,
                    averageMBPerHour: avgMBPerHour,
                    peakMBPerHour: peakMBPerHour,
                    isBursty: profile.isBursty
                )
            }
            .sorted { $0.averageMBPerHour > $1.averageMBPerHour }
        
        return Output(bandwidthHogs: bandwidthHogs)
    }
}

/// Use case for cleaning up old traffic data
public actor CleanupTrafficDataUseCase: UseCase {
    
    // MARK: - Dependencies
    
    private let trafficRepository: TrafficDataRepository
    private let processProfileRepository: ProcessProfileRepository
    
    // MARK: - Initialization
    
    public init(trafficRepository: TrafficDataRepository,
                processProfileRepository: ProcessProfileRepository) {
        self.trafficRepository = trafficRepository
        self.processProfileRepository = processProfileRepository
    }
    
    // MARK: - Input
    
    public struct Input {
        public let retentionDays: Int
        public let inactiveProfileDays: Int
        
        public init(retentionDays: Int = 30,
                   inactiveProfileDays: Int = 90) {
            self.retentionDays = retentionDays
            self.inactiveProfileDays = inactiveProfileDays
        }
    }
    
    // MARK: - Output
    
    public struct Output {
        public let deletedObservations: Int
        public let deletedProfiles: Int
        public let freedSpace: Int64  // Estimated in bytes
    }
    
    // MARK: - Execution
    
    public func execute(_ input: Input) async throws -> Output {
        // Calculate cutoff dates
        let observationCutoff = Calendar.current.date(
            byAdding: .day, 
            value: -input.retentionDays, 
            to: Date()
        )!
        
        let profileCutoff = Calendar.current.date(
            byAdding: .day, 
            value: -input.inactiveProfileDays, 
            to: Date()
        )!
        
        // Get counts before deletion
        let observationCountBefore = try await trafficRepository.getObservationCount()
        let profilesBefore = try await processProfileRepository.fetchAll()
        
        // Cleanup observations
        try await trafficRepository.pruneOldObservations(before: observationCutoff)
        
        // Cleanup inactive profiles
        try await processProfileRepository.pruneInactive(before: profileCutoff)
        
        // Get counts after deletion
        let observationCountAfter = try await trafficRepository.getObservationCount()
        let profilesAfter = try await processProfileRepository.fetchAll()
        
        let deletedObservations = observationCountBefore - observationCountAfter
        let deletedProfiles = profilesBefore.count - profilesAfter.count
        
        // Estimate freed space (rough estimate: 100 bytes per observation, 1KB per profile)
        let freedSpace = Int64(deletedObservations * 100 + deletedProfiles * 1024)
        
        return Output(
            deletedObservations: deletedObservations,
            deletedProfiles: deletedProfiles,
            freedSpace: freedSpace
        )
    }
}