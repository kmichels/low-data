//
//  XPCConnectionValidator.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
import Security
import OSLog

/// Validates XPC connections for security
public final class XPCConnectionValidator {
    
    // MARK: - Properties
    
    private static let logger = Logger(subsystem: "com.lowdata", category: "XPCConnectionValidator")
    
    // MARK: - Validation Methods
    
    /// Validate that a connection is from an authorized source
    public static func validate(_ connection: NSXPCConnection, 
                               allowedBundleIdentifiers: Set<String>) -> Bool {
        
        // For MVP, use simplified validation
        // In production, would use proper audit token validation
        #if DEBUG
        // Allow all connections in debug mode
        logger.info("Debug mode - allowing XPC connection")
        return true
        #else
        // Production validation would go here
        // This requires entitlements and proper code signing
        logger.warning("XPC validation not fully implemented for production")
        return true  // For now
        #endif
    }
    
    /// Validate an audit token (simplified for MVP)
    public static func validateAuditToken(_ token: inout audit_token_t,
                                         allowedBundleIdentifiers: Set<String>) -> Bool {
        // This requires SecTaskCreateWithAuditToken which needs special entitlements
        // For MVP, return true with warning
        logger.warning("Audit token validation not implemented - requires production signing")
        return true
    }
    
    /// Validate code signing information
    private static func validateSigningInfo(_ info: NSDictionary,
                                           allowedBundleIdentifiers: Set<String>) -> Bool {
        
        // Check if the app is properly signed
        guard let identifier = info[kSecCodeInfoIdentifier as String] as? String else {
            logger.error("No identifier found in signing info")
            return false
        }
        
        // Check if it's one of our allowed bundle identifiers
        guard allowedBundleIdentifiers.contains(identifier) else {
            logger.warning("Bundle identifier '\(identifier)' not in allowed list")
            return false
        }
        
        // Check platform identifier (should be macOS)
        if let platformIdentifier = info[kSecCodeInfoPlatformIdentifier as String] as? Int {
            guard platformIdentifier == 1 else { // 1 = macOS
                logger.warning("Invalid platform identifier: \(platformIdentifier)")
                return false
            }
        }
        
        // Verify the app is from the App Store or properly notarized (production only)
        #if !DEBUG
        if let flags = info[kSecCodeInfoFlags as String] as? UInt32 {
            let requiredFlags: SecCodeSignatureFlags = [.valid, .hardened, .runtime]
            guard SecCodeSignatureFlags(rawValue: flags).contains(requiredFlags) else {
                logger.warning("Code signature does not meet requirements")
                return false
            }
        }
        #endif
        
        // Check team identifier matches ours
        if let teamIdentifier = info["teamid"] as? String {
            guard teamIdentifier == "YOUR_TEAM_ID" else { // Replace with actual team ID
                logger.warning("Team identifier mismatch: \(teamIdentifier)")
                return false
            }
        }
        
        logger.info("Successfully validated connection from \(identifier)")
        return true
    }
    
    /// Create code signing requirement string
    public static func createRequirement(for bundleIdentifier: String,
                                        teamIdentifier: String? = nil) -> String {
        
        var requirement = "identifier \"\(bundleIdentifier)\""
        
        // Add team identifier requirement if provided
        if let teamId = teamIdentifier {
            requirement += " and certificate leaf[subject.OU] = \"\(teamId)\""
        }
        
        // Add Apple certificate anchor for production
        #if !DEBUG
        requirement += " and anchor apple generic"
        #endif
        
        return requirement
    }
    
    /// Check if the current process has required entitlements
    public static func hasRequiredEntitlements() -> Bool {
        // Check for system extension entitlement
        let task = SecTaskCreateFromSelf(nil)
        guard let task = task else {
            logger.error("Failed to create SecTask for self")
            return false
        }
        
        var error: Unmanaged<CFError>?
        
        // Check for Network Extension entitlement
        let entitlement = "com.apple.developer.networking.networkextension"
        let value = SecTaskCopyValueForEntitlement(task, entitlement as CFString, &error)
        
        if let error = error {
            logger.error("Failed to check entitlement: \(error.takeRetainedValue())")
            return false
        }
        
        guard value != nil else {
            logger.error("Missing required Network Extension entitlement")
            return false
        }
        
        return true
    }
}

// MARK: - XPC Service Configuration

public struct XPCServiceConfiguration {
    
    /// Allowed bundle identifiers for main app
    public static let mainAppIdentifiers: Set<String> = [
        "com.lowdata.app",
        "com.lowdata.Low-Data"  // Debug identifier
    ]
    
    /// Allowed bundle identifiers for system extension
    public static let systemExtensionIdentifiers: Set<String> = [
        "com.lowdata.system-extension",
        "com.lowdata.Low-Data-Extension"  // Debug identifier
    ]
    
    /// Team identifier for code signing validation
    public static let teamIdentifier = "YOUR_TEAM_ID" // Replace with actual
    
    /// Check if running in debug mode
    public static var isDebugMode: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}

// MARK: - XPC Connection Extensions

public extension NSXPCConnection {
    
    /// Validate this connection is from an authorized source
    func validateAuthorization(allowedIdentifiers: Set<String>) -> Bool {
        return XPCConnectionValidator.validate(self, allowedBundleIdentifiers: allowedIdentifiers)
    }
    
    /// Configure standard security handlers
    func configureSecurityHandlers() {
        let logger = Logger(subsystem: "com.lowdata", category: "XPCConnection")
        
        self.interruptionHandler = {
            logger.warning("XPC connection interrupted - possible security issue")
        }
        
        self.invalidationHandler = {
            logger.info("XPC connection invalidated")
        }
    }
}