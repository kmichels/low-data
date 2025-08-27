//
//  CoreDataTrustedNetworkRepositoryTests.swift
//  Low DataTests
//
//  Created by Konrad Michels on 8/27/25.
//

import XCTest
import CoreData
@testable import Low_Data

final class CoreDataTrustedNetworkRepositoryTests: XCTestCase {
    
    var repository: CoreDataTrustedNetworkRepository!
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
        
        repository = CoreDataTrustedNetworkRepository(container: testContainer)
    }
    
    override func tearDown() async throws {
        repository = nil
        testContainer = nil
        try await super.tearDown()
    }
    
    // MARK: - Save Tests
    
    func test_save_createsNewNetwork() async throws {
        let network = TrustedNetwork(
            name: "Test Network",
            identifiers: [.ssid("TestSSID")]
        )
        
        try await repository.save(network)
        
        let fetched = try await repository.fetch(by: network.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "Test Network")
        XCTAssertEqual(fetched?.identifiers.count, 1)
    }
    
    func test_save_updatesExistingNetwork() async throws {
        let network = TrustedNetwork(
            name: "Original",
            identifiers: [.ssid("TestSSID")]
        )
        
        try await repository.save(network)
        
        // Update the network
        let updated = TrustedNetwork(
            id: network.id,
            name: "Updated",
            identifiers: [.ssid("TestSSID"), .gateway(IPAddress("192.168.1.1"))],
            dateAdded: network.dateAdded,
            isEnabled: false
        )
        
        try await repository.save(updated)
        
        let fetched = try await repository.fetch(by: network.id)
        XCTAssertEqual(fetched?.name, "Updated")
        XCTAssertEqual(fetched?.identifiers.count, 2)
        XCTAssertEqual(fetched?.isEnabled, false)
    }
    
    // MARK: - Fetch Tests
    
    func test_fetchAll_returnsAllNetworks() async throws {
        let network1 = TrustedNetwork(name: "Network 1", identifiers: [.ssid("SSID1")])
        let network2 = TrustedNetwork(name: "Network 2", identifiers: [.ssid("SSID2")])
        let network3 = TrustedNetwork(name: "Network 3", identifiers: [.ssid("SSID3")])
        
        try await repository.save(network1)
        try await repository.save(network2)
        try await repository.save(network3)
        
        let all = try await repository.fetchAll()
        XCTAssertEqual(all.count, 3)
        XCTAssertTrue(all.contains { $0.name == "Network 1" })
        XCTAssertTrue(all.contains { $0.name == "Network 2" })
        XCTAssertTrue(all.contains { $0.name == "Network 3" })
    }
    
    func test_fetch_returnsNilForNonexistentId() async throws {
        let fetched = try await repository.fetch(by: UUID())
        XCTAssertNil(fetched)
    }
    
    // MARK: - Delete Tests
    
    func test_delete_removesNetwork() async throws {
        let network = TrustedNetwork(
            name: "To Delete",
            identifiers: [.ssid("TestSSID")]
        )
        
        try await repository.save(network)
        
        // Verify it exists
        var fetched = try await repository.fetch(by: network.id)
        XCTAssertNotNil(fetched)
        
        // Delete it
        try await repository.delete(network)
        
        // Verify it's gone
        fetched = try await repository.fetch(by: network.id)
        XCTAssertNil(fetched)
    }
    
    // MARK: - Trust Evaluation Tests
    
    func test_isTrusted_returnsTrueForMatchingNetwork() async throws {
        let trustedNetwork = TrustedNetwork(
            name: "Home",
            identifiers: [.ssid("HomeWiFi")]
        )
        try await repository.save(trustedNetwork)
        
        var detectedNetwork = DetectedNetwork()
        detectedNetwork.ssid = "HomeWiFi"
        
        let isTrusted = try await repository.isTrusted(detectedNetwork)
        XCTAssertTrue(isTrusted)
    }
    
    func test_isTrusted_returnsFalseForNonMatchingNetwork() async throws {
        let trustedNetwork = TrustedNetwork(
            name: "Home",
            identifiers: [.ssid("HomeWiFi")]
        )
        try await repository.save(trustedNetwork)
        
        var detectedNetwork = DetectedNetwork()
        detectedNetwork.ssid = "CoffeeShop"
        
        let isTrusted = try await repository.isTrusted(detectedNetwork)
        XCTAssertFalse(isTrusted)
    }
    
    func test_findMatch_returnsMatchingNetwork() async throws {
        let network1 = TrustedNetwork(name: "Home", identifiers: [.ssid("HomeWiFi")])
        let network2 = TrustedNetwork(name: "Office", identifiers: [.ssid("OfficeWiFi")])
        
        try await repository.save(network1)
        try await repository.save(network2)
        
        var detectedNetwork = DetectedNetwork()
        detectedNetwork.ssid = "OfficeWiFi"
        
        let match = try await repository.findMatch(for: detectedNetwork)
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.name, "Office")
    }
    
    // MARK: - Complex Identifier Tests
    
    func test_save_handlesComplexIdentifiers() async throws {
        let network = TrustedNetwork(
            name: "Complex",
            identifiers: [
                .ssid("TestSSID"),
                .bssid("AA:BB:CC:DD:EE:FF"),
                .subnet(try CIDR("192.168.1.0/24")),
                .gateway(IPAddress("192.168.1.1")),
                .combination([
                    .ssid("ComboSSID"),
                    .gateway(IPAddress("10.0.0.1"))
                ])
            ]
        )
        
        try await repository.save(network)
        
        let fetched = try await repository.fetch(by: network.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.identifiers.count, 5)
    }
    
    func test_save_handlesCustomRules() async throws {
        let rules = [
            ProcessRule(processIdentifier: "com.dropbox", action: .block, reason: "Bandwidth hog"),
            ProcessRule(processIdentifier: "com.spotify", action: .allow, reason: "Music is essential")
        ]
        
        let network = TrustedNetwork(
            name: "With Rules",
            identifiers: [.ssid("TestSSID")],
            customRules: rules
        )
        
        try await repository.save(network)
        
        let fetched = try await repository.fetch(by: network.id)
        XCTAssertNotNil(fetched?.customRules)
        XCTAssertEqual(fetched?.customRules?.count, 2)
        XCTAssertEqual(fetched?.customRules?.first?.processIdentifier, "com.dropbox")
        XCTAssertEqual(fetched?.customRules?.first?.action, .block)
    }
}