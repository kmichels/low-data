//
//  ProcessIdentity.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation

/// Represents the identity of a process making network connections
public struct ProcessIdentity: Equatable, Hashable, Codable {
    public let type: ProcessType
    public let name: String
    public let bundleId: String?
    public let path: String?
    public let pid: pid_t?
    
    public init(
        type: ProcessType,
        name: String,
        bundleId: String? = nil,
        path: String? = nil,
        pid: pid_t? = nil
    ) {
        self.type = type
        self.name = name
        self.bundleId = bundleId
        self.path = path
        self.pid = pid
    }
    
    /// Unique identifier for this process
    public var identifier: String {
        switch type {
        case .application:
            return bundleId ?? name
        case .brewService, .system, .daemon:
            return path ?? name
        case .unknown:
            return "unknown.\(name)"
        }
    }
    
    /// Display name suitable for UI
    public var displayName: String {
        switch type {
        case .application:
            return name
        case .brewService:
            return "\(name) (Homebrew)"
        case .system:
            return "\(name) (System)"
        case .daemon:
            return "\(name) (Daemon)"
        case .unknown:
            return "\(name) (Unknown)"
        }
    }
    
    /// Whether this process is likely to use high bandwidth
    public var isLikelyBandwidthIntensive: Bool {
        // Common bandwidth-heavy processes
        let heavyProcesses = [
            "Dropbox", "Google Drive", "OneDrive", "iCloud",
            "Photos", "Creative Cloud", "Spotify", "Music",
            "TV", "Netflix", "YouTube", "Prime Video",
            "Slack", "Discord", "Zoom", "Teams",
            "Docker", "node", "npm", "yarn"
        ]
        
        return heavyProcesses.contains { name.contains($0) }
    }
}

/// Types of processes that can make network connections
public enum ProcessType: String, Codable {
    case application    // Regular macOS applications
    case brewService    // Homebrew services
    case system        // System processes
    case daemon        // Background daemons
    case unknown       // Unidentified processes
    
    public var defaultAction: RuleAction {
        switch self {
        case .application:
            return .askUser
        case .brewService:
            return .block  // Conservative default for brew services
        case .system:
            return .allow  // System processes usually needed
        case .daemon:
            return .askUser
        case .unknown:
            return .block  // Conservative for unknown
        }
    }
}

/// Profile of a process based on observed behavior
public struct ProcessProfile: Codable {
    public let process: ProcessIdentity
    public var observationCount: Int
    public var averageBandwidth: Double  // Bytes per second
    public var peakBandwidth: Double
    public var totalBytesIn: UInt64
    public var totalBytesOut: UInt64
    public var lastSeen: Date
    public var isBursty: Bool
    public var commonPorts: Set<Int>
    
    public init(process: ProcessIdentity) {
        self.process = process
        self.observationCount = 0
        self.averageBandwidth = 0
        self.peakBandwidth = 0
        self.totalBytesIn = 0
        self.totalBytesOut = 0
        self.lastSeen = Date()
        self.isBursty = false
        self.commonPorts = []
    }
    
    public mutating func addObservation(_ observation: TrafficObservation) {
        let bandwidth = Double(observation.bytesIn + observation.bytesOut)
        
        // Update running average
        let newCount = observationCount + 1
        averageBandwidth = (averageBandwidth * Double(observationCount) + bandwidth) / Double(newCount)
        
        // Update peak
        if bandwidth > peakBandwidth {
            peakBandwidth = bandwidth
        }
        
        // Update totals
        totalBytesIn += observation.bytesIn
        totalBytesOut += observation.bytesOut
        observationCount = newCount
        lastSeen = observation.timestamp
        
        // Detect burstiness (simplified - bandwidth spike > 5x average)
        if bandwidth > averageBandwidth * 5 && observationCount > 10 {
            isBursty = true
        }
    }
}