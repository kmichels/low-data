//
//  TrustEvaluationUseCaseTests.swift
//  Low DataTests
//
//  Created by Konrad Michels on 8/27/25.
//

import XCTest
@testable import Low_Data

@MainActor
final class TrustEvaluationUseCaseTests: XCTestCase {
    
    var networkMonitor: NetworkMonitor!
    var trustedNetworkRepo: MockTrustedNetworkRepository!
    var trustEvaluationUseCase: TrustEvaluationUseCase!
    var addTrustedNetworkUseCase: AddTrustedNetworkUseCase!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Setup mocks
        networkMonitor = NetworkMonitor()
        trustedNetworkRepo = MockTrustedNetworkRepository()
        
        // Create use cases
        trustEvaluationUseCase = TrustEvaluationUseCase(
            networkMonitor: networkMonitor,
            trustedNetworkRepository: trustedNetworkRepo
        )
        
        addTrustedNetworkUseCase = AddTrustedNetworkUseCase(
            networkMonitor: networkMonitor,
            trustedNetworkRepository: trustedNetworkRepo
        )
    }
    
    override func tearDown() async throws {
        networkMonitor = nil
        trustedNetworkRepo = nil
        trustEvaluationUseCase = nil
        addTrustedNetworkUseCase = nil
        try await super.tearDown()
    }
    
    // MARK: - TrustEvaluationUseCase Tests
    
    func test_trustEvaluation_returnsNotTrustedWhenNoNetwork() async throws {
        // Given - no current network
        networkMonitor.currentNetwork = nil
        
        // When
        let result = try await trustEvaluationUseCase.execute()
        
        // Then
        XCTAssertFalse(result.isTrusted)
        XCTAssertEqual(result.reason, .noNetwork)
        XCTAssertNil(result.matchedNetwork)
    }
    
    func test_trustEvaluation_returnsTrustedForMatchingNetwork() async throws {
        // Given
        let trustedNetwork = TrustedNetwork(
            name: "Home WiFi",
            identifiers: [.ssid("HomeNetwork")]
        )
        await trustedNetworkRepo.networks.append(trustedNetwork)
        
        var detectedNetwork = DetectedNetwork()
        detectedNetwork.ssid = "HomeNetwork"
        detectedNetwork.bssid = "aa:bb:cc:dd:ee:ff"
        detectedNetwork.interfaceName = "en0"
        detectedNetwork.interfaceType = .wifi
        networkMonitor.currentNetwork = detectedNetwork
        
        // When
        let result = try await trustEvaluationUseCase.execute()
        
        // Then
        XCTAssertTrue(result.isTrusted)
        XCTAssertEqual(result.reason, .matchedTrustedNetwork)
        XCTAssertNotNil(result.matchedNetwork)
        XCTAssertEqual(result.matchedNetwork?.id, trustedNetwork.id)
    }
    
    func test_trustEvaluation_returnsNotTrustedForPublicWiFi() async throws {
        // Given
        var detectedNetwork = DetectedNetwork()
        detectedNetwork.ssid = "Starbucks WiFi"
        detectedNetwork.interfaceName = "en0"
        detectedNetwork.interfaceType = .wifi
        networkMonitor.currentNetwork = detectedNetwork
        
        // When
        let result = try await trustEvaluationUseCase.execute()
        
        // Then
        XCTAssertFalse(result.isTrusted)
        XCTAssertEqual(result.reason, .publicWiFi)
        XCTAssertNil(result.matchedNetwork)
    }
    
    func test_trustEvaluation_returnsNotTrustedForCellular() async throws {
        // Given
        var detectedNetwork = DetectedNetwork()
        detectedNetwork.interfaceName = "pdp_ip0"
        detectedNetwork.interfaceType = .cellular
        networkMonitor.currentNetwork = detectedNetwork
        
        // When
        let result = try await trustEvaluationUseCase.execute()
        
        // Then
        XCTAssertFalse(result.isTrusted)
        XCTAssertEqual(result.reason, .cellular)
        XCTAssertNil(result.matchedNetwork)
    }
    
    func test_trustEvaluation_returnsDisabledForDisabledTrustedNetwork() async throws {
        // Given
        var trustedNetwork = TrustedNetwork(
            name: "Office",
            identifiers: [.ssid("OfficeWiFi")]
        )
        trustedNetwork.isEnabled = false
        await trustedNetworkRepo.networks.append(trustedNetwork)
        
        var detectedNetwork = DetectedNetwork()
        detectedNetwork.ssid = "OfficeWiFi"
        detectedNetwork.bssid = "11:22:33:44:55:66"
        detectedNetwork.interfaceName = "en0"
        detectedNetwork.interfaceType = .wifi
        networkMonitor.currentNetwork = detectedNetwork
        
        // When
        let result = try await trustEvaluationUseCase.execute()
        
        // Then
        XCTAssertFalse(result.isTrusted)
        XCTAssertEqual(result.reason, .trustedButDisabled)
        XCTAssertNotNil(result.matchedNetwork)
    }
    
    // MARK: - AddTrustedNetworkUseCase Tests
    
    func test_addTrustedNetwork_createsNetworkFromCurrentConnection() async throws {
        // Given
        var detectedNetwork = DetectedNetwork()
        detectedNetwork.ssid = "TestNetwork"
        detectedNetwork.bssid = "aa:bb:cc:dd:ee:ff"
        detectedNetwork.interfaceName = "en0"
        detectedNetwork.interfaceType = .wifi
        detectedNetwork.ipAddresses = [IPAddress("192.168.1.100")]
        detectedNetwork.gateway = IPAddress("192.168.1.1")
        networkMonitor.currentNetwork = detectedNetwork
        
        let input = AddTrustedNetworkUseCase.Input(
            name: "My Home",
            trustCurrentNetwork: true
        )
        
        // When
        let result = try await addTrustedNetworkUseCase.execute(input)
        
        // Then
        XCTAssertEqual(result.name, "My Home")
        XCTAssertTrue(result.identifiers.contains(.ssid("TestNetwork")))
        XCTAssertTrue(result.identifiers.contains(.subnet("192.168.1.0/24")))
        XCTAssertTrue(result.identifiers.contains(.gateway("192.168.1.1")))
        
        // Verify saved to repository
        await trustedNetworkRepo.assertSaveCalled()
    }
    
    func test_addTrustedNetwork_throwsErrorForEmptyName() async throws {
        // Given
        let input = AddTrustedNetworkUseCase.Input(
            name: "  ",
            trustCurrentNetwork: false,
            customIdentifiers: [.ssid("Test")]
        )
        
        // When/Then
        do {
            _ = try await addTrustedNetworkUseCase.execute(input)
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertTrue(error is UseCaseError)
        }
    }
    
    func test_addTrustedNetwork_throwsErrorWhenNoNetworkAvailable() async throws {
        // Given
        networkMonitor.currentNetwork = nil
        
        let input = AddTrustedNetworkUseCase.Input(
            name: "Test",
            trustCurrentNetwork: true
        )
        
        // When/Then
        do {
            _ = try await addTrustedNetworkUseCase.execute(input)
            XCTFail("Should have thrown error")
        } catch {
            if let useCaseError = error as? UseCaseError {
                XCTAssertEqual(useCaseError, .networkUnavailable)
            } else {
                XCTFail("Wrong error type")
            }
        }
    }
    
    func test_addTrustedNetwork_usesCustomIdentifiers() async throws {
        // Given
        let customIdentifiers = [
            NetworkIdentifier.ssid("CustomSSID"),
            NetworkIdentifier.subnet("10.0.0.0/8")
        ]
        
        let input = AddTrustedNetworkUseCase.Input(
            name: "Custom Network",
            trustCurrentNetwork: false,
            customIdentifiers: customIdentifiers
        )
        
        // When
        let result = try await addTrustedNetworkUseCase.execute(input)
        
        // Then
        XCTAssertEqual(result.name, "Custom Network")
        XCTAssertEqual(result.identifiers, customIdentifiers)
    }
    
    func test_addTrustedNetwork_appliesCustomRules() async throws {
        // Given
        let rules = [
            ProcessRule(
                processIdentifier: "com.dropbox.Dropbox",
                action: .block,
                priority: 100
            )
        ]
        
        let input = AddTrustedNetworkUseCase.Input(
            name: "Restricted Network",
            trustCurrentNetwork: false,
            customIdentifiers: [.ssid("Test")],
            trustLevel: .restricted,
            customRules: rules
        )
        
        // When
        let result = try await addTrustedNetworkUseCase.execute(input)
        
        // Then
        XCTAssertEqual(result.trustLevel, .restricted)
        XCTAssertEqual(result.customRules, rules)
    }
    
    // MARK: - MonitorTrustStateUseCase Tests
    
    func test_monitorTrustState_streamsUpdates() async throws {
        // Given
        let monitorUseCase = MonitorTrustStateUseCase(
            trustEvaluationUseCase: trustEvaluationUseCase,
            networkMonitor: networkMonitor
        )
        
        let input = MonitorTrustStateUseCase.Input(evaluationInterval: 0.1)
        
        // When
        let stream = monitorUseCase.observe(input)
        var results: [TrustEvaluationResult] = []
        
        let task = Task {
            for try await result in stream {
                results.append(result)
                if results.count >= 2 {
                    break
                }
            }
        }
        
        // Give it time to collect results
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        task.cancel()
        
        // Then
        XCTAssertGreaterThanOrEqual(results.count, 2)
    }
}

// MARK: - Mock Extensions

extension MockTrustedNetworkRepository {
    func assertSaveCalled() async {
        XCTAssertTrue(saveCalled, "save() was not called on repository")
    }
}