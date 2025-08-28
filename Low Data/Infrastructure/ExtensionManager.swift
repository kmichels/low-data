//
//  ExtensionManager.swift
//  Low Data
//
//  Created on 8/28/25.
//

import Foundation
import SystemExtensions
import NetworkExtension
import os.log

/// Result of extension activation
public enum ExtensionActivationResult {
    case success
    case needsUserApproval
    case failed(Error)
}

/// Manages the System Extension lifecycle
@MainActor
public final class ExtensionManager: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    @Published public private(set) var extensionStatus: ExtensionStatus = .notInstalled
    @Published public private(set) var isActivating = false
    @Published public private(set) var lastError: Error?
    
    private let logger = Logger(subsystem: "com.tonalphoto.tech.Low-Data", category: "ExtensionManager")
    private let extensionBundleId = "com.tonalphoto.tech.Low-Data.Low-Data-Extensino"
    
    private var activationRequest: OSSystemExtensionRequest?
    
    // MARK: - Singleton
    
    public static let shared = ExtensionManager()
    
    private override init() {
        super.init()
        checkExtensionStatus()
    }
    
    // MARK: - Public Methods
    
    /// Activates the System Extension
    public func activateExtension() async -> ExtensionActivationResult {
        guard !isActivating else {
            logger.warning("Extension activation already in progress")
            return .failed(ExtensionError.alreadyActivating)
        }
        
        logger.info("Starting extension activation")
        isActivating = true
        lastError = nil
        
        return await withCheckedContinuation { continuation in
            self.activationContinuation = continuation
            
            let request = OSSystemExtensionRequest.activationRequest(
                forExtensionWithIdentifier: extensionBundleId,
                queue: .main
            )
            
            request.delegate = self
            self.activationRequest = request
            
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }
    
    /// Deactivates the System Extension
    public func deactivateExtension() async -> Bool {
        logger.info("Starting extension deactivation")
        
        return await withCheckedContinuation { continuation in
            self.deactivationContinuation = continuation
            
            let request = OSSystemExtensionRequest.deactivationRequest(
                forExtensionWithIdentifier: extensionBundleId,
                queue: .main
            )
            
            request.delegate = self
            
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }
    
    /// Checks current extension status
    public func checkExtensionStatus() {
        Task {
            await updateFilterStatus()
        }
    }
    
    /// Enables content filtering
    public func enableContentFilter() async throws {
        guard extensionStatus == .running else {
            throw ExtensionError.notRunning
        }
        
        let manager = await getFilterManager()
        
        guard let manager = manager else {
            throw ExtensionError.filterConfigurationNotFound
        }
        
        manager.isEnabled = true
        
        try await manager.saveToPreferences()
        logger.info("Content filter enabled")
    }
    
    /// Disables content filtering
    public func disableContentFilter() async throws {
        let manager = await getFilterManager()
        
        guard let manager = manager else {
            throw ExtensionError.filterConfigurationNotFound
        }
        
        manager.isEnabled = false
        
        try await manager.saveToPreferences()
        logger.info("Content filter disabled")
    }
    
    // MARK: - Private Methods
    
    private var activationContinuation: CheckedContinuation<ExtensionActivationResult, Never>?
    private var deactivationContinuation: CheckedContinuation<Bool, Never>?
    
    private func updateFilterStatus() async {
        // Check if extension is registered with the system
        let manager = NEFilterManager.shared()
        
        do {
            try await manager.loadFromPreferences()
            
            if manager.providerConfiguration != nil {
                if manager.isEnabled {
                    extensionStatus = .running
                } else {
                    extensionStatus = .installed
                }
            } else {
                // Try to create configuration
                await createFilterConfiguration()
            }
        } catch {
            logger.error("Failed to load filter preferences: \(error.localizedDescription)")
            extensionStatus = .notInstalled
        }
    }
    
    private func createFilterConfiguration() async {
        let manager = NEFilterManager.shared()
        
        do {
            try await manager.loadFromPreferences()
            
            if manager.providerConfiguration == nil {
                let config = NEFilterProviderConfiguration()
                config.organization = "TonalPhoto Tech"
                // filterBrowsers is deprecated in macOS 10.15+
                // config.filterBrowsers = true
                config.filterSockets = true
                
                manager.providerConfiguration = config
                manager.localizedDescription = "Low Data Network Filter"
                manager.isEnabled = false // Start disabled
                
                try await manager.saveToPreferences()
                logger.info("Filter configuration created")
            }
            
        } catch {
            logger.error("Failed to create filter configuration: \(error.localizedDescription)")
            lastError = error
        }
    }
    
    private func getFilterManager() async -> NEFilterManager? {
        let manager = NEFilterManager.shared()
        
        do {
            try await manager.loadFromPreferences()
            return manager.providerConfiguration != nil ? manager : nil
        } catch {
            logger.error("Failed to load filter manager: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - OSSystemExtensionRequestDelegate

extension ExtensionManager: OSSystemExtensionRequestDelegate {
    
    nonisolated public func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        Logger(subsystem: "com.tonalphoto.tech.Low-Data", category: "ExtensionManager").info("Replacing extension version \(existing.bundleShortVersion) with \(ext.bundleShortVersion)")
        return .replace
    }
    
    nonisolated public func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        Logger(subsystem: "com.tonalphoto.tech.Low-Data", category: "ExtensionManager").info("Extension needs user approval")
        
        DispatchQueue.main.async {
            self.extensionStatus = .needsApproval
            self.isActivating = false
            
            if let continuation = self.activationContinuation {
                continuation.resume(returning: .needsUserApproval)
                self.activationContinuation = nil
            }
        }
    }
    
    nonisolated public func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        Logger(subsystem: "com.tonalphoto.tech.Low-Data", category: "ExtensionManager").info("Extension request finished with result: \(result.rawValue)")
        
        DispatchQueue.main.async {
            self.isActivating = false
            
            switch result {
            case .completed:
                self.extensionStatus = .installed
                Task {
                    await self.updateFilterStatus()
                }
                
                if let continuation = self.activationContinuation {
                    continuation.resume(returning: .success)
                    self.activationContinuation = nil
                }
                
                if let continuation = self.deactivationContinuation {
                    continuation.resume(returning: true)
                    self.deactivationContinuation = nil
                }
                
            case .willCompleteAfterReboot:
                self.extensionStatus = .requiresReboot
                
                if let continuation = self.activationContinuation {
                    continuation.resume(returning: .success)
                    self.activationContinuation = nil
                }
                
            @unknown default:
                break
            }
        }
    }
    
    nonisolated public func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        Logger(subsystem: "com.tonalphoto.tech.Low-Data", category: "ExtensionManager").error("Extension request failed: \(error.localizedDescription)")
        
        DispatchQueue.main.async {
            self.isActivating = false
            self.lastError = error
            
            if let continuation = self.activationContinuation {
                continuation.resume(returning: .failed(error))
                self.activationContinuation = nil
            }
            
            if let continuation = self.deactivationContinuation {
                continuation.resume(returning: false)
                self.deactivationContinuation = nil
            }
        }
    }
}

// MARK: - Supporting Types

/// Current status of the System Extension
public enum ExtensionStatus: Equatable {
    case notInstalled
    case installed
    case needsApproval
    case requiresReboot
    case running
    case error(String)
}

/// Errors that can occur during extension management
public enum ExtensionError: LocalizedError {
    case alreadyActivating
    case notRunning
    case filterConfigurationNotFound
    case activationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .alreadyActivating:
            return "Extension activation is already in progress"
        case .notRunning:
            return "Extension is not running"
        case .filterConfigurationNotFound:
            return "Filter configuration not found"
        case .activationFailed(let reason):
            return "Extension activation failed: \(reason)"
        }
    }
}