//
//  FilterRuleEngineTests.swift
//  Low DataTests
//
//  Created by Konrad Michels on 8/27/25.
//

import XCTest
@testable import Low_Data

@MainActor
final class FilterRuleEngineTests: XCTestCase {
    
    var ruleEngine: FilterRuleEngine!
    
    override func setUp() async throws {
        try await super.setUp()
        ruleEngine = FilterRuleEngine()
    }
    
    override func tearDown() async throws {
        ruleEngine = nil
        try await super.tearDown()
    }
    
    // MARK: - Evaluation Tests
    
    func test_evaluate_allowsOnTrustedNetwork() async {
        // Given
        let process = ProcessIdentity(type: .application, name: "Safari")
        let flow = createFlowInfo(host: "example.com")
        
        // Simulate trusted network
        var network = DetectedNetwork()
        network.ssid = "Home WiFi"
        network.interfaceType = .wifi
        await ruleEngine.updateCurrentNetwork(network)
        
        let trustedNetwork = TrustedNetwork(
            name: "Home",
            identifiers: [.ssid("Home WiFi")]
        )
        ruleEngine.updateTrustedNetworks([trustedNetwork])
        
        // When
        let decision = ruleEngine.evaluate(
            process: process,
            flow: flow,
            isCurrentNetworkTrusted: true
        )
        
        // Then
        XCTAssertEqual(decision.action, .allow)
        XCTAssertTrue(decision.reason.contains("Trusted"))
    }
    
    func test_evaluate_blocksDropboxOnUntrustedNetwork() async {
        // Given
        let process = ProcessIdentity(
            type: .application,
            name: "Dropbox",
            bundleId: "com.dropbox.Dropbox"
        )
        let flow = createFlowInfo(host: "dropbox.com")
        
        // Load default rules
        await ruleEngine.loadDefaultRules()
        
        // When
        let decision = ruleEngine.evaluate(
            process: process,
            flow: flow,
            isCurrentNetworkTrusted: false
        )
        
        // Then
        XCTAssertEqual(decision.action, .block)
        XCTAssertTrue(decision.shouldRecord)
    }
    
    func test_evaluate_respectsPriority() {
        // Given
        let process = ProcessIdentity(
            type: .application,
            name: "TestApp",
            bundleId: "com.test.app"
        )
        let flow = createFlowInfo(host: "test.com")
        
        // Create conflicting rules with different priorities
        let highPriorityRule = ProcessRule(
            processIdentifier: "com.test.app",
            action: .block,
            priority: 100
        )
        
        let lowPriorityRule = ProcessRule(
            processIdentifier: "com.test.app",
            action: .allow,
            priority: 10
        )
        
        ruleEngine.updateProcessRules([lowPriorityRule, highPriorityRule])
        
        // When
        let decision = ruleEngine.evaluate(
            process: process,
            flow: flow,
            isCurrentNetworkTrusted: false
        )
        
        // Then - High priority rule should win
        XCTAssertEqual(decision.action, .block)
    }
    
    func test_evaluate_detectsBandwidthHeavyProcess() {
        // Given
        let process = ProcessIdentity(
            type: .application,
            name: "Steam"
        )
        let flow = createFlowInfo(host: "steampowered.com")
        
        // When - on untrusted network
        let decision = ruleEngine.evaluate(
            process: process,
            flow: flow,
            isCurrentNetworkTrusted: false
        )
        
        // Then
        XCTAssertEqual(decision.action, .block)
        XCTAssertTrue(decision.reason.contains("Bandwidth-heavy"))
    }
    
    func test_evaluate_blocksBackgroundProcessOnUntrusted() {
        // Given
        let process = ProcessIdentity(
            type: .daemon,
            name: "com.example.updater"
        )
        let flow = createFlowInfo(host: "example.com")
        
        // When
        let decision = ruleEngine.evaluate(
            process: process,
            flow: flow,
            isCurrentNetworkTrusted: false
        )
        
        // Then
        XCTAssertEqual(decision.action, .block)
        XCTAssertTrue(decision.reason.contains("Background"))
    }
    
    // MARK: - Network Trust Tests
    
    func test_evaluateNetworkTrust_matchesSSID() async {
        // Given
        var network = DetectedNetwork()
        network.ssid = "Office Network"
        network.interfaceType = .wifi
        
        let trustedNetwork = TrustedNetwork(
            name: "Office",
            identifiers: [.ssid("Office Network")]
        )
        
        ruleEngine.updateTrustedNetworks([trustedNetwork])
        
        // When
        let isTrusted = ruleEngine.evaluateNetworkTrust(network)
        
        // Then
        XCTAssertTrue(isTrusted)
    }
    
    func test_evaluateNetworkTrust_detectsPublicWiFi() {
        // Given
        var network = DetectedNetwork()
        network.ssid = "Starbucks WiFi"
        network.interfaceType = .wifi
        
        // When
        let isTrusted = ruleEngine.evaluateNetworkTrust(network)
        
        // Then
        XCTAssertFalse(isTrusted)
    }
    
    func test_evaluateNetworkTrust_rejectsCellular() {
        // Given
        var network = DetectedNetwork()
        network.interfaceType = .cellular
        
        // When
        let isTrusted = ruleEngine.evaluateNetworkTrust(network)
        
        // Then
        XCTAssertFalse(isTrusted)
    }
    
    func test_evaluateNetworkTrust_respectsDisabledNetwork() {
        // Given
        var network = DetectedNetwork()
        network.ssid = "Test Network"
        network.interfaceType = .wifi
        
        var trustedNetwork = TrustedNetwork(
            name: "Test",
            identifiers: [.ssid("Test Network")]
        )
        trustedNetwork.isEnabled = false // Disabled
        
        ruleEngine.updateTrustedNetworks([trustedNetwork])
        
        // When
        let isTrusted = ruleEngine.evaluateNetworkTrust(network)
        
        // Then
        XCTAssertFalse(isTrusted) // Should not trust disabled network
    }
    
    // MARK: - Rule Matching Tests
    
    func test_matchesRule_byBundleId() async {
        // Given
        let process = ProcessIdentity(
            type: .application,
            name: "Dropbox",
            bundleId: "com.dropbox.Dropbox"
        )
        
        await ruleEngine.loadDefaultRules()
        
        // When
        let flow = createFlowInfo(host: "dropbox.com")
        let decision = ruleEngine.evaluate(
            process: process,
            flow: flow,
            isCurrentNetworkTrusted: false
        )
        
        // Then
        XCTAssertEqual(decision.action, .block)
    }
    
    func test_matchesRule_byProcessName() async {
        // Given
        let process = ProcessIdentity(
            type: .brewService,
            name: "docker"
        )
        
        await ruleEngine.loadDefaultRules()
        
        // When
        let flow = createFlowInfo(host: "docker.io")
        let decision = ruleEngine.evaluate(
            process: process,
            flow: flow,
            isCurrentNetworkTrusted: false
        )
        
        // Then
        XCTAssertEqual(decision.action, .block)
    }
    
    // MARK: - State Management Tests
    
    func test_setEnabled() {
        // Given
        XCTAssertTrue(ruleEngine.isEnabled) // Default
        
        // When
        ruleEngine.setEnabled(false)
        
        // Then
        XCTAssertFalse(ruleEngine.isEnabled)
        
        // When
        ruleEngine.setEnabled(true)
        
        // Then
        XCTAssertTrue(ruleEngine.isEnabled)
    }
    
    func test_updateCurrentNetwork() async {
        // Given
        var network = DetectedNetwork()
        network.ssid = "Test Network"
        
        // When
        await ruleEngine.updateCurrentNetwork(network)
        
        // Then
        XCTAssertFalse(ruleEngine.currentNetworkTrusted) // Not in trusted list
    }
    
    // MARK: - Statistics Tests
    
    func test_getStatistics() {
        // Given - Make some decisions
        let process = ProcessIdentity(type: .application, name: "Test")
        let flow = createFlowInfo(host: "test.com")
        
        _ = ruleEngine.evaluate(process: process, flow: flow, isCurrentNetworkTrusted: true)
        _ = ruleEngine.evaluate(process: process, flow: flow, isCurrentNetworkTrusted: true)
        
        // When
        let stats = ruleEngine.getStatistics()
        
        // Then
        XCTAssertEqual(stats.totalDecisions, 2)
        XCTAssertEqual(stats.allowedCount, 2)
        XCTAssertEqual(stats.blockedCount, 0)
    }
    
    // MARK: - Helper Methods
    
    private func createFlowInfo(host: String, port: Int = 443) -> FlowInfo {
        return FlowInfo(
            key: FlowKey(
                remoteHost: host,
                remotePort: String(port),
                localPort: "12345",
                direction: .outbound
            ),
            url: URL(string: "https://\(host)"),
            hostname: host,
            port: port
        )
    }
}