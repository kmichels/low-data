//
//  TrafficDataRepository.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation

/// Repository protocol for managing traffic observations and statistics
public protocol TrafficDataRepository {
    /// Save a traffic observation
    func save(_ observation: TrafficObservation) async throws
    
    /// Save multiple observations in batch
    func saveBatch(_ observations: [TrafficObservation]) async throws
    
    /// Fetch observations for a specific process
    func fetchObservations(for process: ProcessIdentity, limit: Int) async throws -> [TrafficObservation]
    
    /// Fetch observations within a time range
    func fetchObservations(from startDate: Date, to endDate: Date) async throws -> [TrafficObservation]
    
    /// Get traffic statistics for a time period
    func getStatistics(from startDate: Date, to endDate: Date) async throws -> TrafficStatistics
    
    /// Clean up old observations
    func pruneOldObservations(before date: Date) async throws
    
    /// Get the total number of observations
    func getObservationCount() async throws -> Int
}

/// Repository protocol for managing process profiles
public protocol ProcessProfileRepository {
    /// Save or update a process profile
    func save(_ profile: ProcessProfile) async throws
    
    /// Fetch a process profile
    func fetch(for process: ProcessIdentity) async throws -> ProcessProfile?
    
    /// Fetch all known process profiles
    func fetchAll() async throws -> [ProcessProfile]
    
    /// Fetch profiles that match certain criteria
    func fetchBandwidthIntensive(threshold: Double) async throws -> [ProcessProfile]
    
    /// Delete old profiles not seen recently
    func pruneInactive(before date: Date) async throws
}

/// Errors that can occur in traffic data operations
public enum TrafficDataError: LocalizedError {
    case observationNotFound
    case invalidDateRange
    case dataCorrupted
    case quotaExceeded(Int)
    case persistenceError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .observationNotFound:
            return "Traffic observation not found"
        case .invalidDateRange:
            return "Invalid date range specified"
        case .dataCorrupted:
            return "Traffic data is corrupted"
        case .quotaExceeded(let limit):
            return "Observation quota exceeded: \(limit)"
        case .persistenceError(let error):
            return "Failed to persist traffic data: \(error.localizedDescription)"
        }
    }
}