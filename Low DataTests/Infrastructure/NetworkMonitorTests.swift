//
//  NetworkMonitorTests.swift
//  Low DataTests
//
//  Created by Konrad Michels on 8/27/25.
//

import XCTest
import Network
import Combine
@testable import Low_Data

@MainActor
final class NetworkMonitorTests: XCTestCase {
    
    var monitor: NetworkMonitor!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        monitor = NetworkMonitor()
        cancellables = []
    }
    
    override func tearDown() async throws {
        monitor = nil
        cancellables = nil
        try await super.tearDown()
    }
    
    // MARK: - Connection Status Tests
    
    func test_networkMonitor_initializesCorrectly() {
        XCTAssertNotNil(monitor)
        XCTAssertFalse(monitor.isExpensive)
        XCTAssertFalse(monitor.isConstrained)
    }
    
    func test_networkMonitor_publishes_connectionChanges() async {
        let expectation = expectation(description: "Connection status published")
        expectation.expectedFulfillmentCount = 1
        
        monitor.$isConnected
            .dropFirst() // Skip initial value
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Trigger a refresh
        await monitor.refresh()
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    
    func test_networkMonitor_detectsCurrentNetwork() async {
        // Give the monitor time to detect network
        await monitor.refresh()
        
        // In a real device/simulator, should detect some network
        // This test will pass/fail based on actual network availability
        if monitor.isConnected {
            XCTAssertNotNil(monitor.currentNetwork)
            XCTAssertNotNil(monitor.connectionType)
        } else {
            XCTAssertNil(monitor.currentNetwork)
        }
    }
    
    // MARK: - Network Details Tests
    
    func test_detectedNetwork_hasDisplayName() async {
        await monitor.refresh()
        
        if let network = monitor.currentNetwork {
            XCTAssertFalse(network.displayName.isEmpty)
            XCTAssertNotEqual(network.displayName, "Unknown Network")
        }
    }
    
    func test_networkQuality_estimation() async {
        await monitor.refresh()
        
        if let network = monitor.currentNetwork {
            // Quality should be set to something
            XCTAssertNotEqual(network.quality, .unknown)
            
            // Ethernet should be excellent
            if network.interfaceType == .ethernet {
                XCTAssertEqual(network.quality, .excellent)
            }
        }
    }
    
    // MARK: - Interface Detection Tests
    
    func test_tailscale_detection() async {
        await monitor.refresh()
        
        if let network = monitor.currentNetwork {
            // Check if Tailscale detection works for utun interfaces
            if let interfaceName = network.interfaceName,
               interfaceName.hasPrefix("utun") {
                XCTAssertTrue(network.isTailscale)
                XCTAssertNotNil(network.tailscaleNetwork)
            }
        }
    }
    
    func test_wifi_detection() async {
        await monitor.refresh()
        
        if monitor.connectionType == .wifi {
            XCTAssertNotNil(monitor.currentNetwork)
            XCTAssertEqual(monitor.currentNetwork?.interfaceType, .wifi)
            // SSID might be nil in simulator
        }
    }
    
    // MARK: - IP Address Tests
    
    func test_ipAddress_detection() async {
        await monitor.refresh()
        
        if let network = monitor.currentNetwork,
           monitor.isConnected {
            // Should have at least one IP address when connected
            if let addresses = network.ipAddresses {
                XCTAssertFalse(addresses.isEmpty)
                
                // Should have at least one IPv4 address
                let hasIPv4 = addresses.contains { !$0.isIPv6 }
                XCTAssertTrue(hasIPv4)
            }
        }
    }
    
    // MARK: - Publishing Tests
    
    func test_published_properties_update() async {
        let networkExpectation = expectation(description: "Network updated")
        let typeExpectation = expectation(description: "Connection type updated")
        
        monitor.$currentNetwork
            .dropFirst()
            .compactMap { $0 }
            .sink { _ in
                networkExpectation.fulfill()
            }
            .store(in: &cancellables)
        
        monitor.$connectionType
            .dropFirst()
            .compactMap { $0 }
            .sink { _ in
                typeExpectation.fulfill()
            }
            .store(in: &cancellables)
        
        await monitor.refresh()
        
        // Only check if we're connected
        if monitor.isConnected {
            await fulfillment(of: [networkExpectation, typeExpectation], timeout: 2.0)
        }
    }
    
    // MARK: - Performance Tests
    
    func test_performance_networkRefresh() throws {
        measure {
            let expectation = expectation(description: "Refresh completed")
            
            Task {
                await monitor.refresh()
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 1.0)
        }
    }
}