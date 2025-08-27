//
//  TrustedNetworkMapper.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
import CoreData

/// Maps between TrustedNetwork domain entities and CDTrustedNetwork Core Data entities
struct TrustedNetworkMapper {
    
    /// Converts Core Data entity to domain entity
    static func toDomain(_ cdNetwork: CDTrustedNetwork) throws -> TrustedNetwork {
        guard let id = cdNetwork.id,
              let name = cdNetwork.name,
              let dateAdded = cdNetwork.dateAdded else {
            throw MappingError.missingRequiredField("TrustedNetwork")
        }
        
        let identifiers: [NetworkIdentifier]
        if let data = cdNetwork.identifiersData {
            identifiers = try JSONDecoder().decode([NetworkIdentifier].self, from: data)
        } else {
            identifiers = []
        }
        
        let customRules: [ProcessRule]
        if let data = cdNetwork.customRulesData {
            customRules = try JSONDecoder().decode([ProcessRule].self, from: data)
        } else {
            customRules = []
        }
        
        // Default trust level to trusted if not stored
        let trustLevel = NetworkTrustLevel.trusted
        
        return TrustedNetwork(
            id: id,
            name: name,
            identifiers: identifiers,
            dateAdded: dateAdded,
            isEnabled: cdNetwork.isEnabled,
            trustLevel: trustLevel,
            customRules: customRules
        )
    }
    
    /// Updates Core Data entity with domain entity values
    static func update(_ cdNetwork: CDTrustedNetwork, from domain: TrustedNetwork) throws {
        cdNetwork.id = domain.id
        cdNetwork.name = domain.name
        cdNetwork.dateAdded = domain.dateAdded
        cdNetwork.isEnabled = domain.isEnabled
        
        cdNetwork.identifiersData = try JSONEncoder().encode(domain.identifiers)
        
        if !domain.customRules.isEmpty {
            cdNetwork.customRulesData = try JSONEncoder().encode(domain.customRules)
        } else {
            cdNetwork.customRulesData = nil
        }
    }
    
    /// Creates new Core Data entity from domain entity
    static func toCore(_ domain: TrustedNetwork, in context: NSManagedObjectContext) throws -> CDTrustedNetwork {
        let cdNetwork = CDTrustedNetwork(context: context)
        try update(cdNetwork, from: domain)
        return cdNetwork
    }
}

/// Maps between TrafficObservation domain entities and CDTrafficObservation Core Data entities
struct TrafficObservationMapper {
    
    /// Converts Core Data entity to domain entity
    static func toDomain(_ cdObservation: CDTrafficObservation) throws -> TrafficObservation {
        guard let id = cdObservation.id,
              let timestamp = cdObservation.timestamp,
              cdObservation.processIdentifier != nil,
              let processName = cdObservation.processName,
              let processTypeStr = cdObservation.processType,
              let networkTypeStr = cdObservation.networkType else {
            throw MappingError.missingRequiredField("TrafficObservation")
        }
        
        let processType = ProcessType(rawValue: processTypeStr) ?? .unknown
        let process = ProcessIdentity(
            type: processType,
            name: processName
        )
        
        let networkType = NetworkType(rawValue: networkTypeStr) ?? .unknown
        
        return TrafficObservation(
            id: id,
            timestamp: timestamp,
            process: process,
            bytesIn: cdObservation.bytesIn,
            bytesOut: cdObservation.bytesOut,
            packetsIn: 0, // Not stored in Core Data yet
            packetsOut: 0, // Not stored in Core Data yet
            networkType: networkType,
            isTrustedNetwork: false, // Not stored in Core Data yet
            destinationHost: cdObservation.destinationHost,
            destinationPort: cdObservation.destinationPort > 0 ? Int(cdObservation.destinationPort) : nil
        )
    }
    
    /// Updates Core Data entity with domain entity values
    static func update(_ cdObservation: CDTrafficObservation, from domain: TrafficObservation) {
        cdObservation.id = domain.id
        cdObservation.timestamp = domain.timestamp
        cdObservation.processIdentifier = domain.process.identifier
        cdObservation.processName = domain.process.name
        cdObservation.processType = domain.process.type.rawValue
        cdObservation.bytesIn = domain.bytesIn
        cdObservation.bytesOut = domain.bytesOut
        cdObservation.networkType = domain.networkType.rawValue
        cdObservation.destinationHost = domain.destinationHost
        cdObservation.destinationPort = Int32(domain.destinationPort ?? 0)
    }
    
    /// Creates new Core Data entity from domain entity
    static func toCore(_ domain: TrafficObservation, in context: NSManagedObjectContext) -> CDTrafficObservation {
        let cdObservation = CDTrafficObservation(context: context)
        update(cdObservation, from: domain)
        return cdObservation
    }
}

/// Maps between ProcessProfile domain entities and CDProcessProfile Core Data entities
struct ProcessProfileMapper {
    
    /// Converts Core Data entity to domain entity
    static func toDomain(_ cdProfile: CDProcessProfile) throws -> ProcessProfile {
        guard cdProfile.processIdentifier != nil,
              let processName = cdProfile.processName,
              let processTypeStr = cdProfile.processType,
              let lastSeen = cdProfile.lastSeen else {
            throw MappingError.missingRequiredField("ProcessProfile")
        }
        
        let processType = ProcessType(rawValue: processTypeStr) ?? .unknown
        let process = ProcessIdentity(
            type: processType,
            name: processName,
            bundleId: cdProfile.bundleId,
            path: cdProfile.path
        )
        
        var profile = ProcessProfile(process: process)
        profile.observationCount = Int(cdProfile.observationCount)
        profile.averageBandwidth = cdProfile.averageBandwidth
        profile.peakBandwidth = cdProfile.peakBandwidth
        profile.totalBytesIn = cdProfile.totalBytesIn
        profile.totalBytesOut = cdProfile.totalBytesOut
        profile.lastSeen = lastSeen
        profile.isBursty = cdProfile.isBursty
        
        return profile
    }
    
    /// Updates Core Data entity with domain entity values
    static func update(_ cdProfile: CDProcessProfile, from domain: ProcessProfile) {
        cdProfile.processIdentifier = domain.process.identifier
        cdProfile.processName = domain.process.name
        cdProfile.processType = domain.process.type.rawValue
        cdProfile.bundleId = domain.process.bundleId
        cdProfile.path = domain.process.path
        cdProfile.observationCount = Int32(domain.observationCount)
        cdProfile.averageBandwidth = domain.averageBandwidth
        cdProfile.peakBandwidth = domain.peakBandwidth
        cdProfile.totalBytesIn = domain.totalBytesIn
        cdProfile.totalBytesOut = domain.totalBytesOut
        cdProfile.lastSeen = domain.lastSeen
        cdProfile.isBursty = domain.isBursty
    }
    
    /// Creates new Core Data entity from domain entity
    static func toCore(_ domain: ProcessProfile, in context: NSManagedObjectContext) -> CDProcessProfile {
        let cdProfile = CDProcessProfile(context: context)
        update(cdProfile, from: domain)
        return cdProfile
    }
}

enum MappingError: LocalizedError {
    case missingRequiredField(String)
    case invalidData(String)
    
    var errorDescription: String? {
        switch self {
        case .missingRequiredField(let entity):
            return "Missing required field for \(entity)"
        case .invalidData(let description):
            return "Invalid data: \(description)"
        }
    }
}