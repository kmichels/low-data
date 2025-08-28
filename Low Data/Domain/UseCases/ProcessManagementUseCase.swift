//
//  ProcessManagementUseCase.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation

/// Use case for getting process filtering recommendations
public actor GetProcessRecommendationsUseCase: UseCase {
    
    // MARK: - Dependencies
    
    private let processProfileRepository: ProcessProfileRepository
    private let trustEvaluationUseCase: TrustEvaluationUseCase
    
    // MARK: - Initialization
    
    public init(processProfileRepository: ProcessProfileRepository,
                trustEvaluationUseCase: TrustEvaluationUseCase) {
        self.processProfileRepository = processProfileRepository
        self.trustEvaluationUseCase = trustEvaluationUseCase
    }
    
    // MARK: - Input
    
    public struct Input {
        public let considerCurrentTrust: Bool
        public let bandwidthThresholdMB: Double
        public let includeSystemProcesses: Bool
        
        public init(considerCurrentTrust: Bool = true,
                   bandwidthThresholdMB: Double = 50.0,
                   includeSystemProcesses: Bool = false) {
            self.considerCurrentTrust = considerCurrentTrust
            self.bandwidthThresholdMB = bandwidthThresholdMB
            self.includeSystemProcesses = includeSystemProcesses
        }
    }
    
    // MARK: - Output
    
    public struct Output {
        public let recommendations: [ProcessRecommendation]
        public let currentTrustState: TrustEvaluationResult?
        
        public struct ProcessRecommendation {
            public let process: ProcessIdentity
            public let profile: ProcessProfile
            public let recommendation: RecommendationType
            public let reason: String
            public let estimatedMonthlySavingsMB: Double
            
            public enum RecommendationType {
                case block
                case allow
                case monitor
                case askUser
            }
        }
    }
    
    // MARK: - Execution
    
    public func execute(_ input: Input) async throws -> Output {
        // Get current trust state if needed
        let trustState = input.considerCurrentTrust ? 
            try await trustEvaluationUseCase.execute() : nil
        
        // Get all process profiles
        let profiles = try await processProfileRepository.fetchAll()
        
        // Filter and create recommendations
        var recommendations: [Output.ProcessRecommendation] = []
        
        for profile in profiles {
            // Skip system processes if not included
            if !input.includeSystemProcesses && profile.process.type == .system {
                continue
            }
            
            // Skip if no significant data
            if profile.observationCount < 5 {
                continue
            }
            
            // Determine recommendation
            let avgMBPerHour = profile.averageBandwidth / 1024 / 1024
            let monthlyMB = avgMBPerHour * 24 * 30
            
            let recommendation: Output.ProcessRecommendation.RecommendationType
            let reason: String
            
            // Check against common bandwidth hogs
            if isKnownBandwidthHog(profile.process) {
                recommendation = .block
                reason = "Known bandwidth-intensive application"
            }
            // Check if exceeds threshold
            else if avgMBPerHour > input.bandwidthThresholdMB {
                if profile.isBursty {
                    recommendation = .block
                    reason = "High bandwidth usage with bursty pattern"
                } else {
                    recommendation = .askUser
                    reason = "Consistently high bandwidth usage"
                }
            }
            // Check for essential services
            else if isEssentialService(profile.process) {
                recommendation = .allow
                reason = "Essential system service"
            }
            // Default to monitoring
            else {
                recommendation = .monitor
                reason = "Low to moderate bandwidth usage"
            }
            
            recommendations.append(Output.ProcessRecommendation(
                process: profile.process,
                profile: profile,
                recommendation: recommendation,
                reason: reason,
                estimatedMonthlySavingsMB: recommendation == .block ? monthlyMB : 0
            ))
        }
        
        // Sort by potential savings
        recommendations.sort { $0.estimatedMonthlySavingsMB > $1.estimatedMonthlySavingsMB }
        
        return Output(
            recommendations: recommendations,
            currentTrustState: trustState
        )
    }
    
    // MARK: - Helpers
    
    private func isKnownBandwidthHog(_ process: ProcessIdentity) -> Bool {
        let knownHogs = [
            "com.dropbox",
            "com.google.drive",
            "com.microsoft.onedrive",
            "com.getdropbox.dropbox",
            "com.apple.photolibraryd",  // iCloud Photos
            "com.spotify",
            "com.netflix"
        ]
        
        return knownHogs.contains { process.identifier.contains($0) }
    }
    
    private func isEssentialService(_ process: ProcessIdentity) -> Bool {
        let essential = [
            "com.apple.security",
            "com.apple.trustd",
            "com.apple.networkd",
            "com.apple.mDNSResponder",
            "com.apple.softwareupdated"  // Important for security updates
        ]
        
        return essential.contains { process.identifier.contains($0) }
    }
}

/// Use case for applying process rules
public actor ApplyProcessRulesUseCase: UseCase {
    
    // MARK: - Dependencies
    
    private let trustedNetworkRepository: TrustedNetworkRepository
    private let trustEvaluationUseCase: TrustEvaluationUseCase
    
    // MARK: - Initialization
    
    public init(trustedNetworkRepository: TrustedNetworkRepository,
                trustEvaluationUseCase: TrustEvaluationUseCase) {
        self.trustedNetworkRepository = trustedNetworkRepository
        self.trustEvaluationUseCase = trustEvaluationUseCase
    }
    
    // MARK: - Input
    
    public struct Input {
        public let rules: [ProcessRule]
        public let applyToCurrentNetwork: Bool
        public let applyGlobally: Bool
        
        public init(rules: [ProcessRule],
                   applyToCurrentNetwork: Bool = true,
                   applyGlobally: Bool = false) {
            self.rules = rules
            self.applyToCurrentNetwork = applyToCurrentNetwork
            self.applyGlobally = applyGlobally
        }
    }
    
    // MARK: - Output
    
    public struct Output {
        public let appliedRules: [ProcessRule]
        public let updatedNetworks: [TrustedNetwork]
        public let failedRules: [(rule: ProcessRule, error: Error)]
    }
    
    // MARK: - Execution
    
    public func execute(_ input: Input) async throws -> Output {
        guard !input.rules.isEmpty else {
            throw UseCaseError.invalidInput("No rules provided")
        }
        
        var appliedRules: [ProcessRule] = []
        var updatedNetworks: [TrustedNetwork] = []
        let failedRules: [(ProcessRule, Error)] = []
        
        if input.applyGlobally {
            // Apply to all trusted networks
            let allNetworks = try await trustedNetworkRepository.fetchAll()
            
            for network in allNetworks {
                var updatedNetwork = network
                for rule in input.rules {
                    // Add or update rule
                    if let existingIndex = updatedNetwork.customRules.firstIndex(where: { 
                        $0.processIdentifier == rule.processIdentifier 
                    }) {
                        updatedNetwork.customRules[existingIndex] = rule
                    } else {
                        updatedNetwork.customRules.append(rule)
                    }
                    appliedRules.append(rule)
                }
                
                try await trustedNetworkRepository.save(updatedNetwork)
                updatedNetworks.append(updatedNetwork)
            }
        } else if input.applyToCurrentNetwork {
            // Apply to current trusted network only
            let trustResult = try await trustEvaluationUseCase.execute()
            
            guard let currentNetwork = trustResult.matchedNetwork else {
                throw UseCaseError.networkUnavailable
            }
            
            var updatedNetwork = currentNetwork
            for rule in input.rules {
                // Add or update rule
                if let existingIndex = updatedNetwork.customRules.firstIndex(where: { 
                    $0.processIdentifier == rule.processIdentifier 
                }) {
                    updatedNetwork.customRules[existingIndex] = rule
                } else {
                    updatedNetwork.customRules.append(rule)
                }
                appliedRules.append(rule)
            }
            
            try await trustedNetworkRepository.save(updatedNetwork)
            updatedNetworks.append(updatedNetwork)
        }
        
        return Output(
            appliedRules: appliedRules,
            updatedNetworks: updatedNetworks,
            failedRules: failedRules
        )
    }
}

/// Use case for learning process behavior patterns
public actor LearnProcessBehaviorUseCase: UseCase {
    
    // MARK: - Dependencies
    
    private let processProfileRepository: ProcessProfileRepository
    private let trafficRepository: TrafficDataRepository
    
    // MARK: - Initialization
    
    public init(processProfileRepository: ProcessProfileRepository,
                trafficRepository: TrafficDataRepository) {
        self.processProfileRepository = processProfileRepository
        self.trafficRepository = trafficRepository
    }
    
    // MARK: - Input
    
    public struct Input {
        public let process: ProcessIdentity
        public let learningPeriodDays: Int
        
        public init(process: ProcessIdentity,
                   learningPeriodDays: Int = 7) {
            self.process = process
            self.learningPeriodDays = learningPeriodDays
        }
    }
    
    // MARK: - Output
    
    public struct Output {
        public let profile: ProcessProfile
        public let patterns: BehaviorPatterns
        
        public struct BehaviorPatterns {
            public let peakUsageHours: [Int]  // Hours of day (0-23)
            public let averageDailyMB: Double
            public let burstFrequency: Double  // Bursts per day
            public let typicalSessionDurationMinutes: Double
            public let preferredNetworkType: NetworkType?
        }
    }
    
    // MARK: - Execution
    
    public func execute(_ input: Input) async throws -> Output {
        // Fetch recent observations
        let endDate = Date()
        let _ = Calendar.current.date(
            byAdding: .day, 
            value: -input.learningPeriodDays, 
            to: endDate
        )!
        
        let observations = try await trafficRepository.fetchObservations(
            for: input.process, 
            limit: 1000
        )
        
        guard !observations.isEmpty else {
            throw UseCaseError.invalidInput("No observations found for process")
        }
        
        // Analyze patterns
        var hourlyUsage: [Int: Int64] = [:]
        var dailyUsage: [String: Int64] = [:]
        var networkTypes: [NetworkType: Int] = [:]
        var sessionStarts: [Date] = []
        
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        for (index, observation) in observations.enumerated() {
            // Track hourly usage
            let hour = calendar.component(.hour, from: observation.timestamp)
            hourlyUsage[hour, default: 0] += observation.bytesIn + observation.bytesOut
            
            // Track daily usage
            let day = dateFormatter.string(from: observation.timestamp)
            dailyUsage[day, default: 0] += observation.bytesIn + observation.bytesOut
            
            // Track network types
            networkTypes[observation.networkType, default: 0] += 1
            
            // Detect session starts (gap > 5 minutes)
            if index == 0 || 
               observation.timestamp.timeIntervalSince(observations[index-1].timestamp) > 300 {
                sessionStarts.append(observation.timestamp)
            }
        }
        
        // Calculate patterns
        let peakHours = hourlyUsage
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }
            .sorted()
        
        let totalDailyBytes = dailyUsage.values.reduce(0, +)
        let dayCount = Double(max(dailyUsage.count, 1))
        let avgDailyMB = Double(totalDailyBytes) / dayCount / 1024 / 1024
        
        let burstFrequency = Double(sessionStarts.count) / 
            Double(max(input.learningPeriodDays, 1))
        
        let avgSessionMinutes: Double = {
            guard sessionStarts.count > 1 else { return 30.0 }
            var durations: [TimeInterval] = []
            for i in 0..<sessionStarts.count-1 {
                durations.append(sessionStarts[i+1].timeIntervalSince(sessionStarts[i]))
            }
            return durations.reduce(0, +) / Double(durations.count) / 60
        }()
        
        let preferredNetwork = networkTypes.max { $0.value < $1.value }?.key
        
        // Get or create profile
        var profile = try await processProfileRepository.fetch(for: input.process) 
            ?? ProcessProfile(process: input.process)
        
        // Update profile with latest observations
        for observation in observations {
            profile.addObservation(observation)
        }
        
        try await processProfileRepository.save(profile)
        
        return Output(
            profile: profile,
            patterns: Output.BehaviorPatterns(
                peakUsageHours: peakHours,
                averageDailyMB: avgDailyMB,
                burstFrequency: burstFrequency,
                typicalSessionDurationMinutes: avgSessionMinutes,
                preferredNetworkType: preferredNetwork
            )
        )
    }
}