//
//  CoreDataTrafficRepository.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
import CoreData
import os.log

/// Core Data implementation of TrafficDataRepository
actor CoreDataTrafficRepository: TrafficDataRepository {
    private let container: NSPersistentContainer
    private let logger = Logger(subsystem: "com.lowdata", category: "TrafficRepository")
    private let maxObservations = 100_000
    
    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
    }
    
    func save(_ observation: TrafficObservation) async throws {
        let context = container.newBackgroundContext()
        
        try await context.perform {
            _ = TrafficObservationMapper.toCore(observation, in: context)
            try context.save()
        }
    }
    
    func saveBatch(_ observations: [TrafficObservation]) async throws {
        guard !observations.isEmpty else { return }
        
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        try await context.perform {
            // Use batch insert for performance
            for observation in observations {
                _ = TrafficObservationMapper.toCore(observation, in: context)
            }
            
            try context.save()
            self.logger.info("Saved batch of \(observations.count) observations")
        }
        
        // Check if we need to prune old observations
        let count = try await getObservationCount()
        if count > maxObservations {
            let pruneDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            try await pruneOldObservations(before: pruneDate)
        }
    }
    
    func fetchObservations(for process: ProcessIdentity, limit: Int) async throws -> [TrafficObservation] {
        let context = container.viewContext
        let request = CDTrafficObservation.fetchRequest()
        request.predicate = NSPredicate(format: "processIdentifier == %@", process.identifier)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDTrafficObservation.timestamp, ascending: false)]
        request.fetchLimit = limit
        
        return try await context.perform {
            let cdObservations = try context.fetch(request)
            return try cdObservations.compactMap { try TrafficObservationMapper.toDomain($0) }
        }
    }
    
    func fetchObservations(from startDate: Date, to endDate: Date) async throws -> [TrafficObservation] {
        guard startDate <= endDate else {
            throw TrafficDataError.invalidDateRange
        }
        
        let context = container.viewContext
        let request = CDTrafficObservation.fetchRequest()
        request.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp <= %@", startDate as NSDate, endDate as NSDate)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDTrafficObservation.timestamp, ascending: false)]
        
        return try await context.perform {
            let cdObservations = try context.fetch(request)
            return try cdObservations.compactMap { try TrafficObservationMapper.toDomain($0) }
        }
    }
    
    func getStatistics(from startDate: Date, to endDate: Date) async throws -> TrafficStatistics {
        guard startDate <= endDate else {
            throw TrafficDataError.invalidDateRange
        }
        
        let context = container.viewContext
        
        return try await context.perform {
            // Fetch aggregated data using Core Data
            let request = CDTrafficObservation.fetchRequest()
            request.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp <= %@", startDate as NSDate, endDate as NSDate)
            
            let observations = try context.fetch(request)
            
            // Calculate statistics
            var totalBytesIn: UInt64 = 0
            var totalBytesOut: UInt64 = 0
            var processBytesMap: [String: UInt64] = [:]
            
            for obs in observations {
                totalBytesIn += UInt64(obs.bytesIn)
                totalBytesOut += UInt64(obs.bytesOut)
                
                if let processId = obs.processIdentifier {
                    let totalBytes = UInt64(obs.bytesIn + obs.bytesOut)
                    processBytesMap[processId, default: 0] += totalBytes
                }
            }
            
            // Get top processes
            let topProcesses = processBytesMap
                .sorted { $0.value > $1.value }
                .prefix(10)
                .compactMap { (identifier, bytes) -> (ProcessIdentity, UInt64)? in
                    guard let obs = observations.first(where: { $0.processIdentifier == identifier }),
                          let processName = obs.processName,
                          let processType = obs.processType else {
                        return nil
                    }
                    
                    let process = ProcessIdentity(
                        type: ProcessType(rawValue: processType) ?? .unknown,
                        name: processName
                    )
                    return (process, bytes)
                }
            
            return TrafficStatistics(
                periodStart: startDate,
                periodEnd: endDate,
                totalBytesBlocked: 0, // Will be updated when filtering is implemented
                totalBytesAllowed: totalBytesIn + totalBytesOut,
                blockedConnectionCount: 0,
                allowedConnectionCount: observations.count,
                topBlockedProcesses: [],
                topAllowedProcesses: Array(topProcesses)
            )
        }
    }
    
    func pruneOldObservations(before date: Date) async throws {
        let context = container.newBackgroundContext()
        
        try await context.perform {
            // Check if we're using an in-memory store (for testing)
            let isInMemory = self.container.persistentStoreDescriptions.first?.type == NSInMemoryStoreType
            
            if isInMemory {
                // For in-memory stores, fetch and delete individually
                let request = NSFetchRequest<CDTrafficObservation>(entityName: "CDTrafficObservation")
                request.predicate = NSPredicate(format: "timestamp < %@", date as NSDate)
                
                let observations = try context.fetch(request)
                let deleteCount = observations.count
                
                for observation in observations {
                    context.delete(observation)
                }
                
                if deleteCount > 0 {
                    try context.save()
                    self.logger.info("Pruned \(deleteCount) old observations")
                }
            } else {
                // For persistent stores, use batch delete
                let request = NSFetchRequest<NSFetchRequestResult>(entityName: "CDTrafficObservation")
                request.predicate = NSPredicate(format: "timestamp < %@", date as NSDate)
                
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
                deleteRequest.resultType = .resultTypeCount
                
                let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
                let deleteCount = result?.result as? Int ?? 0
                
                if deleteCount > 0 {
                    // Batch deletes bypass the context, so we need to merge changes
                    try context.save()
                    self.logger.info("Pruned \(deleteCount) old observations")
                }
            }
        }
    }
    
    func getObservationCount() async throws -> Int {
        let context = container.viewContext
        let request = CDTrafficObservation.fetchRequest()
        
        return try await context.perform {
            try context.count(for: request)
        }
    }
}

/// Core Data implementation of ProcessProfileRepository
actor CoreDataProcessProfileRepository: ProcessProfileRepository {
    private let container: NSPersistentContainer
    private let logger = Logger(subsystem: "com.lowdata", category: "ProcessProfileRepository")
    
    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
    }
    
    func save(_ profile: ProcessProfile) async throws {
        let context = container.newBackgroundContext()
        
        try await context.perform {
            let request = CDProcessProfile.fetchRequest()
            request.predicate = NSPredicate(format: "processIdentifier == %@", profile.process.identifier)
            request.fetchLimit = 1
            
            let cdProfile: CDProcessProfile
            if let existing = try context.fetch(request).first {
                cdProfile = existing
            } else {
                cdProfile = CDProcessProfile(context: context)
            }
            
            ProcessProfileMapper.update(cdProfile, from: profile)
            
            if context.hasChanges {
                try context.save()
                self.logger.debug("Saved profile for process: \(profile.process.name)")
            }
        }
    }
    
    func fetch(for process: ProcessIdentity) async throws -> ProcessProfile? {
        let context = container.viewContext
        let request = CDProcessProfile.fetchRequest()
        request.predicate = NSPredicate(format: "processIdentifier == %@", process.identifier)
        request.fetchLimit = 1
        
        return try await context.perform {
            guard let cdProfile = try context.fetch(request).first else {
                return nil
            }
            return try ProcessProfileMapper.toDomain(cdProfile)
        }
    }
    
    func fetchAll() async throws -> [ProcessProfile] {
        let context = container.viewContext
        let request = CDProcessProfile.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDProcessProfile.lastSeen, ascending: false)]
        
        return try await context.perform {
            let cdProfiles = try context.fetch(request)
            return try cdProfiles.map { try ProcessProfileMapper.toDomain($0) }
        }
    }
    
    func fetchBandwidthIntensive(threshold: Double) async throws -> [ProcessProfile] {
        let context = container.viewContext
        let request = CDProcessProfile.fetchRequest()
        request.predicate = NSPredicate(format: "averageBandwidth > %f", threshold)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDProcessProfile.averageBandwidth, ascending: false)]
        
        return try await context.perform {
            let cdProfiles = try context.fetch(request)
            return try cdProfiles.map { try ProcessProfileMapper.toDomain($0) }
        }
    }
    
    func pruneInactive(before date: Date) async throws {
        let context = container.newBackgroundContext()
        
        try await context.perform {
            // Check if we're using an in-memory store (for testing)
            let isInMemory = self.container.persistentStoreDescriptions.first?.type == NSInMemoryStoreType
            
            if isInMemory {
                // For in-memory stores, fetch and delete individually
                let request = NSFetchRequest<CDProcessProfile>(entityName: "CDProcessProfile")
                request.predicate = NSPredicate(format: "lastSeen < %@", date as NSDate)
                
                let profiles = try context.fetch(request)
                let deleteCount = profiles.count
                
                for profile in profiles {
                    context.delete(profile)
                }
                
                if deleteCount > 0 {
                    try context.save()
                    self.logger.info("Pruned \(deleteCount) inactive process profiles")
                }
            } else {
                // For persistent stores, use batch delete
                let request = NSFetchRequest<NSFetchRequestResult>(entityName: "CDProcessProfile")
                request.predicate = NSPredicate(format: "lastSeen < %@", date as NSDate)
                
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
                deleteRequest.resultType = .resultTypeCount
                
                let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
                let deleteCount = result?.result as? Int ?? 0
                
                if deleteCount > 0 {
                    // Batch deletes bypass the context, so we need to merge changes
                    try context.save()
                    self.logger.info("Pruned \(deleteCount) inactive process profiles")
                }
            }
        }
    }
}