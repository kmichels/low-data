//
//  CoreDataTrustedNetworkRepository.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
import CoreData
import os.log

/// Core Data implementation of TrustedNetworkRepository
actor CoreDataTrustedNetworkRepository: TrustedNetworkRepository {
    private let container: NSPersistentContainer
    private let logger = Logger(subsystem: "com.lowdata", category: "TrustedNetworkRepository")
    
    init(container: NSPersistentContainer = PersistenceController.shared.container) {
        self.container = container
    }
    
    func fetchAll() async throws -> [TrustedNetwork] {
        let context = container.viewContext
        let request = CDTrustedNetwork.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDTrustedNetwork.dateAdded, ascending: false)]
        
        return try await context.perform {
            let cdNetworks = try context.fetch(request)
            return try cdNetworks.map { try TrustedNetworkMapper.toDomain($0) }
        }
    }
    
    func fetch(by id: UUID) async throws -> TrustedNetwork? {
        let context = container.viewContext
        let request = CDTrustedNetwork.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        
        return try await context.perform {
            guard let cdNetwork = try context.fetch(request).first else {
                return nil
            }
            return try TrustedNetworkMapper.toDomain(cdNetwork)
        }
    }
    
    func save(_ network: TrustedNetwork) async throws {
        let context = container.newBackgroundContext()
        
        try await context.perform {
            let request = CDTrustedNetwork.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", network.id as CVarArg)
            request.fetchLimit = 1
            
            let cdNetwork: CDTrustedNetwork
            if let existing = try context.fetch(request).first {
                cdNetwork = existing
            } else {
                cdNetwork = CDTrustedNetwork(context: context)
            }
            
            try TrustedNetworkMapper.update(cdNetwork, from: network)
            
            if context.hasChanges {
                try context.save()
                self.logger.info("Saved trusted network: \(network.name)")
            }
        }
    }
    
    func delete(_ network: TrustedNetwork) async throws {
        let context = container.newBackgroundContext()
        
        try await context.perform {
            let request = CDTrustedNetwork.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", network.id as CVarArg)
            request.fetchLimit = 1
            
            if let cdNetwork = try context.fetch(request).first {
                context.delete(cdNetwork)
                try context.save()
                self.logger.info("Deleted trusted network: \(network.name)")
            }
        }
    }
    
    func isTrusted(_ network: DetectedNetwork) async throws -> Bool {
        let trustedNetworks = try await fetchAll()
        return trustedNetworks.contains { $0.matches(network) }
    }
    
    func findMatch(for network: DetectedNetwork) async throws -> TrustedNetwork? {
        let trustedNetworks = try await fetchAll()
        return trustedNetworks.first { $0.matches(network) }
    }
}