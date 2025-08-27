//
//  TrustedNetwork.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation

/// Represents a trusted network configuration
public struct TrustedNetwork: Identifiable, Equatable, Codable {
    public let id: UUID
    public let name: String
    public let identifiers: [NetworkIdentifier]
    public let dateAdded: Date
    public let isEnabled: Bool
    public let customRules: [ProcessRule]?
    
    public init(
        id: UUID = UUID(),
        name: String,
        identifiers: [NetworkIdentifier],
        dateAdded: Date = Date(),
        isEnabled: Bool = true,
        customRules: [ProcessRule]? = nil
    ) {
        self.id = id
        self.name = name
        self.identifiers = identifiers
        self.dateAdded = dateAdded
        self.isEnabled = isEnabled
        self.customRules = customRules
    }
    
    /// Check if the given network matches this trusted network configuration
    public func matches(_ network: DetectedNetwork) -> Bool {
        guard isEnabled else { return false }
        
        // Network matches if ANY identifier matches (OR logic)
        // Use combination identifier for AND logic
        return identifiers.contains { $0.matches(network) }
    }
}

/// Represents a custom rule for a specific process
public struct ProcessRule: Codable, Equatable {
    public let processIdentifier: String
    public let action: RuleAction
    public let reason: String?
    
    public init(
        processIdentifier: String,
        action: RuleAction,
        reason: String? = nil
    ) {
        self.processIdentifier = processIdentifier
        self.action = action
        self.reason = reason
    }
}

public enum RuleAction: String, Codable {
    case allow
    case block
    case askUser
}

/// Trust level for a network
public enum NetworkTrustLevel: String, Codable {
    case trusted
    case untrusted
    case unknown
    
    public var shouldRestrictTraffic: Bool {
        switch self {
        case .trusted:
            return false
        case .untrusted, .unknown:
            return true
        }
    }
}