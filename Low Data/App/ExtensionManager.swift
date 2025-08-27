//
//  ExtensionManager.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
import SystemExtensions
import NetworkExtension
import OSLog

/// Manages System Extension installation and activation
@MainActor
public final class ExtensionManager: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.lowdata", category: "ExtensionManager")
    
    @Published public var extensionStatus: ExtensionStatus = .notInstalled
    @Published public var filterStatus: FilterStatus?
    @Published public var installationProgress: Double = 0.0
    @Published public var errorMessage: String?
    
    private var activationRequest: OSSystemExtensionRequest?
    
    // Bundle identifier for the system extension
    private let extensionBundleIdentifier = "com.lowdata.system-extension"
    
    // MARK: - Public Methods
    
    /// Install and activate the system extension
    public func installExtension() async throws {
        logger.info("Starting system extension installation...")
        
        extensionStatus = .installing
        installationProgress = 0.1
        
        // Create activation request
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionBundleIdentifier,
            queue: .main
        )
        
        request.delegate = self
        self.activationRequest = request
        
        // Submit the request
        OSSystemExtensionManager.shared.submitRequest(request)
        
        // Wait for installation
        try await waitForInstallation()
    }
    
    /// Uninstall the system extension
    public func uninstallExtension() async throws {
        logger.info("Starting system extension uninstallation...")
        
        extensionStatus = .uninstalling
        
        // Create deactivation request
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: extensionBundleIdentifier,
            queue: .main
        )
        
        request.delegate = self
        self.activationRequest = request
        
        // Submit the request
        OSSystemExtensionManager.shared.submitRequest(request)
        
        // Wait for uninstallation
        try await waitForUninstallation()
    }
    
    /// Enable content filtering
    public func enableFiltering() async throws {
        logger.info("Enabling content filter...")
        
        // Load the filter configuration
        let filterManager = NEFilterManager.shared()
        try await filterManager.loadFromPreferences()
        
        // Check if already configured
        if filterManager.providerConfiguration == nil {
            // Create new filter configuration
            let providerConfiguration = NEFilterProviderConfiguration()
            providerConfiguration.filterBrowsers = false
            providerConfiguration.filterSockets = true
            providerConfiguration.filterDataProviderBundleIdentifier = extensionBundleIdentifier
            providerConfiguration.serverAddress = "127.0.0.1"  // Local
            providerConfiguration.username = "Low Data"
            providerConfiguration.organization = "Low Data"
            
            filterManager.providerConfiguration = providerConfiguration
            filterManager.localizedDescription = "Low Data Network Filter"
        }
        
        // Enable the filter
        filterManager.isEnabled = true
        
        // Save configuration
        try await filterManager.saveToPreferences()
        
        logger.info("Content filter enabled")
        
        // Update status
        await updateFilterStatus()
    }
    
    /// Disable content filtering
    public func disableFiltering() async throws {
        logger.info("Disabling content filter...")
        
        let filterManager = NEFilterManager.shared()
        try await filterManager.loadFromPreferences()
        
        filterManager.isEnabled = false
        
        try await filterManager.saveToPreferences()
        
        logger.info("Content filter disabled")
        
        // Update status
        await updateFilterStatus()
    }
    
    /// Check extension and filter status
    public func checkStatus() async {
        await updateExtensionStatus()
        await updateFilterStatus()
    }
    
    // MARK: - Private Methods
    
    private func waitForInstallation() async throws {
        // Wait up to 30 seconds for installation
        let timeout = 30.0
        let startTime = Date()
        
        while extensionStatus == .installing {
            if Date().timeIntervalSince(startTime) > timeout {
                throw ExtensionError.installationTimeout
            }
            
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        if extensionStatus != .installed {
            throw ExtensionError.installationFailed(errorMessage ?? "Unknown error")
        }
    }
    
    private func waitForUninstallation() async throws {
        // Wait up to 30 seconds for uninstallation
        let timeout = 30.0
        let startTime = Date()
        
        while extensionStatus == .uninstalling {
            if Date().timeIntervalSince(startTime) > timeout {
                throw ExtensionError.uninstallationTimeout
            }
            
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        if extensionStatus != .notInstalled {
            throw ExtensionError.uninstallationFailed(errorMessage ?? "Unknown error")
        }
    }
    
    private func updateExtensionStatus() async {
        // Check if extension is installed
        // This is a simplified check - in production would query system
        
        let filterManager = NEFilterManager.shared()
        do {
            try await filterManager.loadFromPreferences()
            
            if filterManager.providerConfiguration != nil {
                extensionStatus = .installed
            } else {
                extensionStatus = .notInstalled
            }
        } catch {
            logger.error("Failed to check extension status: \(error.localizedDescription)")
            extensionStatus = .notInstalled
        }
    }
    
    private func updateFilterStatus() async {
        // Get filter status via XPC
        do {
            filterStatus = try await FilterControlXPCService.shared.getFilterStatus()
        } catch {
            logger.error("Failed to get filter status: \(error.localizedDescription)")
        }
    }
}

// MARK: - OSSystemExtensionRequestDelegate

extension ExtensionManager: OSSystemExtensionRequestDelegate {
    
    public func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        logger.info("Replacing extension version \(existing.bundleShortVersion) with \(ext.bundleShortVersion)")
        return .replace
    }
    
    public func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        logger.info("Extension needs user approval")
        installationProgress = 0.5
        
        DispatchQueue.main.async {
            self.extensionStatus = .needsApproval
        }
    }
    
    public func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        logger.info("Extension request finished with result: \(result.rawValue)")
        
        DispatchQueue.main.async {
            self.installationProgress = 1.0
            
            switch result {
            case .completed:
                if request is OSSystemExtensionRequest {
                    self.extensionStatus = .installed
                } else {
                    self.extensionStatus = .notInstalled
                }
                self.errorMessage = nil
                
            case .willCompleteAfterReboot:
                self.extensionStatus = .needsReboot
                self.errorMessage = "System extension will be activated after reboot"
                
            @unknown default:
                self.extensionStatus = .error
                self.errorMessage = "Unknown result"
            }
        }
    }
    
    public func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        logger.error("Extension request failed: \(error.localizedDescription)")
        
        DispatchQueue.main.async {
            self.installationProgress = 0.0
            self.extensionStatus = .error
            self.errorMessage = error.localizedDescription
            
            // Handle specific errors
            if let osError = error as? OSSystemExtensionError {
                switch osError.code {
                case .missingEntitlement:
                    self.errorMessage = "App is missing required entitlements"
                case .unsupportedParentBundleLocation:
                    self.errorMessage = "App must be in /Applications folder"
                case .extensionNotFound:
                    self.errorMessage = "System extension not found in app bundle"
                case .duplicateExtensionIdentifer:
                    self.errorMessage = "Extension is already installed"
                case .authorizationRequired:
                    self.errorMessage = "User authorization required"
                default:
                    break
                }
            }
        }
    }
}

// MARK: - Supporting Types

public enum ExtensionStatus {
    case notInstalled
    case installing
    case needsApproval
    case needsReboot
    case installed
    case uninstalling
    case error
}

public enum ExtensionError: LocalizedError {
    case installationTimeout
    case installationFailed(String)
    case uninstallationTimeout
    case uninstallationFailed(String)
    case filterConfigurationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .installationTimeout:
            return "System extension installation timed out"
        case .installationFailed(let reason):
            return "Installation failed: \(reason)"
        case .uninstallationTimeout:
            return "System extension uninstallation timed out"
        case .uninstallationFailed(let reason):
            return "Uninstallation failed: \(reason)"
        case .filterConfigurationFailed(let reason):
            return "Filter configuration failed: \(reason)"
        }
    }
}