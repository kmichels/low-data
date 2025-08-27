//
//  ProcessIdentifierTests.swift
//  Low DataTests
//
//  Created by Konrad Michels on 8/27/25.
//

import XCTest
@testable import Low_Data

@MainActor
final class ProcessIdentifierTests: XCTestCase {
    
    var processIdentifier: ProcessIdentifier!
    var brewDetector: BrewServiceDetector!
    
    override func setUp() async throws {
        try await super.setUp()
        brewDetector = BrewServiceDetector()
        processIdentifier = ProcessIdentifier(brewDetector: brewDetector)
    }
    
    override func tearDown() async throws {
        processIdentifier = nil
        brewDetector = nil
        try await super.tearDown()
    }
    
    func test_identifyCurrentProcess() {
        // Given - current process PID
        let currentPid = ProcessInfo.processInfo.processIdentifier
        
        // When
        let identity = processIdentifier.identify(pid: currentPid)
        
        // Then
        XCTAssertNotEqual(identity.type, .unknown)
        XCTAssertNotNil(identity.name)
        XCTAssertFalse(identity.name.isEmpty)
    }
    
    func test_identifySystemProcess() {
        // Given - launchd PID (always 1)
        let launchdPid: pid_t = 1
        
        // When
        let identity = processIdentifier.identify(pid: launchdPid)
        
        // Then
        XCTAssertEqual(identity.type, .system)
        XCTAssertTrue(identity.name.lowercased().contains("launchd") || identity.name == "kernel_task")
    }
    
    func test_cacheHit() {
        // Given
        let pid = ProcessInfo.processInfo.processIdentifier
        
        // When - identify same PID twice
        let identity1 = processIdentifier.identify(pid: pid)
        let identity2 = processIdentifier.identify(pid: pid)
        
        // Then - should return same cached result
        XCTAssertEqual(identity1.name, identity2.name)
        XCTAssertEqual(identity1.type, identity2.type)
        XCTAssertEqual(identity1.bundleId, identity2.bundleId)
    }
    
    func test_clearCache() {
        // Given
        let pid = ProcessInfo.processInfo.processIdentifier
        _ = processIdentifier.identify(pid: pid)
        
        // When
        processIdentifier.clearCache()
        
        // Then - cache should be cleared (we can't directly test this, but no crash is good)
        let identity = processIdentifier.identify(pid: pid)
        XCTAssertNotNil(identity)
    }
    
    func test_identifyInvalidPID() {
        // Given - invalid PID
        let invalidPid: pid_t = 99999
        
        // When
        let identity = processIdentifier.identify(pid: invalidPid)
        
        // Then
        XCTAssertEqual(identity.type, .unknown)
        XCTAssertTrue(identity.name.contains("99999") || identity.name.contains("Unknown"))
    }
}

// MARK: - BrewServiceDetectorTests

@MainActor
final class BrewServiceDetectorTests: XCTestCase {
    
    var detector: BrewServiceDetector!
    
    override func setUp() async throws {
        try await super.setUp()
        detector = BrewServiceDetector()
    }
    
    override func tearDown() async throws {
        detector = nil
        try await super.tearDown()
    }
    
    func test_isBrewService_withNonBrewPath() {
        // Given
        let paths = [
            "/System/Library/CoreServices/Finder.app",
            "/Applications/Safari.app",
            "/usr/bin/ls"
        ]
        
        // When/Then
        for path in paths {
            XCTAssertFalse(detector.isBrewService(path: path))
        }
    }
    
    func test_isBrewService_withBrewPath() {
        // Given
        let paths = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/mysql",
            "/opt/homebrew/Cellar/postgresql/14.0/bin/postgres"
        ]
        
        // When/Then
        for path in paths {
            XCTAssertTrue(detector.isBrewService(path: path))
        }
    }
    
    func test_extractServiceName() {
        // Given
        let testCases: [(path: String, expected: String?)] = [
            ("/opt/homebrew/bin/postgresql@14", "Postgresql"),
            ("/usr/local/bin/mysql", "Mysql"),
            ("/opt/homebrew/Cellar/redis/6.2.5/bin/redis-server", "Redis Server"),
            ("", nil)
        ]
        
        // When/Then
        for testCase in testCases {
            let result = detector.extractServiceName(from: testCase.path)
            if let expected = testCase.expected {
                XCTAssertEqual(result, expected)
            } else {
                XCTAssertNil(result)
            }
        }
    }
    
    func test_isBandwidthIntensive() {
        // Given
        let intensiveServices = ["docker", "elasticsearch", "mongodb", "nginx"]
        let normalServices = ["git", "vim", "bash"]
        
        // When/Then
        for service in intensiveServices {
            XCTAssertTrue(detector.isBandwidthIntensive(service))
        }
        
        for service in normalServices {
            XCTAssertFalse(detector.isBandwidthIntensive(service))
        }
    }
}

// MARK: - ProcessGrouperTests

@MainActor
final class ProcessGrouperTests: XCTestCase {
    
    var grouper: ProcessGrouper!
    
    override func setUp() async throws {
        try await super.setUp()
        grouper = ProcessGrouper()
    }
    
    override func tearDown() async throws {
        grouper = nil
        try await super.tearDown()
    }
    
    func test_findParent_forChromeHelper() {
        // Given
        let helper = ProcessIdentity(
            type: .helper,
            name: "Google Chrome Helper",
            bundleId: "com.google.Chrome.helper"
        )
        
        // When
        let parent = grouper.findParent(for: helper)
        
        // Then
        XCTAssertNotNil(parent)
        XCTAssertEqual(parent?.bundleId, "com.google.Chrome")
    }
    
    func test_findParent_forDropboxHelper() {
        // Given
        let helper = ProcessIdentity(
            type: .helper,
            name: "Dropbox Helper",
            bundleId: "com.dropbox.DropboxHelper"
        )
        
        // When
        let parent = grouper.findParent(for: helper)
        
        // Then
        XCTAssertNotNil(parent)
        XCTAssertEqual(parent?.bundleId, "com.dropbox.Dropbox")
    }
    
    func test_isHelper() {
        // Given
        let helpers = [
            ProcessIdentity(type: .helper, name: "Safari Web Content"),
            ProcessIdentity(type: .helper, name: "Code Helper (GPU)"),
            ProcessIdentity(type: .helper, name: "Slack Helper (Renderer)")
        ]
        
        let nonHelpers = [
            ProcessIdentity(type: .application, name: "Safari"),
            ProcessIdentity(type: .daemon, name: "launchd"),
            ProcessIdentity(type: .system, name: "kernel_task")
        ]
        
        // When/Then
        for helper in helpers {
            XCTAssertTrue(grouper.isHelper(helper))
        }
        
        for nonHelper in nonHelpers {
            XCTAssertFalse(grouper.isHelper(nonHelper))
        }
    }
    
    func test_groupProcesses() {
        // Given
        let processes = [
            ProcessIdentity(type: .application, name: "Google Chrome", bundleId: "com.google.Chrome"),
            ProcessIdentity(type: .helper, name: "Google Chrome Helper", bundleId: "com.google.Chrome.helper"),
            ProcessIdentity(type: .helper, name: "Chrome Helper (GPU)", bundleId: "com.google.Chrome.helper.GPU"),
            ProcessIdentity(type: .application, name: "Safari", bundleId: "com.apple.Safari"),
            ProcessIdentity(type: .daemon, name: "mysqld")
        ]
        
        // When
        let groups = grouper.groupProcesses(processes)
        
        // Then
        XCTAssertGreaterThan(groups.count, 0)
        
        // Find Chrome group
        if let chromeGroup = groups.first(where: { $0.parent.bundleId == "com.google.Chrome" }) {
            XCTAssertEqual(chromeGroup.helpers.count, 2)
        } else {
            XCTFail("Chrome group not found")
        }
        
        // Safari should be its own group
        XCTAssertNotNil(groups.first(where: { $0.parent.bundleId == "com.apple.Safari" }))
    }
}