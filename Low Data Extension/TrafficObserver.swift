//
//  TrafficObserver.swift
//  Low Data Extension
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
import OSLog

/// Observes and records network traffic for analysis
final class TrafficObserver {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.lowdata.extension", category: "TrafficObserver")
    
    // Statistics
    private(set) var blockedConnectionCount: Int = 0
    private(set) var allowedConnectionCount: Int = 0
    private(set) var totalBytesBlocked: Int64 = 0
    private(set) var totalBytesAllowed: Int64 = 0
    
    // Circular buffer for recent observations (memory-efficient)
    private var observations: CircularBuffer<TrafficObservation>
    private let maxObservations = 10_000
    
    // Per-flow byte tracking
    private var flowBytes: [FlowKey: FlowByteCount] = [:]
    private let flowBytesLock = NSLock()
    
    // Per-process statistics
    private var processStats: [String: ProcessStatistics] = [:]
    private let processStatsLock = NSLock()
    
    // Timing
    private let startTime = Date()
    
    // MARK: - Initialization
    
    init() {
        self.observations = CircularBuffer(capacity: maxObservations)
        logger.info("TrafficObserver initialized with capacity: \(maxObservations)")
    }
    
    // MARK: - Public Methods
    
    func record(_ observation: TrafficObservation) {
        observations.append(observation)
        
        // Update process statistics
        updateProcessStatistics(for: observation)
        
        // Log periodically
        if observations.count % 1000 == 0 {
            logger.info("Recorded \(observations.count) observations")
        }
    }
    
    func recordBytes(inbound: Int64, for flowKey: FlowKey) {
        flowBytesLock.lock()
        defer { flowBytesLock.unlock() }
        
        if flowBytes[flowKey] == nil {
            flowBytes[flowKey] = FlowByteCount()
        }
        
        flowBytes[flowKey]?.bytesIn += inbound
        totalBytesAllowed += inbound
    }
    
    func recordBytes(outbound: Int64, for flowKey: FlowKey) {
        flowBytesLock.lock()
        defer { flowBytesLock.unlock() }
        
        if flowBytes[flowKey] == nil {
            flowBytes[flowKey] = FlowByteCount()
        }
        
        flowBytes[flowKey]?.bytesOut += outbound
        totalBytesAllowed += outbound
    }
    
    func recordBlocked(bytes: Int64) {
        totalBytesBlocked += bytes
        blockedConnectionCount += 1
    }
    
    func recordAllowed() {
        allowedConnectionCount += 1
    }
    
    func getRecentObservations(limit: Int) -> [TrafficObservation] {
        return observations.toArray().suffix(limit).map { $0 }
    }
    
    func getObservationsForProcess(_ processId: String) -> [TrafficObservation] {
        return observations.toArray().filter { $0.processIdentifier == processId }
    }
    
    func getStatistics() -> FilterTrafficStatistics {
        processStatsLock.lock()
        defer { processStatsLock.unlock() }
        
        // Get top processes by bytes
        let sortedByBlocked = processStats
            .sorted { $0.value.bytesBlocked > $1.value.bytesBlocked }
            .prefix(10)
            .map { ProcessCount(identifier: $0.key, count: Int($0.value.bytesBlocked)) }
        
        let sortedByAllowed = processStats
            .sorted { $0.value.bytesAllowed > $1.value.bytesAllowed }
            .prefix(10)
            .map { ProcessCount(identifier: $0.key, count: Int($0.value.bytesAllowed)) }
        
        return FilterTrafficStatistics(
            totalBlocked: totalBytesBlocked,
            totalAllowed: totalBytesAllowed,
            topBlockedProcesses: sortedByBlocked,
            topAllowedProcesses: sortedByAllowed,
            startDate: startTime,
            lastUpdateDate: Date()
        )
    }
    
    func clearStatistics() {
        observations.clear()
        
        flowBytesLock.lock()
        flowBytes.removeAll()
        flowBytesLock.unlock()
        
        processStatsLock.lock()
        processStats.removeAll()
        processStatsLock.unlock()
        
        blockedConnectionCount = 0
        allowedConnectionCount = 0
        totalBytesBlocked = 0
        totalBytesAllowed = 0
        
        logger.info("Statistics cleared")
    }
    
    var uptimeSeconds: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
    
    // MARK: - Private Methods
    
    private func updateProcessStatistics(for observation: TrafficObservation) {
        processStatsLock.lock()
        defer { processStatsLock.unlock() }
        
        let processId = observation.processIdentifier
        
        if processStats[processId] == nil {
            processStats[processId] = ProcessStatistics()
        }
        
        processStats[processId]?.observationCount += 1
        processStats[processId]?.bytesAllowed += observation.bytesIn + observation.bytesOut
        processStats[processId]?.lastSeen = Date()
    }
    
    // MARK: - Persistence
    
    func saveToSharedContainer() async {
        // Save observations to App Groups container for main app access
        logger.info("Saving \(observations.count) observations to shared container")
        
        // TODO: Implement App Groups saving
        // For now, just log statistics
        let stats = getStatistics()
        logger.info("Stats - Blocked: \(stats.totalBlocked) bytes, Allowed: \(stats.totalAllowed) bytes")
    }
    
    func loadFromSharedContainer() async {
        // Load previous observations from App Groups container
        logger.info("Loading observations from shared container")
        
        // TODO: Implement App Groups loading
    }
}

// MARK: - Supporting Types

struct FlowByteCount {
    var bytesIn: Int64 = 0
    var bytesOut: Int64 = 0
}

struct ProcessStatistics {
    var observationCount: Int = 0
    var bytesBlocked: Int64 = 0
    var bytesAllowed: Int64 = 0
    var lastSeen: Date = Date()
}

// MARK: - Circular Buffer

struct CircularBuffer<T> {
    private var buffer: [T?]
    private var writeIndex = 0
    private var count = 0
    private let capacity: Int
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }
    
    mutating func append(_ element: T) {
        buffer[writeIndex] = element
        writeIndex = (writeIndex + 1) % capacity
        if count < capacity {
            count += 1
        }
    }
    
    func toArray() -> [T] {
        if count < capacity {
            // Buffer not full yet
            return buffer[0..<count].compactMap { $0 }
        } else {
            // Buffer is full, need to reconstruct in order
            let firstPart = buffer[writeIndex..<capacity].compactMap { $0 }
            let secondPart = buffer[0..<writeIndex].compactMap { $0 }
            return firstPart + secondPart
        }
    }
    
    mutating func clear() {
        buffer = Array(repeating: nil, count: capacity)
        writeIndex = 0
        count = 0
    }
    
    var isEmpty: Bool {
        return count == 0
    }
}