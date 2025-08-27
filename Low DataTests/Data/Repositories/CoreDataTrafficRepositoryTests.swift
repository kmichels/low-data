//
//  CoreDataTrafficRepositoryTests.swift
//  Low DataTests
//
//  Created by Konrad Michels on 8/27/25.
//

import XCTest
import CoreData
@testable import Low_Data

final class CoreDataTrafficRepositoryTests: XCTestCase {
    
    var repository: CoreDataTrafficRepository!
    var profileRepository: CoreDataProcessProfileRepository!
    var testContainer: NSPersistentContainer!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create in-memory container for testing
        testContainer = NSPersistentContainer(name: "Low_Data")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        testContainer.persistentStoreDescriptions = [description]
        
        let expectation = expectation(description: "Core Data stack loaded")
        testContainer.loadPersistentStores { _, error in
            XCTAssertNil(error)
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)
        
        repository = CoreDataTrafficRepository(container: testContainer)
        profileRepository = CoreDataProcessProfileRepository(container: testContainer)
    }
    
    override func tearDown() async throws {
        repository = nil
        profileRepository = nil
        testContainer = nil
        try await super.tearDown()
    }
    
    // MARK: - Save Tests
    
    func test_save_createsObservation() async throws {
        let process = ProcessIdentity(type: .application, name: "TestApp", bundleId: "com.test.app")
        let observation = TrafficObservation(
            process: process,
            bytesIn: 1000,
            bytesOut: 500,
            networkType: .untrusted,
            networkQuality: .good
        )
        
        try await repository.save(observation)
        
        let count = try await repository.getObservationCount()
        XCTAssertEqual(count, 1)
    }
    
    func test_saveBatch_createsMultipleObservations() async throws {
        let process = ProcessIdentity(type: .application, name: "TestApp")
        let observations = (0..<10).map { i in
            TrafficObservation(
                process: process,
                bytesIn: UInt64(i * 100),
                bytesOut: UInt64(i * 50),
                networkType: .untrusted,
                networkQuality: .good
            )
        }
        
        try await repository.saveBatch(observations)
        
        let count = try await repository.getObservationCount()
        XCTAssertEqual(count, 10)
    }
    
    // MARK: - Fetch Tests
    
    func test_fetchObservations_forProcess() async throws {
        let process1 = ProcessIdentity(type: .application, name: "App1", bundleId: "com.test.app1")
        let process2 = ProcessIdentity(type: .application, name: "App2", bundleId: "com.test.app2")
        
        // Save observations for both processes
        for i in 0..<5 {
            try await repository.save(TrafficObservation(
                process: process1,
                bytesIn: UInt64(i * 100),
                bytesOut: 50,
                networkType: .untrusted,
                networkQuality: .good
            ))
            
            try await repository.save(TrafficObservation(
                process: process2,
                bytesIn: 100,
                bytesOut: UInt64(i * 50),
                networkType: .trusted,
                networkQuality: .excellent
            ))
        }
        
        let observations = try await repository.fetchObservations(for: process1, limit: 10)
        XCTAssertEqual(observations.count, 5)
        XCTAssertTrue(observations.allSatisfy { $0.process.name == "App1" })
    }
    
    func test_fetchObservations_byDateRange() async throws {
        let process = ProcessIdentity(type: .application, name: "TestApp")
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        
        // Save observation for today
        try await repository.save(TrafficObservation(
            timestamp: now,
            process: process,
            bytesIn: 1000,
            bytesOut: 500,
            networkType: .untrusted,
            networkQuality: .good
        ))
        
        // Fetch for date range including today
        let observations = try await repository.fetchObservations(from: yesterday, to: tomorrow)
        XCTAssertEqual(observations.count, 1)
        
        // Fetch for date range excluding today
        let emptyObservations = try await repository.fetchObservations(
            from: Calendar.current.date(byAdding: .day, value: -10, to: now)!,
            to: Calendar.current.date(byAdding: .day, value: -2, to: now)!
        )
        XCTAssertEqual(emptyObservations.count, 0)
    }
    
    // MARK: - Statistics Tests
    
    func test_getStatistics() async throws {
        let process1 = ProcessIdentity(type: .application, name: "HighBandwidth")
        let process2 = ProcessIdentity(type: .application, name: "LowBandwidth")
        
        let now = Date()
        let observations = [
            TrafficObservation(
                timestamp: now,
                process: process1,
                bytesIn: 1_000_000,
                bytesOut: 500_000,
                networkType: .untrusted,
                networkQuality: .good
            ),
            TrafficObservation(
                timestamp: now,
                process: process2,
                bytesIn: 10_000,
                bytesOut: 5_000,
                networkType: .untrusted,
                networkQuality: .good
            )
        ]
        
        try await repository.saveBatch(observations)
        
        let stats = try await repository.getStatistics(
            from: Calendar.current.date(byAdding: .hour, value: -1, to: now)!,
            to: Calendar.current.date(byAdding: .hour, value: 1, to: now)!
        )
        
        XCTAssertEqual(stats.totalBytesAllowed, 1_515_000)
        XCTAssertEqual(stats.allowedConnectionCount, 2)
        XCTAssertEqual(stats.topAllowedProcesses.count, 2)
        XCTAssertEqual(stats.topAllowedProcesses.first?.0.name, "HighBandwidth")
    }
    
    // MARK: - Pruning Tests
    
    func test_pruneOldObservations() async throws {
        let process = ProcessIdentity(type: .application, name: "TestApp")
        let now = Date()
        let oldDate = Calendar.current.date(byAdding: .day, value: -60, to: now)!
        
        // Save old observation
        let oldObservation = TrafficObservation(
            timestamp: oldDate,
            process: process,
            bytesIn: 100,
            bytesOut: 50,
            networkType: .untrusted,
            networkQuality: .good
        )
        
        // Save recent observation
        let recentObservation = TrafficObservation(
            timestamp: now,
            process: process,
            bytesIn: 200,
            bytesOut: 100,
            networkType: .trusted,
            networkQuality: .excellent
        )
        
        try await repository.save(oldObservation)
        try await repository.save(recentObservation)
        
        // Verify both exist
        var count = try await repository.getObservationCount()
        XCTAssertEqual(count, 2)
        
        // Prune old observations
        let pruneDate = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        try await repository.pruneOldObservations(before: pruneDate)
        
        // Verify only recent observation remains
        count = try await repository.getObservationCount()
        XCTAssertEqual(count, 1)
        
        let remaining = try await repository.fetchObservations(for: process, limit: 10)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.bytesIn, 200)
    }
    
    // MARK: - Process Profile Tests
    
    func test_processProfile_save() async throws {
        let process = ProcessIdentity(
            type: .application,
            name: "TestApp",
            bundleId: "com.test.app",
            path: "/Applications/TestApp.app"
        )
        
        var profile = ProcessProfile(process: process)
        profile.averageBandwidth = 1_000_000
        profile.peakBandwidth = 5_000_000
        profile.totalBytesIn = 10_000_000
        profile.totalBytesOut = 5_000_000
        profile.observationCount = 100
        profile.isBursty = true
        
        try await profileRepository.save(profile)
        
        let fetched = try await profileRepository.fetch(for: process)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.averageBandwidth, 1_000_000)
        XCTAssertEqual(fetched?.peakBandwidth, 5_000_000)
        XCTAssertTrue(fetched?.isBursty ?? false)
    }
    
    func test_processProfile_fetchBandwidthIntensive() async throws {
        let highBandwidthProcess = ProcessIdentity(type: .application, name: "HighBandwidth")
        var highProfile = ProcessProfile(process: highBandwidthProcess)
        highProfile.averageBandwidth = 10_000_000 // 10 MB/s
        
        let lowBandwidthProcess = ProcessIdentity(type: .application, name: "LowBandwidth")
        var lowProfile = ProcessProfile(process: lowBandwidthProcess)
        lowProfile.averageBandwidth = 1_000 // 1 KB/s
        
        try await profileRepository.save(highProfile)
        try await profileRepository.save(lowProfile)
        
        let intensive = try await profileRepository.fetchBandwidthIntensive(threshold: 1_000_000)
        XCTAssertEqual(intensive.count, 1)
        XCTAssertEqual(intensive.first?.process.name, "HighBandwidth")
    }
    
    func test_processProfile_pruneInactive() async throws {
        let now = Date()
        let oldDate = Calendar.current.date(byAdding: .day, value: -60, to: now)!
        
        let oldProcess = ProcessIdentity(type: .application, name: "OldApp")
        var oldProfile = ProcessProfile(process: oldProcess)
        oldProfile.lastSeen = oldDate
        
        let recentProcess = ProcessIdentity(type: .application, name: "RecentApp")
        var recentProfile = ProcessProfile(process: recentProcess)
        recentProfile.lastSeen = now
        
        try await profileRepository.save(oldProfile)
        try await profileRepository.save(recentProfile)
        
        let pruneDate = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        try await profileRepository.pruneInactive(before: pruneDate)
        
        let remaining = try await profileRepository.fetchAll()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.process.name, "RecentApp")
    }
}