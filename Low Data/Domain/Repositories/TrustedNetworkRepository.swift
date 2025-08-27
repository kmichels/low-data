//
//  TrustedNetworkRepository.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation

/// Repository protocol for managing trusted networks
public protocol TrustedNetworkRepository {
    /// Fetch all trusted networks
    func fetchAll() async throws -> [TrustedNetwork]
    
    /// Fetch a specific trusted network by ID
    func fetch(by id: UUID) async throws -> TrustedNetwork?
    
    /// Save a trusted network
    func save(_ network: TrustedNetwork) async throws
    
    /// Delete a trusted network
    func delete(_ network: TrustedNetwork) async throws
    
    /// Check if a detected network is trusted
    func isTrusted(_ network: DetectedNetwork) async throws -> Bool
    
    /// Find matching trusted network for a detected network
    func findMatch(for network: DetectedNetwork) async throws -> TrustedNetwork?
}

/// Errors that can occur in trusted network operations
public enum TrustedNetworkError: LocalizedError {
    case networkNotFound(UUID)
    case duplicateNetwork(String)
    case invalidConfiguration(String)
    case persistenceError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .networkNotFound(let id):
            return "Trusted network not found: \(id)"
        case .duplicateNetwork(let name):
            return "A trusted network named '\(name)' already exists"
        case .invalidConfiguration(let reason):
            return "Invalid network configuration: \(reason)"
        case .persistenceError(let error):
            return "Failed to save network: \(error.localizedDescription)"
        }
    }
}