//
//  MockRepositories.swift
//  Low DataTests
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
@testable import Low_Data

// MARK: - Mock TrustedNetworkRepository

actor MockTrustedNetworkRepository: TrustedNetworkRepository {
    var networks: [TrustedNetwork] = []
    var shouldThrowError = false
    var fetchAllCallCount = 0
    var saveCallCount = 0
    var deleteCallCount = 0
    
    func fetchAll() async throws -> [TrustedNetwork] {
        fetchAllCallCount += 1
        if shouldThrowError {
            throw TrustedNetworkError.persistenceError(MockError.testError)
        }
        return networks
    }
    
    func fetch(by id: UUID) async throws -> TrustedNetwork? {
        if shouldThrowError {
            throw TrustedNetworkError.networkNotFound(id)
        }
        return networks.first { $0.id == id }
    }
    
    func save(_ network: TrustedNetwork) async throws {
        saveCallCount += 1
        if shouldThrowError {
            throw TrustedNetworkError.persistenceError(MockError.testError)
        }
        
        if let index = networks.firstIndex(where: { $0.id == network.id }) {
            networks[index] = network
        } else {
            networks.append(network)
        }
    }
    
    func delete(_ network: TrustedNetwork) async throws {
        deleteCallCount += 1
        if shouldThrowError {
            throw TrustedNetworkError.persistenceError(MockError.testError)
        }
        networks.removeAll { $0.id == network.id }
    }
    
    func isTrusted(_ network: DetectedNetwork) async throws -> Bool {
        if shouldThrowError {
            throw TrustedNetworkError.persistenceError(MockError.testError)
        }
        return networks.contains { $0.matches(network) }
    }
    
    func findMatch(for network: DetectedNetwork) async throws -> TrustedNetwork? {
        if shouldThrowError {
            throw TrustedNetworkError.persistenceError(MockError.testError)
        }
        return networks.first { $0.matches(network) }
    }
}

// MARK: - Mock TrafficDataRepository

actor MockTrafficDataRepository: TrafficDataRepository {
    var observations: [TrafficObservation] = []
    var shouldThrowError = false
    var saveCallCount = 0
    var saveBatchCallCount = 0
    
    func save(_ observation: TrafficObservation) async throws {
        saveCallCount += 1
        if shouldThrowError {
            throw TrafficDataError.persistenceError(MockError.testError)
        }
        observations.append(observation)
    }
    
    func saveBatch(_ observations: [TrafficObservation]) async throws {
        saveBatchCallCount += 1
        if shouldThrowError {
            throw TrafficDataError.persistenceError(MockError.testError)
        }
        self.observations.append(contentsOf: observations)
    }
    
    func fetchObservations(for process: ProcessIdentity, limit: Int) async throws -> [TrafficObservation] {
        if shouldThrowError {
            throw TrafficDataError.observationNotFound
        }
        return Array(observations
            .filter { $0.process == process }
            .prefix(limit))
    }
    
    func fetchObservations(from startDate: Date, to endDate: Date) async throws -> [TrafficObservation] {
        if shouldThrowError {
            throw TrafficDataError.invalidDateRange
        }
        return observations.filter { 
            $0.timestamp >= startDate && $0.timestamp <= endDate 
        }
    }
    
    func getStatistics(from startDate: Date, to endDate: Date) async throws -> TrafficStatistics {
        if shouldThrowError {
            throw TrafficDataError.dataCorrupted
        }
        
        let periodObservations = observations.filter {
            $0.timestamp >= startDate && $0.timestamp <= endDate
        }
        
        return TrafficStatistics(
            periodStart: startDate,
            periodEnd: endDate,
            totalBytesBlocked: 0,
            totalBytesAllowed: periodObservations.reduce(0) { $0 + $1.totalBytes },
            blockedConnectionCount: 0,
            allowedConnectionCount: periodObservations.count,
            topBlockedProcesses: [],
            topAllowedProcesses: []
        )
    }
    
    func pruneOldObservations(before date: Date) async throws {
        if shouldThrowError {
            throw TrafficDataError.persistenceError(MockError.testError)
        }
        observations.removeAll { $0.timestamp < date }
    }
    
    func getObservationCount() async throws -> Int {
        if shouldThrowError {
            throw TrafficDataError.persistenceError(MockError.testError)
        }
        return observations.count
    }
}

// MARK: - Mock ProcessProfileRepository

actor MockProcessProfileRepository: ProcessProfileRepository {
    var profiles: [ProcessProfile] = []
    var shouldThrowError = false
    var saveCallCount = 0
    
    func save(_ profile: ProcessProfile) async throws {
        saveCallCount += 1
        if shouldThrowError {
            throw TrafficDataError.persistenceError(MockError.testError)
        }
        
        if let index = profiles.firstIndex(where: { $0.process == profile.process }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
    }
    
    func fetch(for process: ProcessIdentity) async throws -> ProcessProfile? {
        if shouldThrowError {
            throw TrafficDataError.observationNotFound
        }
        return profiles.first { $0.process == process }
    }
    
    func fetchAll() async throws -> [ProcessProfile] {
        if shouldThrowError {
            throw TrafficDataError.persistenceError(MockError.testError)
        }
        return profiles
    }
    
    func fetchBandwidthIntensive(threshold: Double) async throws -> [ProcessProfile] {
        if shouldThrowError {
            throw TrafficDataError.persistenceError(MockError.testError)
        }
        return profiles.filter { $0.averageBandwidth > threshold }
    }
    
    func pruneInactive(before date: Date) async throws {
        if shouldThrowError {
            throw TrafficDataError.persistenceError(MockError.testError)
        }
        profiles.removeAll { $0.lastSeen < date }
    }
}

// MARK: - Helper Error

enum MockError: Error {
    case testError
}