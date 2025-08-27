//
//  FilterControlXPCProtocol.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation

/// XPC protocol for communication between the main app and the system extension
@objc public protocol FilterControlXPCProtocol {
    
    // MARK: - Configuration
    
    /// Update the list of trusted networks
    func updateTrustedNetworks(_ networks: Data, reply: @escaping (Bool, Error?) -> Void)
    
    /// Update filtering rules
    func updateFilterRules(_ rules: Data, reply: @escaping (Bool, Error?) -> Void)
    
    /// Set whether filtering is enabled
    func setFilteringEnabled(_ enabled: Bool, reply: @escaping (Bool, Error?) -> Void)
    
    // MARK: - Status
    
    /// Get current filter status
    func getFilterStatus(reply: @escaping (Data?, Error?) -> Void)
    
    /// Get current network status
    func getCurrentNetwork(reply: @escaping (Data?, Error?) -> Void)
    
    /// Get statistics
    func getStatistics(reply: @escaping (Data?, Error?) -> Void)
    
    // MARK: - Traffic Monitoring
    
    /// Get recent traffic observations
    func getRecentTraffic(limit: Int, reply: @escaping (Data?, Error?) -> Void)
    
    /// Get traffic for specific process
    func getTrafficForProcess(_ processId: String, reply: @escaping (Data?, Error?) -> Void)
    
    // MARK: - Control
    
    /// Clear all statistics
    func clearStatistics(reply: @escaping (Bool, Error?) -> Void)
    
    /// Force re-evaluation of current network
    func reevaluateNetwork(reply: @escaping (Bool, Error?) -> Void)
}

// MARK: - Data Transfer Objects

/// Filter status information
public struct FilterStatus: Codable {
    public let isEnabled: Bool
    public let currentNetworkTrusted: Bool
    public let blockedConnectionCount: Int
    public let allowedConnectionCount: Int
    public let totalBytesBlocked: Int64
    public let totalBytesAllowed: Int64
    public let uptimeSeconds: TimeInterval
    public let lastUpdateDate: Date
    
    public init(isEnabled: Bool = false,
                currentNetworkTrusted: Bool = false,
                blockedConnectionCount: Int = 0,
                allowedConnectionCount: Int = 0,
                totalBytesBlocked: Int64 = 0,
                totalBytesAllowed: Int64 = 0,
                uptimeSeconds: TimeInterval = 0,
                lastUpdateDate: Date = Date()) {
        self.isEnabled = isEnabled
        self.currentNetworkTrusted = currentNetworkTrusted
        self.blockedConnectionCount = blockedConnectionCount
        self.allowedConnectionCount = allowedConnectionCount
        self.totalBytesBlocked = totalBytesBlocked
        self.totalBytesAllowed = totalBytesAllowed
        self.uptimeSeconds = uptimeSeconds
        self.lastUpdateDate = lastUpdateDate
    }
}

/// XPC Service names
public struct XPCServiceNames {
    /// Main app to extension service name
    public static let filterControl = "com.lowdata.filter-control"
    
    /// Mach service name for the system extension
    public static let systemExtension = "com.lowdata.system-extension"
}

// MARK: - XPC Errors

public enum XPCError: LocalizedError {
    case connectionFailed
    case serviceNotAvailable
    case encodingError
    case decodingError
    case unauthorized
    case timeout
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to establish XPC connection"
        case .serviceNotAvailable:
            return "XPC service is not available"
        case .encodingError:
            return "Failed to encode data for XPC transfer"
        case .decodingError:
            return "Failed to decode XPC response data"
        case .unauthorized:
            return "Not authorized to communicate with system extension"
        case .timeout:
            return "XPC request timed out"
        }
    }
}