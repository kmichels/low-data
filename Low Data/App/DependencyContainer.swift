//
//  DependencyContainer.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
import CoreData
import OSLog

/// Main dependency injection container for the application
@MainActor
public final class DependencyContainer: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = DependencyContainer()
    
    // MARK: - Container Types
    
    public enum Scope {
        case singleton
        case transient
    }
    
    public enum Environment {
        case production
        case testing
        case preview
    }
    
    // MARK: - Properties
    
    private let environment: Environment
    private let logger = Logger(subsystem: "com.lowdata", category: "DependencyContainer")
    
    // Registry for factory closures
    private var factories: [String: Any] = [:]
    private var singletons: [String: Any] = [:]
    
    // MARK: - Initialization
    
    private init(environment: Environment = .production) {
        self.environment = environment
        logger.info("Initializing DependencyContainer for environment: \(String(describing: environment))")
        registerDependencies()
    }
    
    /// Configure container for specific environment
    public static func configure(for environment: Environment) -> DependencyContainer {
        return DependencyContainer(environment: environment)
    }
    
    // MARK: - Core Dependencies (Singletons)
    
    /// Core Data persistence controller
    public lazy var persistenceController: PersistenceController = {
        logger.debug("Creating PersistenceController")
        switch environment {
        case .testing:
            return PersistenceController(inMemory: true)
        case .preview:
            return PersistenceController.preview
        case .production:
            return PersistenceController.shared
        }
    }()
    
    /// Network monitoring service
    public lazy var networkMonitor: NetworkMonitor = {
        logger.debug("Creating NetworkMonitor")
        return NetworkMonitor()
    }()
    
    // MARK: - Repository Dependencies
    
    /// Trusted network repository
    public var trustedNetworkRepository: TrustedNetworkRepository {
        get async {
            if let cached = singletons["TrustedNetworkRepository"] as? TrustedNetworkRepository {
                return cached
            }
            
            logger.debug("Creating TrustedNetworkRepository")
            let repository = CoreDataTrustedNetworkRepository(
                container: persistenceController.container
            )
            singletons["TrustedNetworkRepository"] = repository
            return repository
        }
    }
    
    /// Traffic data repository
    public var trafficDataRepository: TrafficDataRepository {
        get async {
            if let cached = singletons["TrafficDataRepository"] as? TrafficDataRepository {
                return cached
            }
            
            logger.debug("Creating TrafficDataRepository")
            let repository = CoreDataTrafficRepository(
                container: persistenceController.container
            )
            singletons["TrafficDataRepository"] = repository
            return repository
        }
    }
    
    /// Process profile repository
    public var processProfileRepository: ProcessProfileRepository {
        get async {
            if let cached = singletons["ProcessProfileRepository"] as? ProcessProfileRepository {
                return cached
            }
            
            logger.debug("Creating ProcessProfileRepository")
            let repository = CoreDataProcessProfileRepository(
                container: persistenceController.container
            )
            singletons["ProcessProfileRepository"] = repository
            return repository
        }
    }
    
    // MARK: - Registration
    
    private func registerDependencies() {
        logger.info("Registering dependencies")
        
        // Register any additional dependencies here
        // This is where we'd register factories for transient dependencies
    }
    
    /// Register a factory for creating dependencies
    public func register<T>(_ type: T.Type, scope: Scope = .singleton, factory: @escaping () async -> T) {
        let key = String(describing: type)
        factories[key] = factory
        logger.debug("Registered factory for \(key) with scope: \(String(describing: scope))")
    }
    
    /// Resolve a dependency
    public func resolve<T>(_ type: T.Type) async -> T? {
        let key = String(describing: type)
        
        // Check singletons first
        if let singleton = singletons[key] as? T {
            return singleton
        }
        
        // Check factories
        if let factory = factories[key] as? () async -> T {
            let instance = await factory()
            // For now, we're treating everything as singleton
            // In a more complex implementation, we'd check scope
            singletons[key] = instance
            return instance
        }
        
        logger.warning("No registration found for type: \(key)")
        return nil
    }
    
    // MARK: - Testing Support
    
    /// Reset container for testing
    public func reset() {
        logger.info("Resetting dependency container")
        singletons.removeAll()
        factories.removeAll()
        registerDependencies()
    }
    
    /// Override a dependency for testing
    public func override<T>(_ type: T.Type, with instance: T) {
        let key = String(describing: type)
        singletons[key] = instance
        logger.debug("Overridden dependency: \(key)")
    }
}

// MARK: - Convenience Accessors

public extension DependencyContainer {
    /// Quick access to shared container
    static var current: DependencyContainer {
        return shared
    }
    
    /// Check if running in test environment
    var isTesting: Bool {
        environment == .testing
    }
    
    /// Check if running in preview environment
    var isPreview: Bool {
        environment == .preview
    }
}