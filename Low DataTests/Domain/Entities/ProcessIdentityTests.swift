//
//  ProcessIdentityTests.swift
//  Low DataTests
//
//  Created by Konrad Michels on 8/27/25.
//

import XCTest
@testable import Low_Data

final class ProcessIdentityTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func test_processIdentity_initializesCorrectly() {
        let process = ProcessIdentity(
            type: .application,
            name: "Safari",
            bundleId: "com.apple.Safari",
            path: "/Applications/Safari.app",
            pid: 1234
        )
        
        XCTAssertEqual(process.type, .application)
        XCTAssertEqual(process.name, "Safari")
        XCTAssertEqual(process.bundleId, "com.apple.Safari")
        XCTAssertEqual(process.path, "/Applications/Safari.app")
        XCTAssertEqual(process.pid, 1234)
    }
    
    // MARK: - Identifier Tests
    
    func test_identifier_forApplication_usesBundleId() {
        let process = ProcessIdentity(
            type: .application,
            name: "TestApp",
            bundleId: "com.example.testapp"
        )
        
        XCTAssertEqual(process.identifier, "com.example.testapp")
    }
    
    func test_identifier_forApplication_fallsBackToName() {
        let process = ProcessIdentity(
            type: .application,
            name: "TestApp",
            bundleId: nil
        )
        
        XCTAssertEqual(process.identifier, "TestApp")
    }
    
    func test_identifier_forBrewService_usesPath() {
        let process = ProcessIdentity(
            type: .brewService,
            name: "postgresql",
            path: "/opt/homebrew/bin/postgresql"
        )
        
        XCTAssertEqual(process.identifier, "/opt/homebrew/bin/postgresql")
    }
    
    func test_identifier_forBrewService_fallsBackToName() {
        let process = ProcessIdentity(
            type: .brewService,
            name: "postgresql"
        )
        
        XCTAssertEqual(process.identifier, "postgresql")
    }
    
    func test_identifier_forUnknown_includesPrefix() {
        let process = ProcessIdentity(
            type: .unknown,
            name: "mystery-process"
        )
        
        XCTAssertEqual(process.identifier, "unknown.mystery-process")
    }
    
    // MARK: - Display Name Tests
    
    func test_displayName_forApplication() {
        let process = ProcessIdentity(type: .application, name: "Safari")
        XCTAssertEqual(process.displayName, "Safari")
    }
    
    func test_displayName_forBrewService() {
        let process = ProcessIdentity(type: .brewService, name: "postgresql")
        XCTAssertEqual(process.displayName, "postgresql (Homebrew)")
    }
    
    func test_displayName_forSystem() {
        let process = ProcessIdentity(type: .system, name: "kernel_task")
        XCTAssertEqual(process.displayName, "kernel_task (System)")
    }
    
    func test_displayName_forDaemon() {
        let process = ProcessIdentity(type: .daemon, name: "cloudd")
        XCTAssertEqual(process.displayName, "cloudd (Daemon)")
    }
    
    func test_displayName_forUnknown() {
        let process = ProcessIdentity(type: .unknown, name: "mystery")
        XCTAssertEqual(process.displayName, "mystery (Unknown)")
    }
    
    // MARK: - Bandwidth Detection Tests
    
    func test_isLikelyBandwidthIntensive_detectsKnownHeavyApps() {
        let heavyApps = [
            "Dropbox",
            "Google Drive",
            "OneDrive",
            "Photos",
            "Spotify",
            "Slack",
            "Docker"
        ]
        
        for appName in heavyApps {
            let process = ProcessIdentity(type: .application, name: appName)
            XCTAssertTrue(process.isLikelyBandwidthIntensive, "\(appName) should be bandwidth intensive")
        }
    }
    
    func test_isLikelyBandwidthIntensive_returnsFalseForUnknownApps() {
        let process = ProcessIdentity(type: .application, name: "TextEdit")
        XCTAssertFalse(process.isLikelyBandwidthIntensive)
    }
    
    // MARK: - ProcessType Tests
    
    func test_processType_defaultActions() {
        XCTAssertEqual(ProcessType.application.defaultAction, .askUser)
        XCTAssertEqual(ProcessType.brewService.defaultAction, .block)
        XCTAssertEqual(ProcessType.system.defaultAction, .allow)
        XCTAssertEqual(ProcessType.daemon.defaultAction, .askUser)
        XCTAssertEqual(ProcessType.unknown.defaultAction, .block)
    }
    
    // MARK: - ProcessProfile Tests
    
    func test_processProfile_initializesCorrectly() {
        let process = ProcessIdentity(type: .application, name: "TestApp")
        let profile = ProcessProfile(process: process)
        
        XCTAssertEqual(profile.process, process)
        XCTAssertEqual(profile.observationCount, 0)
        XCTAssertEqual(profile.averageBandwidth, 0)
        XCTAssertEqual(profile.peakBandwidth, 0)
        XCTAssertEqual(profile.totalBytesIn, 0)
        XCTAssertEqual(profile.totalBytesOut, 0)
        XCTAssertFalse(profile.isBursty)
        XCTAssertTrue(profile.commonPorts.isEmpty)
    }
    
    func test_processProfile_addObservation_updatesStatistics() {
        let process = ProcessIdentity(type: .application, name: "TestApp")
        var profile = ProcessProfile(process: process)
        
        let observation = TrafficObservation(
            process: process,
            bytesIn: 1000,
            bytesOut: 500,
            isTrustedNetwork: false
        )
        
        profile.addObservation(observation)
        
        XCTAssertEqual(profile.observationCount, 1)
        XCTAssertEqual(profile.averageBandwidth, 1500)
        XCTAssertEqual(profile.peakBandwidth, 1500)
        XCTAssertEqual(profile.totalBytesIn, 1000)
        XCTAssertEqual(profile.totalBytesOut, 500)
    }
    
    func test_processProfile_detectsBurstiness() {
        let process = ProcessIdentity(type: .application, name: "TestApp")
        var profile = ProcessProfile(process: process)
        
        // Add 11 low bandwidth observations
        for _ in 0..<11 {
            let observation = TrafficObservation(
                process: process,
                bytesIn: 100,
                bytesOut: 100,
                isTrustedNetwork: false
            )
            profile.addObservation(observation)
        }
        
        XCTAssertFalse(profile.isBursty)
        
        // Add a spike observation (>5x average)
        let spikeObservation = TrafficObservation(
            process: process,
            bytesIn: 5000,
            bytesOut: 5000,
            isTrustedNetwork: false
        )
        profile.addObservation(spikeObservation)
        
        XCTAssertTrue(profile.isBursty)
    }
    
    // MARK: - Equatable Tests
    
    func test_processIdentity_equatable() {
        let process1 = ProcessIdentity(
            type: .application,
            name: "TestApp",
            bundleId: "com.test.app",
            path: "/path/to/app",
            pid: 1234
        )
        
        let process2 = ProcessIdentity(
            type: .application,
            name: "TestApp",
            bundleId: "com.test.app",
            path: "/path/to/app",
            pid: 1234
        )
        
        XCTAssertEqual(process1, process2)
    }
    
    func test_processIdentity_notEqualWithDifferentValues() {
        let process1 = ProcessIdentity(type: .application, name: "App1")
        let process2 = ProcessIdentity(type: .application, name: "App2")
        
        XCTAssertNotEqual(process1, process2)
    }
    
    // MARK: - Hashable Tests
    
    func test_processIdentity_hashable() {
        let process1 = ProcessIdentity(type: .application, name: "TestApp", bundleId: "com.test")
        let process2 = ProcessIdentity(type: .application, name: "TestApp", bundleId: "com.test")
        
        var set = Set<ProcessIdentity>()
        set.insert(process1)
        set.insert(process2)
        
        XCTAssertEqual(set.count, 1)
    }
    
    // MARK: - Codable Tests
    
    func test_processIdentity_codable() throws {
        let process = ProcessIdentity(
            type: .brewService,
            name: "postgresql",
            path: "/opt/homebrew/bin/postgresql"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(process)
        
        let decoder = JSONDecoder()
        let decodedProcess = try decoder.decode(ProcessIdentity.self, from: data)
        
        XCTAssertEqual(process, decodedProcess)
    }
}