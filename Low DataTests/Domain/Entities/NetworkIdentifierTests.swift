//
//  NetworkIdentifierTests.swift
//  Low DataTests
//
//  Created by Konrad Michels on 8/27/25.
//

import XCTest
@testable import Low_Data

final class NetworkIdentifierTests: XCTestCase {
    
    var mockNetwork: DetectedNetwork!
    
    override func setUp() {
        super.setUp()
        mockNetwork = DetectedNetwork()
    }
    
    override func tearDown() {
        mockNetwork = nil
        super.tearDown()
    }
    
    // MARK: - SSID Tests
    
    func test_ssidIdentifier_matchesCorrectSSID() {
        mockNetwork.ssid = "HomeWiFi"
        let identifier = NetworkIdentifier.ssid("HomeWiFi")
        
        XCTAssertTrue(identifier.matches(mockNetwork))
    }
    
    func test_ssidIdentifier_doesNotMatchDifferentSSID() {
        mockNetwork.ssid = "CoffeeShop"
        let identifier = NetworkIdentifier.ssid("HomeWiFi")
        
        XCTAssertFalse(identifier.matches(mockNetwork))
    }
    
    func test_ssidIdentifier_doesNotMatchNilSSID() {
        mockNetwork.ssid = nil
        let identifier = NetworkIdentifier.ssid("HomeWiFi")
        
        XCTAssertFalse(identifier.matches(mockNetwork))
    }
    
    // MARK: - BSSID Tests
    
    func test_bssidIdentifier_matchesCaseInsensitive() {
        mockNetwork.bssid = "AA:BB:CC:DD:EE:FF"
        let identifier = NetworkIdentifier.bssid("aa:bb:cc:dd:ee:ff")
        
        XCTAssertTrue(identifier.matches(mockNetwork))
    }
    
    // MARK: - Subnet Tests
    
    func test_subnetIdentifier_matchesIPInRange() throws {
        let cidr = try CIDR("192.168.1.0/24")
        mockNetwork.ipAddresses = [IPAddress("192.168.1.100")]
        let identifier = NetworkIdentifier.subnet(cidr)
        
        XCTAssertTrue(identifier.matches(mockNetwork))
    }
    
    func test_subnetIdentifier_doesNotMatchIPOutsideRange() throws {
        let cidr = try CIDR("192.168.1.0/24")
        mockNetwork.ipAddresses = [IPAddress("192.168.2.100")]
        let identifier = NetworkIdentifier.subnet(cidr)
        
        XCTAssertFalse(identifier.matches(mockNetwork))
    }
    
    // MARK: - Gateway Tests
    
    func test_gatewayIdentifier_matchesCorrectGateway() {
        let gateway = IPAddress("192.168.1.1")
        mockNetwork.gateway = gateway
        let identifier = NetworkIdentifier.gateway(gateway)
        
        XCTAssertTrue(identifier.matches(mockNetwork))
    }
    
    // MARK: - Interface Tests
    
    func test_interfaceIdentifier_matchesCorrectInterface() {
        mockNetwork.interfaceName = "en0"
        let identifier = NetworkIdentifier.interface("en0")
        
        XCTAssertTrue(identifier.matches(mockNetwork))
    }
    
    // MARK: - Tailscale Tests
    
    func test_tailscaleIdentifier_matchesTailscaleNetwork() {
        mockNetwork.isTailscale = true
        mockNetwork.tailscaleNetwork = "company-net"
        let identifier = NetworkIdentifier.tailscaleNetwork("company-net")
        
        XCTAssertTrue(identifier.matches(mockNetwork))
    }
    
    func test_tailscaleIdentifier_doesNotMatchNonTailscale() {
        mockNetwork.isTailscale = false
        mockNetwork.tailscaleNetwork = "company-net"
        let identifier = NetworkIdentifier.tailscaleNetwork("company-net")
        
        XCTAssertFalse(identifier.matches(mockNetwork))
    }
    
    // MARK: - Combination Tests
    
    func test_combinationIdentifier_requiresAllToMatch() {
        mockNetwork.ssid = "HomeWiFi"
        mockNetwork.gateway = IPAddress("192.168.1.1")
        
        let identifiers = [
            NetworkIdentifier.ssid("HomeWiFi"),
            NetworkIdentifier.gateway(IPAddress("192.168.1.1"))
        ]
        let combination = NetworkIdentifier.combination(identifiers)
        
        XCTAssertTrue(combination.matches(mockNetwork))
    }
    
    func test_combinationIdentifier_failsIfOneDoesNotMatch() {
        mockNetwork.ssid = "HomeWiFi"
        mockNetwork.gateway = IPAddress("192.168.1.1")
        
        let identifiers = [
            NetworkIdentifier.ssid("HomeWiFi"),
            NetworkIdentifier.gateway(IPAddress("192.168.2.1")) // Different gateway
        ]
        let combination = NetworkIdentifier.combination(identifiers)
        
        XCTAssertFalse(combination.matches(mockNetwork))
    }
    
    // MARK: - CIDR Tests
    
    func test_cidr_initializesCorrectly() throws {
        let cidr = try CIDR("192.168.1.0/24")
        
        XCTAssertEqual(cidr.network, "192.168.1.0")
        XCTAssertEqual(cidr.prefixLength, 24)
    }
    
    func test_cidr_throwsErrorForInvalidFormat() {
        XCTAssertThrows(try CIDR("192.168.1.0")) { error in
            guard case NetworkError.invalidCIDR = error else {
                XCTFail("Wrong error type")
                return
            }
        }
    }
    
    func test_cidr_contains_checksFirstOctets() throws {
        let cidr = try CIDR("10.0.0.0/8")
        
        XCTAssertTrue(cidr.contains(IPAddress("10.1.2.3")))
        XCTAssertTrue(cidr.contains(IPAddress("10.255.255.255")))
        XCTAssertFalse(cidr.contains(IPAddress("11.0.0.0")))
    }
    
    // MARK: - IPAddress Tests
    
    func test_ipAddress_detectsIPv6() {
        let ipv4 = IPAddress("192.168.1.1")
        let ipv6 = IPAddress("2001:db8::1")
        
        XCTAssertFalse(ipv4.isIPv6)
        XCTAssertTrue(ipv6.isIPv6)
    }
    
    // MARK: - DetectedNetwork Tests
    
    func test_detectedNetwork_displayName_showsSSID() {
        mockNetwork.ssid = "MyWiFi"
        XCTAssertEqual(mockNetwork.displayName, "MyWiFi")
    }
    
    func test_detectedNetwork_displayName_showsTailscale() {
        mockNetwork.isTailscale = true
        XCTAssertEqual(mockNetwork.displayName, "Tailscale Network")
    }
    
    func test_detectedNetwork_displayName_showsCellular() {
        mockNetwork.interfaceType = .cellular
        XCTAssertEqual(mockNetwork.displayName, "Cellular")
    }
    
    func test_detectedNetwork_displayName_showsEthernet() {
        mockNetwork.interfaceType = .ethernet
        XCTAssertEqual(mockNetwork.displayName, "Ethernet")
    }
    
    func test_detectedNetwork_displayName_showsUnknown() {
        XCTAssertEqual(mockNetwork.displayName, "Unknown Network")
    }
}