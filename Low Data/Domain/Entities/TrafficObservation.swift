//
//  TrafficObservation.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation

/// Represents an observation of network traffic for learning
public struct TrafficObservation: Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let process: ProcessIdentity
    public let bytesIn: UInt64
    public let bytesOut: UInt64
    public let networkType: NetworkTrustLevel
    public let networkQuality: NetworkQuality
    public let destinationHost: String?
    public let destinationPort: Int?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        process: ProcessIdentity,
        bytesIn: UInt64,
        bytesOut: UInt64,
        networkType: NetworkTrustLevel,
        networkQuality: NetworkQuality,
        destinationHost: String? = nil,
        destinationPort: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.process = process
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.networkType = networkType
        self.networkQuality = networkQuality
        self.destinationHost = destinationHost
        self.destinationPort = destinationPort
    }
    
    /// Total bandwidth for this observation
    public var totalBytes: UInt64 {
        bytesIn + bytesOut
    }
}

/// Recommendation for blocking/allowing a process
public enum BlockingRecommendation: Equatable {
    case allow(reason: String)
    case block(reason: String)
    case askUser(reason: String)
    
    public var shouldBlock: Bool {
        switch self {
        case .block:
            return true
        case .allow, .askUser:
            return false
        }
    }
    
    public var reason: String {
        switch self {
        case .allow(let reason), .block(let reason), .askUser(let reason):
            return reason
        }
    }
    
    public var requiresUserInput: Bool {
        switch self {
        case .askUser:
            return true
        case .allow, .block:
            return false
        }
    }
}

/// Statistics about network traffic
public struct TrafficStatistics: Codable {
    public let periodStart: Date
    public let periodEnd: Date
    public let totalBytesBlocked: UInt64
    public let totalBytesAllowed: UInt64
    public let blockedConnectionCount: Int
    public let allowedConnectionCount: Int
    public let topBlockedProcesses: [(ProcessIdentity, UInt64)]
    public let topAllowedProcesses: [(ProcessIdentity, UInt64)]
    
    public var totalBytes: UInt64 {
        totalBytesBlocked + totalBytesAllowed
    }
    
    public var blockRate: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(totalBytesBlocked) / Double(totalBytes)
    }
    
    public var savedBandwidth: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalBytesBlocked), countStyle: .binary)
    }
}