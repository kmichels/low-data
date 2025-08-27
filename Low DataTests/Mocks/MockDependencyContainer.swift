//
//  MockDependencyContainer.swift
//  Low DataTests
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
@testable import Low_Data

/// Factory for creating test containers with mocked dependencies
@MainActor
final class MockDependencyFactory {
    
    /// Create a test container with all mocked dependencies
    static func createTestContainer() -> DependencyContainer {
        let container = DependencyContainer.configure(for: .testing)
        
        // Override with mocks as needed
        // Example: container.override(NetworkMonitor.self, with: MockNetworkMonitor())
        
        return container
    }
    
    /// Create a container with specific mocked repositories
    static func createWithMockedRepositories() async -> DependencyContainer {
        let container = DependencyContainer.configure(for: .testing)
        
        // Register mock repositories - using the existing MockRepositories from MockRepositories.swift
        container.register(TrustedNetworkRepository.self) { 
            MockTrustedNetworkRepository()
        }
        
        container.register(TrafficDataRepository.self) {
            MockTrafficDataRepository()
        }
        
        container.register(ProcessProfileRepository.self) {
            MockProcessProfileRepository()
        }
        
        return container
    }
}