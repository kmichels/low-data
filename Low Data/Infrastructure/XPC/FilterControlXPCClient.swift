//
//  FilterControlXPCClient.swift
//  Low Data
//
//  Created on 8/28/25.
//

import Foundation
import os.log

/// Client for communicating with the System Extension via XPC
@MainActor
public final class FilterControlXPCClient: ObservableObject {
    
    // MARK: - Properties
    
    @Published public private(set) var isConnected = false
    @Published public private(set) var filterStatus: FilterStatus?
    @Published public private(set) var currentNetwork: DetectedNetwork?
    
    private var connection: NSXPCConnection?
    private let serviceName = "com.tonalphoto.tech.Low-Data.Low-Data-Extensino.xpc"
    private let logger = Logger(subsystem: "com.tonalphoto.tech.Low-Data", category: "XPCClient")
    
    // MARK: - Singleton
    
    public static let shared = FilterControlXPCClient()
    
    private init() {
        setupConnection()
    }
    
    // MARK: - Public Methods
    
    /// Establishes connection to the System Extension
    public func connect() {
        guard connection == nil else { return }
        setupConnection()
    }
    
    /// Disconnects from the System Extension
    public func disconnect() {
        connection?.invalidate()
        connection = nil
        isConnected = false
    }
    
    /// Updates trusted networks in the extension
    public func updateTrustedNetworks(_ networks: [TrustedNetwork]) async throws {
        let service = try getService()
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(networks)
        
        return try await withCheckedThrowingContinuation { continuation in
            service.updateTrustedNetworks(data) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? XPCError.unknownError)
                }
            }
        }
    }
    
    /// Updates filter rules in the extension
    public func updateFilterRules(_ rules: [ProcessRule]) async throws {
        let service = try getService()
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(rules)
        
        return try await withCheckedThrowingContinuation { continuation in
            service.updateFilterRules(data) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? XPCError.unknownError)
                }
            }
        }
    }
    
    /// Enables or disables filtering
    public func setFilteringEnabled(_ enabled: Bool) async throws {
        let service = try getService()
        
        return try await withCheckedThrowingContinuation { continuation in
            service.setFilteringEnabled(enabled) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? XPCError.unknownError)
                }
            }
        }
    }
    
    /// Gets current filter status
    public func fetchFilterStatus() async throws {
        let service = try getService()
        
        let data = try await withCheckedThrowingContinuation { continuation in
            service.getFilterStatus { data, error in
                if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? XPCError.noData)
                }
            }
        }
        
        let decoder = JSONDecoder()
        self.filterStatus = try decoder.decode(FilterStatus.self, from: data)
    }
    
    /// Gets recent traffic observations
    public func getTrafficObservations(limit: Int = 100) async throws -> [TrafficObservation] {
        let service = try getService()
        
        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            service.getRecentTraffic(limit: limit) { data, error in
                if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? XPCError.noData)
                }
            }
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode([TrafficObservation].self, from: data)
    }
    
    /// Gets traffic statistics
    public func getTrafficStatistics() async throws -> FilterTrafficStatistics {
        let service = try getService()
        
        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            service.getStatistics { data, error in
                if let data = data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? XPCError.noData)
                }
            }
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(FilterTrafficStatistics.self, from: data)
    }
    
    /// Gets process profiles
    public func getProcessProfiles() async throws -> [ProcessProfile] {
        // This method isn't available in the extension yet
        // Return empty array for now
        return []
    }
    
    /// Forces network re-evaluation
    public func reevaluateNetwork() async throws {
        let service = try getService()
        
        return try await withCheckedThrowingContinuation { continuation in
            service.reevaluateNetwork { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? XPCError.unknownError)
                }
            }
        }
    }
    
    /// Clears statistics
    public func clearStatistics() async throws {
        let service = try getService()
        
        return try await withCheckedThrowingContinuation { continuation in
            service.clearStatistics { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? XPCError.unknownError)
                }
            }
        }
    }
    
    /// Gets current network information
    public func fetchCurrentNetwork() async throws {
        let service = try getService()
        
        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            service.getCurrentNetwork { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data {
                    continuation.resume(returning: data)
                } else {
                    // No network detected is valid
                    continuation.resume(throwing: XPCError.noData)
                }
            }
        }
        
        let decoder = JSONDecoder()
        self.currentNetwork = try decoder.decode(DetectedNetwork.self, from: data)
    }
    
    // MARK: - Private Methods
    
    private func setupConnection() {
        logger.info("Setting up XPC connection to extension")
        
        let newConnection = NSXPCConnection(serviceName: serviceName)
        newConnection.remoteObjectInterface = NSXPCInterface(with: FilterControlXPCProtocol.self)
        
        newConnection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.logger.warning("XPC connection invalidated")
                self?.isConnected = false
                self?.connection = nil
            }
        }
        
        newConnection.interruptionHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.logger.warning("XPC connection interrupted")
                self?.isConnected = false
                // Try to reconnect after interruption
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self?.setupConnection()
                }
            }
        }
        
        newConnection.resume()
        connection = newConnection
        isConnected = true
        
        logger.info("XPC connection established")
    }
    
    private func getService() throws -> FilterControlXPCProtocol {
        guard let connection = connection else {
            throw XPCError.notConnected
        }
        
        guard isConnected else {
            setupConnection()
            guard let connection = self.connection else {
                throw XPCError.notConnected
            }
            return connection.remoteObjectProxy as! FilterControlXPCProtocol
        }
        
        return connection.remoteObjectProxy as! FilterControlXPCProtocol
    }
}

// MARK: - XPC Errors

public enum XPCError: LocalizedError {
    case notConnected
    case noData
    case unknownError
    case connectionFailed
    case decodingError
    case encodingError
    
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to System Extension"
        case .noData:
            return "No data received from extension"
        case .unknownError:
            return "An unknown error occurred"
        case .connectionFailed:
            return "Failed to establish XPC connection"
        case .decodingError:
            return "Failed to decode XPC response"
        case .encodingError:
            return "Failed to encode data for XPC"
        }
    }
}