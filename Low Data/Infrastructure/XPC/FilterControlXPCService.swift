//
//  FilterControlXPCService.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
import OSLog

/// XPC service for communication from main app to system extension
@MainActor
public final class FilterControlXPCService: NSObject {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.lowdata", category: "FilterControlXPCService")
    private var connection: NSXPCConnection?
    private var proxy: FilterControlXPCProtocol?
    private let connectionLock = NSLock()
    
    // MARK: - Singleton
    
    public static let shared = FilterControlXPCService()
    
    private override init() {
        super.init()
    }
    
    // MARK: - Connection Management
    
    private func establishConnection() throws -> FilterControlXPCProtocol {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        
        // Check if we have a valid connection
        if let existingProxy = proxy {
            return existingProxy
        }
        
        // Create new connection
        let newConnection = NSXPCConnection(machServiceName: XPCServiceNames.systemExtension, options: .privileged)
        
        // Configure the connection
        newConnection.remoteObjectInterface = NSXPCInterface(with: FilterControlXPCProtocol.self)
        
        // Set interruption handler
        newConnection.interruptionHandler = { [weak self] in
            self?.logger.warning("XPC connection interrupted")
            self?.connectionLock.lock()
            self?.proxy = nil
            self?.connection = nil
            self?.connectionLock.unlock()
        }
        
        // Set invalidation handler
        newConnection.invalidationHandler = { [weak self] in
            self?.logger.warning("XPC connection invalidated")
            self?.connectionLock.lock()
            self?.proxy = nil
            self?.connection = nil
            self?.connectionLock.unlock()
        }
        
        // Resume the connection
        newConnection.resume()
        
        // Get proxy object
        guard let remoteProxy = newConnection.remoteObjectProxyWithErrorHandler({ [weak self] error in
            self?.logger.error("Failed to get remote object proxy: \(error.localizedDescription)")
        }) as? FilterControlXPCProtocol else {
            throw XPCError.connectionFailed
        }
        
        // Store connection and proxy
        self.connection = newConnection
        self.proxy = remoteProxy
        
        logger.info("XPC connection established successfully")
        
        return remoteProxy
    }
    
    // MARK: - Configuration Methods
    
    public func updateTrustedNetworks(_ networks: [TrustedNetwork]) async throws -> Bool {
        let service = try establishConnection()
        
        // Encode networks
        let encoder = JSONEncoder()
        let data = try encoder.encode(networks)
        
        return try await withCheckedThrowingContinuation { continuation in
            service.updateTrustedNetworks(data) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    public func updateFilterRules(_ rules: [ProcessRule]) async throws -> Bool {
        let service = try establishConnection()
        
        // Encode rules
        let encoder = JSONEncoder()
        let data = try encoder.encode(rules)
        
        return try await withCheckedThrowingContinuation { continuation in
            service.updateFilterRules(data) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    public func setFilteringEnabled(_ enabled: Bool) async throws -> Bool {
        let service = try establishConnection()
        
        return try await withCheckedThrowingContinuation { continuation in
            service.setFilteringEnabled(enabled) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    // MARK: - Status Methods
    
    public func getFilterStatus() async throws -> FilterStatus {
        let service = try establishConnection()
        
        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
            service.getFilterStatus { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
        
        guard let statusData = data else {
            throw XPCError.decodingError
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(FilterStatus.self, from: statusData)
    }
    
    public func getCurrentNetwork() async throws -> DetectedNetwork? {
        let service = try establishConnection()
        
        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
            service.getCurrentNetwork { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
        
        guard let networkData = data else {
            return nil
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(DetectedNetwork.self, from: networkData)
    }
    
    public func getStatistics() async throws -> TrafficStatistics {
        let service = try establishConnection()
        
        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
            service.getStatistics { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
        
        guard let statsData = data else {
            throw XPCError.decodingError
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(TrafficStatistics.self, from: statsData)
    }
    
    // MARK: - Traffic Monitoring Methods
    
    public func getRecentTraffic(limit: Int = 100) async throws -> [TrafficObservation] {
        let service = try establishConnection()
        
        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
            service.getRecentTraffic(limit: limit) { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
        
        guard let trafficData = data else {
            throw XPCError.decodingError
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode([TrafficObservation].self, from: trafficData)
    }
    
    public func getTrafficForProcess(_ processIdentifier: String) async throws -> [TrafficObservation] {
        let service = try establishConnection()
        
        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
            service.getTrafficForProcess(processIdentifier) { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
        
        guard let trafficData = data else {
            throw XPCError.decodingError
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode([TrafficObservation].self, from: trafficData)
    }
    
    // MARK: - Control Methods
    
    public func clearStatistics() async throws -> Bool {
        let service = try establishConnection()
        
        return try await withCheckedThrowingContinuation { continuation in
            service.clearStatistics { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    public func reevaluateNetwork() async throws -> Bool {
        let service = try establishConnection()
        
        return try await withCheckedThrowingContinuation { continuation in
            service.reevaluateNetwork { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    // MARK: - Connection Validation
    
    public func validateConnection() async -> Bool {
        do {
            _ = try establishConnection()
            return true
        } catch {
            logger.error("Failed to validate XPC connection: \(error.localizedDescription)")
            return false
        }
    }
    
    public func disconnect() {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        
        connection?.invalidate()
        connection = nil
        proxy = nil
        
        logger.info("XPC connection disconnected")
    }
}

// MARK: - Supporting Types

/// Traffic statistics from the filter
public struct TrafficStatistics: Codable {
    public let totalBlocked: Int64
    public let totalAllowed: Int64
    public let topBlockedProcesses: [(identifier: String, count: Int)]
    public let topAllowedProcesses: [(identifier: String, count: Int)]
    public let startDate: Date
    public let lastUpdateDate: Date
}