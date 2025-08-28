//
//  TrafficObserverTests.swift
//  Low DataTests
//
//  Created by Konrad Michels on 8/27/25.
//

import XCTest
import NetworkExtension
@testable import Low_Data

final class TrafficObserverTests: XCTestCase {
    
    var observer: TrafficObserver!
    
    override func setUp() {
        super.setUp()
        observer = TrafficObserver()
    }
    
    override func tearDown() {
        observer = nil
        super.tearDown()
    }
    
    // MARK: - Recording Tests
    
    func test_record_addsObservation() {
        // Given
        let process = ProcessIdentity(type: .application, name: "TestApp")
        let observation = TrafficObservation(
            process: process,
            bytesIn: 1000,
            bytesOut: 500,
            isTrustedNetwork: false
        )
        
        // When
        observer.record(observation)
        
        // Then
        let recent = observer.getRecentObservations(limit: 10)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.bytesIn, 1000)
    }
    
    func test_recordBytes_tracksInboundTraffic() {
        // Given
        let flowKey = FlowKey(
            remoteHost: "example.com",
            remotePort: "443",
            localPort: "12345",
            direction: .outbound
        )
        
        // When
        observer.recordBytes(inbound: 1000, for: flowKey)
        observer.recordBytes(inbound: 500, for: flowKey)
        
        // Then
        XCTAssertEqual(observer.totalBytesAllowed, 1500)
    }
    
    func test_recordBytes_tracksOutboundTraffic() {
        // Given
        let flowKey = FlowKey(
            remoteHost: "example.com",
            remotePort: "443",
            localPort: "12345",
            direction: .outbound
        )
        
        // When
        observer.recordBytes(outbound: 2000, for: flowKey)
        observer.recordBytes(outbound: 1000, for: flowKey)
        
        // Then
        XCTAssertEqual(observer.totalBytesAllowed, 3000)
    }
    
    func test_recordBlocked_updatesStatistics() {
        // When
        observer.recordBlocked(bytes: 5000)
        observer.recordBlocked(bytes: 3000)
        
        // Then
        XCTAssertEqual(observer.blockedConnectionCount, 2)
        XCTAssertEqual(observer.totalBytesBlocked, 8000)
    }
    
    func test_recordAllowed_incrementsCount() {
        // When
        observer.recordAllowed()
        observer.recordAllowed()
        observer.recordAllowed()
        
        // Then
        XCTAssertEqual(observer.allowedConnectionCount, 3)
    }
    
    // MARK: - Retrieval Tests
    
    func test_getRecentObservations_respectsLimit() {
        // Given - Add 20 observations
        let process = ProcessIdentity(type: .application, name: "TestApp")
        
        for i in 0..<20 {
            let observation = TrafficObservation(
                process: process,
                bytesIn: Int64(i * 100),
                bytesOut: Int64(i * 50),
                isTrustedNetwork: false
            )
            observer.record(observation)
        }
        
        // When
        let recent = observer.getRecentObservations(limit: 5)
        
        // Then
        XCTAssertEqual(recent.count, 5)
        // Should get the most recent ones
        XCTAssertEqual(recent.last?.bytesIn, 1900) // 19 * 100
    }
    
    func test_getObservationsForProcess_filtersCorrectly() {
        // Given
        let process1 = ProcessIdentity(type: .application, name: "App1", bundleId: "com.test.app1")
        let process2 = ProcessIdentity(type: .application, name: "App2", bundleId: "com.test.app2")
        
        observer.record(TrafficObservation(process: process1, bytesIn: 100, bytesOut: 50, isTrustedNetwork: false))
        observer.record(TrafficObservation(process: process2, bytesIn: 200, bytesOut: 100, isTrustedNetwork: false))
        observer.record(TrafficObservation(process: process1, bytesIn: 150, bytesOut: 75, isTrustedNetwork: false))
        
        // When
        let app1Observations = observer.getObservationsForProcess("com.test.app1")
        
        // Then
        XCTAssertEqual(app1Observations.count, 2)
        XCTAssertEqual(app1Observations[0].bytesIn, 100)
        XCTAssertEqual(app1Observations[1].bytesIn, 150)
    }
    
    // MARK: - Statistics Tests
    
    func test_getStatistics_returnsCorrectData() {
        // Given
        observer.recordBytes(inbound: 1000, for: createFlowKey("host1"))
        observer.recordBytes(outbound: 500, for: createFlowKey("host1"))
        observer.recordBlocked(bytes: 2000)
        
        // When
        let stats = observer.getStatistics()
        
        // Then
        XCTAssertEqual(stats.totalAllowed, 1500)
        XCTAssertEqual(stats.totalBlocked, 2000)
        XCTAssertNotNil(stats.startDate)
        XCTAssertNotNil(stats.lastUpdateDate)
    }
    
    func test_clearStatistics_resetsAllData() {
        // Given
        observer.recordBytes(inbound: 1000, for: createFlowKey("host1"))
        observer.recordBlocked(bytes: 500)
        observer.recordAllowed()
        
        let process = ProcessIdentity(type: .application, name: "TestApp")
        observer.record(TrafficObservation(process: process, bytesIn: 100, bytesOut: 50, isTrustedNetwork: false))
        
        // When
        observer.clearStatistics()
        
        // Then
        XCTAssertEqual(observer.totalBytesAllowed, 0)
        XCTAssertEqual(observer.totalBytesBlocked, 0)
        XCTAssertEqual(observer.blockedConnectionCount, 0)
        XCTAssertEqual(observer.allowedConnectionCount, 0)
        XCTAssertTrue(observer.getRecentObservations(limit: 10).isEmpty)
    }
    
    func test_uptimeSeconds_increasesOverTime() {
        // Given
        let initialUptime = observer.uptimeSeconds
        
        // When - wait a bit
        Thread.sleep(forTimeInterval: 0.1)
        let laterUptime = observer.uptimeSeconds
        
        // Then
        XCTAssertGreaterThan(laterUptime, initialUptime)
    }
    
    // MARK: - Circular Buffer Tests
    
    func test_circularBuffer_handlesOverflow() {
        // Given - Create a small buffer for testing
        var buffer = CircularBuffer<Int>(capacity: 5)
        
        // When - Add more than capacity
        for i in 0..<10 {
            buffer.append(i)
        }
        
        // Then - Should only have last 5 elements
        let array = buffer.toArray()
        XCTAssertEqual(array.count, 5)
        XCTAssertEqual(array, [5, 6, 7, 8, 9])
    }
    
    func test_circularBuffer_toArray_maintainsOrder() {
        // Given
        var buffer = CircularBuffer<String>(capacity: 3)
        
        // When
        buffer.append("first")
        buffer.append("second")
        buffer.append("third")
        buffer.append("fourth") // Overwrites "first"
        
        // Then
        let array = buffer.toArray()
        XCTAssertEqual(array, ["second", "third", "fourth"])
    }
    
    func test_circularBuffer_clear() {
        // Given
        var buffer = CircularBuffer<Int>(capacity: 5)
        for i in 0..<5 {
            buffer.append(i)
        }
        
        // When
        buffer.clear()
        
        // Then
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.toArray().count, 0)
    }
    
    // MARK: - Performance Tests
    
    func test_performance_recordingObservations() {
        let process = ProcessIdentity(type: .application, name: "TestApp")
        
        measure {
            for _ in 0..<1000 {
                let observation = TrafficObservation(
                    process: process,
                    bytesIn: Int64.random(in: 0...10000),
                    bytesOut: Int64.random(in: 0...5000),
                    isTrustedNetwork: Bool.random()
                )
                observer.record(observation)
            }
        }
    }
    
    func test_performance_getStatistics() {
        // Setup some data
        for i in 0..<100 {
            observer.recordBytes(inbound: Int64(i * 100), for: createFlowKey("host\(i)"))
        }
        
        measure {
            _ = observer.getStatistics()
        }
    }
    
    // MARK: - Helper Methods
    
    private func createFlowKey(_ host: String) -> FlowKey {
        return FlowKey(
            remoteHost: host,
            remotePort: "443",
            localPort: "12345",
            direction: .outbound
        )
    }
}