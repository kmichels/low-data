//
//  TrafficMonitoringUseCaseTests.swift
//  Low DataTests
//
//  Created by Konrad Michels on 8/27/25.
//

import XCTest
@testable import Low_Data

@MainActor
final class TrafficMonitoringUseCaseTests: XCTestCase {
    
    var trafficRepo: MockTrafficDataRepository!
    var processRepo: MockProcessProfileRepository!
    var recordUseCase: RecordTrafficObservationUseCase!
    var statsUseCase: GetTrafficStatisticsUseCase!
    var bandwidthUseCase: IdentifyBandwidthHogsUseCase!
    var cleanupUseCase: CleanupTrafficDataUseCase!
    
    override func setUp() async throws {
        try await super.setUp()
        
        trafficRepo = MockTrafficDataRepository()
        processRepo = MockProcessProfileRepository()
        
        recordUseCase = RecordTrafficObservationUseCase(
            trafficRepository: trafficRepo,
            processProfileRepository: processRepo
        )
        
        statsUseCase = GetTrafficStatisticsUseCase(
            trafficRepository: trafficRepo
        )
        
        bandwidthUseCase = IdentifyBandwidthHogsUseCase(
            processProfileRepository: processRepo
        )
        
        cleanupUseCase = CleanupTrafficDataUseCase(
            trafficRepository: trafficRepo,
            processProfileRepository: processRepo
        )
    }
    
    // MARK: - RecordTrafficObservationUseCase Tests
    
    func test_recordObservation_savesAndUpdatesProfile() async throws {
        // Given
        let process = ProcessIdentity(
            type: .application,
            name: "Test App"
        )
        
        let input = RecordTrafficObservationUseCase.Input(
            process: process,
            bytesIn: 1024 * 1024,  // 1MB
            bytesOut: 512 * 1024,   // 512KB
            networkType: .wifi,
            isTrusted: true
        )
        
        // When
        let observation = try await recordUseCase.execute(input)
        
        // Then
        XCTAssertEqual(observation.process.identifier, process.identifier)
        XCTAssertEqual(observation.bytesIn, 1024 * 1024)
        XCTAssertEqual(observation.bytesOut, 512 * 1024)
        
        // Verify repository calls
        let savedObservations = await trafficRepo.observations
        XCTAssertEqual(savedObservations.count, 1)
        
        let profiles = await processRepo.profiles
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.process.identifier, process.identifier)
    }
    
    func test_recordObservation_updatesExistingProfile() async throws {
        // Given - existing profile
        let process = ProcessIdentity(
            type: .application,
            name: "Existing App",
            bundleId: "com.existing.app"
        )
        
        let existingProfile = ProcessProfile(process: process)
        await processRepo.profiles.append(existingProfile)
        
        let input = RecordTrafficObservationUseCase.Input(
            process: process,
            bytesIn: 2048,
            bytesOut: 1024,
            networkType: .wifi,
            isTrusted: false
        )
        
        // When
        _ = try await recordUseCase.execute(input)
        
        // Then - profile should be updated, not duplicated
        let profiles = await processRepo.profiles
        XCTAssertEqual(profiles.count, 1)
        XCTAssertGreaterThan(profiles.first!.observationCount, 0)
    }
    
    // MARK: - GetTrafficStatisticsUseCase Tests
    
    func test_getStatistics_calculatesCorrectTotals() async throws {
        // Given - sample observations
        let now = Date()
        let observations = [
            TrafficObservation(
                process: ProcessIdentity(type: .application, name: "App 1", bundleId: "app1"),
                bytesIn: 1000,
                bytesOut: 500,
                packetsIn: 10,
                packetsOut: 5,
                networkType: .wifi,
                isTrustedNetwork: true
            ),
            TrafficObservation(
                process: ProcessIdentity(type: .application, name: "App 2", bundleId: "app2"),
                bytesIn: 2000,
                bytesOut: 1000,
                packetsIn: 20,
                packetsOut: 10,
                networkType: .cellular,
                isTrustedNetwork: false
            )
        ]
        
        await trafficRepo.observations.append(contentsOf: observations)
        
        let input = GetTrafficStatisticsUseCase.Input(
            startDate: now.addingTimeInterval(-3600),
            endDate: now.addingTimeInterval(3600),
            groupBy: .process
        )
        
        // When
        let stats = try await statsUseCase.execute(input)
        
        // Then
        XCTAssertEqual(stats.totalBytesIn, 3000)
        XCTAssertEqual(stats.totalBytesOut, 1500)
        XCTAssertEqual(stats.totalPackets, 45)
        XCTAssertEqual(stats.observationCount, 2)
        XCTAssertEqual(stats.groupedStats.count, 2)
        
        // Check grouped stats
        let app2Stats = stats.groupedStats.first { $0.key == "App 2" }
        XCTAssertNotNil(app2Stats)
        XCTAssertEqual(app2Stats?.bytesIn, 2000)
        XCTAssertEqual(app2Stats?.bytesOut, 1000)
    }
    
    func test_getStatistics_groupsByNetworkType() async throws {
        // Given
        let observations = [
            createObservation(networkType: .wifi, bytesIn: 1000, bytesOut: 500),
            createObservation(networkType: .wifi, bytesIn: 2000, bytesOut: 1000),
            createObservation(networkType: .cellular, bytesIn: 500, bytesOut: 250)
        ]
        
        await trafficRepo.observations.append(contentsOf: observations)
        
        let input = GetTrafficStatisticsUseCase.Input(
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date(),
            groupBy: .networkType
        )
        
        // When
        let stats = try await statsUseCase.execute(input)
        
        // Then
        XCTAssertEqual(stats.groupedStats.count, 2)
        
        let wifiStats = stats.groupedStats.first { $0.key == "wifi" }
        XCTAssertNotNil(wifiStats)
        XCTAssertEqual(wifiStats?.bytesIn, 3000)
        XCTAssertEqual(wifiStats?.observationCount, 2)
    }
    
    func test_getStatistics_throwsErrorForInvalidDateRange() async throws {
        // Given
        let input = GetTrafficStatisticsUseCase.Input(
            startDate: Date(),
            endDate: Date().addingTimeInterval(-3600), // End before start
            groupBy: .process
        )
        
        // When/Then
        do {
            _ = try await statsUseCase.execute(input)
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertTrue(error is UseCaseError)
        }
    }
    
    // MARK: - IdentifyBandwidthHogsUseCase Tests
    
    func test_identifyBandwidthHogs_findsHighUsageProcesses() async throws {
        // Given
        let highUsageProfile = ProcessProfile(
            process: ProcessIdentity(type: .application, name: "High Usage", bundleId: "com.high")
        )
        highUsageProfile.totalBytesIn = 100 * 1024 * 1024  // 100MB
        highUsageProfile.totalBytesOut = 50 * 1024 * 1024   // 50MB
        highUsageProfile.observationCount = 20
        highUsageProfile.averageBandwidth = 150 * 1024 * 1024 // 150MB/hour
        
        let lowUsageProfile = ProcessProfile(
            process: ProcessIdentity(type: .application, name: "Low Usage", bundleId: "com.low")
        )
        lowUsageProfile.totalBytesIn = 1 * 1024 * 1024   // 1MB
        lowUsageProfile.totalBytesOut = 512 * 1024       // 512KB
        lowUsageProfile.observationCount = 20
        lowUsageProfile.averageBandwidth = 1.5 * 1024 * 1024  // 1.5MB/hour
        
        await processRepo.profiles.append(contentsOf: [highUsageProfile, lowUsageProfile])
        
        let input = IdentifyBandwidthHogsUseCase.Input(
            thresholdMBPerHour: 10.0,
            minimumObservations: 10
        )
        
        // When
        let result = try await bandwidthUseCase.execute(input)
        
        // Then
        XCTAssertEqual(result.bandwidthHogs.count, 1)
        XCTAssertEqual(result.bandwidthHogs.first?.profile.process.identifier, "com.high")
        XCTAssertEqual(result.bandwidthHogs.first?.averageMBPerHour, 150.0)
    }
    
    // MARK: - CleanupTrafficDataUseCase Tests
    
    func test_cleanupTrafficData_removesOldData() async throws {
        // Given - old and recent observations
        let oldDate = Date().addingTimeInterval(-40 * 24 * 3600) // 40 days ago
        let recentDate = Date().addingTimeInterval(-5 * 24 * 3600) // 5 days ago
        
        var oldObservation = createObservation()
        oldObservation.timestamp = oldDate
        
        var recentObservation = createObservation()
        recentObservation.timestamp = recentDate
        
        await trafficRepo.observations.append(contentsOf: [oldObservation, recentObservation])
        
        // Old profile
        let oldProfile = ProcessProfile(
            process: ProcessIdentity(type: .application, name: "Old", bundleId: "old")
        )
        oldProfile.lastSeen = Date().addingTimeInterval(-100 * 24 * 3600)
        
        // Recent profile
        let recentProfile = ProcessProfile(
            process: ProcessIdentity(type: .application, name: "Recent", bundleId: "recent")
        )
        recentProfile.lastSeen = Date()
        
        await processRepo.profiles.append(contentsOf: [oldProfile, recentProfile])
        
        let input = CleanupTrafficDataUseCase.Input(
            retentionDays: 30,
            inactiveProfileDays: 90
        )
        
        // When
        let result = try await cleanupUseCase.execute(input)
        
        // Then
        XCTAssertEqual(result.deletedObservations, 1)
        XCTAssertEqual(result.deletedProfiles, 1)
        XCTAssertGreaterThan(result.freedSpace, 0)
        
        // Verify remaining data
        let remainingObservations = await trafficRepo.observations
        XCTAssertEqual(remainingObservations.count, 1)
        XCTAssertEqual(remainingObservations.first?.timestamp, recentDate)
        
        let remainingProfiles = await processRepo.profiles
        XCTAssertEqual(remainingProfiles.count, 1)
        XCTAssertEqual(remainingProfiles.first?.process.identifier, "recent")
    }
    
    // MARK: - Helper Methods
    
    private func createObservation(
        networkType: NetworkType = .wifi,
        bytesIn: Int64 = 1000,
        bytesOut: Int64 = 500
    ) -> TrafficObservation {
        TrafficObservation(
            process: ProcessIdentity(
                type: .application,
                name: "Test",
                bundleId: "test.app"
            ),
            bytesIn: bytesIn,
            bytesOut: bytesOut,
            packetsIn: 10,
            packetsOut: 5,
            networkType: networkType,
            isTrustedNetwork: true
        )
    }
}