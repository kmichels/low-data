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
    public var timestamp: Date
    public let process: ProcessIdentity
    public let bytesIn: Int64
    public let bytesOut: Int64
    public let packetsIn: Int
    public let packetsOut: Int
    public let networkType: NetworkType
    public let isTrustedNetwork: Bool
    public let destinationHost: String?
    public let destinationPort: Int?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        process: ProcessIdentity,
        bytesIn: Int64,
        bytesOut: Int64,
        packetsIn: Int = 0,
        packetsOut: Int = 0,
        networkType: NetworkType,
        isTrustedNetwork: Bool,
        destinationHost: String? = nil,
        destinationPort: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.process = process
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.packetsIn = packetsIn
        self.packetsOut = packetsOut
        self.networkType = networkType
        self.isTrustedNetwork = isTrustedNetwork
        self.destinationHost = destinationHost
        self.destinationPort = destinationPort
    }
    
    /// Total bandwidth for this observation
    public var totalBytes: Int64 {
        bytesIn + bytesOut
    }
}

/// Type of network connection
public enum NetworkType: String, Codable, CaseIterable {
    case wifi
    case cellular
    case ethernet
    case vpn
    case unknown
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
public struct TrafficStatistics {
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