//
//  Injected.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
import SwiftUI

/// Property wrapper for dependency injection
@propertyWrapper
public struct Injected<T> {
    private let keyPath: KeyPath<DependencyContainer, T>
    private let container: DependencyContainer
    
    public var wrappedValue: T {
        container[keyPath: keyPath]
    }
    
    public init(_ keyPath: KeyPath<DependencyContainer, T>, 
                container: DependencyContainer? = nil) {
        self.keyPath = keyPath
        self.container = container ?? DependencyContainer.shared
    }
}

/// Wrapper for async dependency resolution
@MainActor
public final class AsyncInjected<T> {
    private let resolver: () async -> T
    private var cached: T?
    
    public init(resolver: @escaping () async -> T) {
        self.resolver = resolver
    }
    
    public init(_ keyPath: KeyPath<DependencyContainer, T>,
                container: DependencyContainer? = nil) {
        let actualContainer = container ?? DependencyContainer.shared
        self.resolver = { actualContainer[keyPath: keyPath] }
    }
    
    public func get() async -> T {
        if let cached = cached {
            return cached
        }
        let resolved = await resolver()
        cached = resolved
        return resolved
    }
}

/// Property wrapper for SwiftUI environment injection
@propertyWrapper
public struct EnvironmentInjected<T> {
    @Environment(\.dependencyContainer) private var container
    private let keyPath: KeyPath<DependencyContainer, T>
    
    public var wrappedValue: T {
        container[keyPath: keyPath]
    }
    
    public init(_ keyPath: KeyPath<DependencyContainer, T>) {
        self.keyPath = keyPath
    }
}

// MARK: - SwiftUI Environment Support

@MainActor
private struct DependencyContainerKey: EnvironmentKey {
    static let defaultValue = DependencyContainer.shared
}

public extension EnvironmentValues {
    var dependencyContainer: DependencyContainer {
        get { self[DependencyContainerKey.self] }
        set { self[DependencyContainerKey.self] = newValue }
    }
}

public extension View {
    /// Inject a specific dependency container into the SwiftUI environment
    func dependencyContainer(_ container: DependencyContainer) -> some View {
        environment(\.dependencyContainer, container)
    }
}

// MARK: - Testing Helpers

/// Protocol for types that can be injected
public protocol Injectable {
    associatedtype Dependencies
    init(dependencies: Dependencies)
}

/// Helper for creating mocked dependencies in tests
@MainActor
public struct MockDependencyContainer {
    public static func create() -> DependencyContainer {
        DependencyContainer.configure(for: .testing)
    }
}

// MARK: - Usage Examples

/*
 Usage Examples:
 
 1. Simple injection:
 ```swift
 class MyViewModel {
     @Injected(\.networkMonitor) var networkMonitor
     @Injected(\.persistenceController) var persistence
 }
 ```
 
 2. Async injection:
 ```swift
 class MyService {
     let repository = AsyncInjected(\.trustedNetworkRepository)
     
     func checkNetwork() async {
         let repo = await repository.get()
         let networks = try await repo.fetchAll()
     }
 }
 ```
 
 3. SwiftUI View injection:
 ```swift
 struct MyView: View {
     @EnvironmentInjected(\.networkMonitor) var networkMonitor
     
     var body: some View {
         Text("Connected: \(networkMonitor.isConnected)")
     }
 }
 ```
 
 4. Testing override:
 ```swift
 func testSomething() {
     let container = MockDependencyContainer.create()
     let mockRepo = MockTrustedNetworkRepository()
     container.override(TrustedNetworkRepository.self, with: mockRepo)
     
     // Test with mocked dependency
 }
 ```
 */