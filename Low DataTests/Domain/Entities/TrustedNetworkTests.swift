//
//  TrustedNetworkTests.swift
//  Low DataTests
//
//  Created by Konrad Michels on 8/27/25.
//

import XCTest
@testable import Low_Data

final class TrustedNetworkTests: XCTestCase {
    
    var mockNetwork: DetectedNetwork!
    
    override func setUp() {
        super.setUp()
        mockNetwork = DetectedNetwork()
        mockNetwork.ssid = "TestNetwork"
        mockNetwork.gateway = IPAddress("192.168.1.1")
    }
    
    override func tearDown() {
        mockNetwork = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func test_trustedNetwork_initializesWithDefaults() {
        let network = TrustedNetwork(
            name: "Home",
            identifiers: [.ssid("HomeWiFi")]
        )
        
        XCTAssertNotNil(network.id)
        XCTAssertEqual(network.name, "Home")
        XCTAssertTrue(network.isEnabled)
        XCTAssertNil(network.customRules)
        XCTAssertNotNil(network.dateAdded)
    }
    
    func test_trustedNetwork_initializesWithCustomValues() {
        let rules = [ProcessRule(processIdentifier: "com.dropbox", action: .block)]
        let id = UUID()
        let date = Date()
        
        let network = TrustedNetwork(
            id: id,
            name: "Office",
            identifiers: [.ssid("OfficeWiFi")],
            dateAdded: date,
            isEnabled: false,
            customRules: rules
        )
        
        XCTAssertEqual(network.id, id)
        XCTAssertEqual(network.name, "Office")
        XCTAssertFalse(network.isEnabled)
        XCTAssertEqual(network.customRules, rules)
        XCTAssertEqual(network.dateAdded, date)
    }
    
    // MARK: - Matching Tests
    
    func test_matches_returnsTrueWhenAnyIdentifierMatches() {
        let trustedNetwork = TrustedNetwork(
            name: "MultiIdentifier",
            identifiers: [
                .ssid("TestNetwork"),
                .gateway(IPAddress("10.0.0.1"))
            ]
        )
        
        XCTAssertTrue(trustedNetwork.matches(mockNetwork))
    }
    
    func test_matches_returnsFalseWhenNoIdentifierMatches() {
        let trustedNetwork = TrustedNetwork(
            name: "NoMatch",
            identifiers: [
                .ssid("DifferentNetwork"),
                .gateway(IPAddress("10.0.0.1"))
            ]
        )
        
        XCTAssertFalse(trustedNetwork.matches(mockNetwork))
    }
    
    func test_matches_returnsFalseWhenDisabled() {
        let trustedNetwork = TrustedNetwork(
            name: "Disabled",
            identifiers: [.ssid("TestNetwork")],
            isEnabled: false
        )
        
        XCTAssertFalse(trustedNetwork.matches(mockNetwork))
    }
    
    func test_matches_worksWithCombinationIdentifier() throws {
        mockNetwork.ipAddresses = [IPAddress("192.168.1.100")]
        
        let trustedNetwork = TrustedNetwork(
            name: "CombinedMatch",
            identifiers: [
                .combination([
                    .ssid("TestNetwork"),
                    .gateway(IPAddress("192.168.1.1")),
                    .subnet(try CIDR("192.168.1.0/24"))
                ])
            ]
        )
        
        XCTAssertTrue(trustedNetwork.matches(mockNetwork))
    }
    
    // MARK: - ProcessRule Tests
    
    func test_processRule_initializesCorrectly() {
        let rule = ProcessRule(
            processIdentifier: "com.example.app",
            action: .block,
            reason: "High bandwidth usage"
        )
        
        XCTAssertEqual(rule.processIdentifier, "com.example.app")
        XCTAssertEqual(rule.action, .block)
        XCTAssertEqual(rule.reason, "High bandwidth usage")
    }
    
    // MARK: - NetworkTrustLevel Tests
    
    func test_networkTrustLevel_shouldRestrictTraffic() {
        XCTAssertFalse(NetworkTrustLevel.trusted.shouldRestrictTraffic)
        XCTAssertTrue(NetworkTrustLevel.untrusted.shouldRestrictTraffic)
        XCTAssertTrue(NetworkTrustLevel.unknown.shouldRestrictTraffic)
    }
    
    // MARK: - Equatable Tests
    
    func test_trustedNetwork_equatable() {
        let id = UUID()
        let date = Date()
        
        let network1 = TrustedNetwork(
            id: id,
            name: "Test",
            identifiers: [.ssid("TestWiFi")],
            dateAdded: date,
            isEnabled: true,
            customRules: nil
        )
        
        let network2 = TrustedNetwork(
            id: id,
            name: "Test",
            identifiers: [.ssid("TestWiFi")],
            dateAdded: date,
            isEnabled: true,
            customRules: nil
        )
        
        XCTAssertEqual(network1, network2)
    }
    
    func test_trustedNetwork_notEqualWithDifferentId() {
        let network1 = TrustedNetwork(
            name: "Test",
            identifiers: [.ssid("TestWiFi")]
        )
        
        let network2 = TrustedNetwork(
            name: "Test",
            identifiers: [.ssid("TestWiFi")]
        )
        
        XCTAssertNotEqual(network1, network2)
    }
    
    // MARK: - Codable Tests
    
    func test_trustedNetwork_codable() throws {
        let network = TrustedNetwork(
            name: "Test",
            identifiers: [
                .ssid("TestWiFi"),
                .gateway(IPAddress("192.168.1.1"))
            ],
            customRules: [
                ProcessRule(processIdentifier: "com.test", action: .block)
            ]
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(network)
        
        let decoder = JSONDecoder()
        let decodedNetwork = try decoder.decode(TrustedNetwork.self, from: data)
        
        XCTAssertEqual(network.id, decodedNetwork.id)
        XCTAssertEqual(network.name, decodedNetwork.name)
        XCTAssertEqual(network.identifiers, decodedNetwork.identifiers)
        XCTAssertEqual(network.customRules, decodedNetwork.customRules)
    }
}