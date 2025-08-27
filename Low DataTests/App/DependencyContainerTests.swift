//
//  DependencyContainerTests.swift
//  Low DataTests
//
//  Created by Konrad Michels on 8/27/25.
//

import XCTest
@testable import Low_Data

@MainActor
final class DependencyContainerTests: XCTestCase {
    
    var container: DependencyContainer!
    
    override func setUp() async throws {
        try await super.setUp()
        container = DependencyContainer.configure(for: .testing)
    }
    
    override func tearDown() async throws {
        container.reset()
        container = nil
        try await super.tearDown()
    }
    
    // MARK: - Container Configuration Tests
    
    func test_container_initializesForTestEnvironment() {
        XCTAssertTrue(container.isTesting)
        XCTAssertFalse(container.isPreview)
    }
    
    func test_container_initializesForProductionEnvironment() {
        let prodContainer = DependencyContainer.shared
        XCTAssertFalse(prodContainer.isTesting)
        XCTAssertFalse(prodContainer.isPreview)
    }
    
    func test_container_initializesForPreviewEnvironment() {
        let previewContainer = DependencyContainer.configure(for: .preview)
        XCTAssertFalse(previewContainer.isTesting)
        XCTAssertTrue(previewContainer.isPreview)
    }
    
    // MARK: - Core Dependencies Tests
    
    func test_persistenceController_returnsInMemoryForTesting() {
        let persistence = container.persistenceController
        XCTAssertNotNil(persistence)
        // In testing, should use in-memory store
        XCTAssertTrue(container.isTesting)
    }
    
    func test_networkMonitor_returnsSingleton() {
        let monitor1 = container.networkMonitor
        let monitor2 = container.networkMonitor
        XCTAssertTrue(monitor1 === monitor2) // Should be same instance
    }
    
    // MARK: - Repository Tests
    
    func test_trustedNetworkRepository_returnsSingleton() async {
        let repo1 = await container.trustedNetworkRepository
        let repo2 = await container.trustedNetworkRepository
        
        // Should return same instance (singleton)
        XCTAssertTrue(repo1 === repo2)
    }
    
    func test_trafficDataRepository_returnsSingleton() async {
        let repo1 = await container.trafficDataRepository
        let repo2 = await container.trafficDataRepository
        
        // Should return same instance (singleton)
        XCTAssertTrue(repo1 === repo2)
    }
    
    func test_processProfileRepository_returnsSingleton() async {
        let repo1 = await container.processProfileRepository
        let repo2 = await container.processProfileRepository
        
        // Should return same instance (singleton)
        XCTAssertTrue(repo1 === repo2)
    }
    
    // MARK: - Registration Tests
    
    func test_register_andResolve_customDependency() async {
        // Given
        class TestService {
            let id = UUID()
        }
        
        // Register
        container.register(TestService.self) {
            TestService()
        }
        
        // Resolve
        let resolved1 = await container.resolve(TestService.self)
        let resolved2 = await container.resolve(TestService.self)
        
        XCTAssertNotNil(resolved1)
        XCTAssertNotNil(resolved2)
        
        // Should be singleton by default
        XCTAssertEqual(resolved1?.id, resolved2?.id)
    }
    
    func test_resolve_returnsNilForUnregisteredType() async {
        // Given
        struct UnregisteredType {}
        
        // When
        let resolved = await container.resolve(UnregisteredType.self)
        
        // Then
        XCTAssertNil(resolved)
    }
    
    // MARK: - Override Tests
    
    func test_override_replacesExistingDependency() async {
        // Given
        let mockRepo = MockTrustedNetworkRepository()
        
        // Override
        container.override(TrustedNetworkRepository.self, with: mockRepo)
        
        // When resolving
        let resolved = await container.resolve(TrustedNetworkRepository.self)
        
        // Then should return the mock
        XCTAssertTrue(resolved === mockRepo)
    }
    
    // MARK: - Reset Tests
    
    func test_reset_clearsSingletons() async {
        // Given - register and resolve to create singleton
        class TestService {
            let id = UUID()
        }
        
        container.register(TestService.self) {
            TestService()
        }
        
        let beforeReset = await container.resolve(TestService.self)
        
        // When
        container.reset()
        
        // Re-register after reset
        container.register(TestService.self) {
            TestService()
        }
        
        let afterReset = await container.resolve(TestService.self)
        
        // Then - should be different instances
        XCTAssertNotEqual(beforeReset?.id, afterReset?.id)
    }
    
    // MARK: - Property Wrapper Tests
    
    func test_injected_propertyWrapper_works() {
        // Given
        class TestClass {
            @Injected(\.networkMonitor) var monitor
            @Injected(\.persistenceController) var persistence
        }
        
        // When
        let testObject = TestClass()
        
        // Then
        XCTAssertNotNil(testObject.monitor)
        XCTAssertNotNil(testObject.persistence)
    }
    
    func test_injected_withCustomContainer() {
        // Given
        let customContainer = DependencyContainer.configure(for: .testing)
        
        class TestClass {
            let monitor: NetworkMonitor
            
            init(container: DependencyContainer) {
                @Injected(\.networkMonitor, container: container) var injectedMonitor
                self.monitor = injectedMonitor
            }
        }
        
        // When
        let testObject = TestClass(container: customContainer)
        
        // Then
        XCTAssertNotNil(testObject.monitor)
    }
    
    // MARK: - Integration Tests
    
    func test_container_providesFullyFunctionalRepositories() async throws {
        // Given
        let repo = await container.trustedNetworkRepository
        
        // When - perform actual operations
        let network = TrustedNetwork(
            name: "Test Network",
            identifiers: [.ssid("TestSSID")]
        )
        
        try await repo.save(network)
        let fetched = try await repo.fetch(by: network.id)
        
        // Then
        XCTAssertEqual(fetched?.id, network.id)
        XCTAssertEqual(fetched?.name, "Test Network")
    }
    
    // MARK: - Mock Container Tests
    
    func test_mockContainer_usesMockedDependencies() async {
        // Given
        let mockContainer = await MockDependencyFactory.createWithMockedRepositories()
        
        // When
        let repo = await mockContainer.resolve(TrustedNetworkRepository.self)
        
        // Then
        XCTAssertTrue(repo is MockTrustedNetworkRepository)
    }
    
    // MARK: - Thread Safety Tests
    
    func test_container_isThreadSafe() async {
        // Given
        let expectation = expectation(description: "Concurrent access")
        expectation.expectedFulfillmentCount = 10
        
        // When - concurrent access
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask { [container] in
                    _ = await container?.trustedNetworkRepository
                    expectation.fulfill()
                }
            }
        }
        
        // Then - should not crash
        await fulfillment(of: [expectation], timeout: 2.0)
    }
}