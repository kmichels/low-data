//
//  BrewServiceDetector.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
import OSLog

/// Detects and identifies Homebrew-installed services
public final class BrewServiceDetector {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.lowdata", category: "BrewServiceDetector")
    private let fileManager = FileManager.default
    
    // Common Homebrew installation paths
    private let brewPaths = [
        "/opt/homebrew",          // Apple Silicon
        "/usr/local",              // Intel
        "/home/linuxbrew/.linuxbrew" // Linux (for compatibility)
    ]
    
    // Cache of known brew services
    private var knownServices: Set<String> = []
    private var lastScanDate: Date?
    private let scanInterval: TimeInterval = 3600 // Re-scan every hour
    
    // MARK: - Initialization
    
    public init() {
        scanBrewServices()
    }
    
    // MARK: - Public Methods
    
    /// Check if a path belongs to a Homebrew service
    public func isBrewService(path: String) -> Bool {
        // Refresh cache if needed
        if shouldRefreshCache() {
            scanBrewServices()
        }
        
        // Check if path contains Homebrew directories
        for brewPath in brewPaths {
            if path.hasPrefix(brewPath) {
                return true
            }
        }
        
        // Check against known services
        let executable = URL(fileURLWithPath: path).lastPathComponent
        return knownServices.contains(executable)
    }
    
    /// Extract service name from a Homebrew service path
    public func extractServiceName(from path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        
        // Remove common prefixes/suffixes
        var serviceName = name
        
        // Remove version numbers (e.g., "postgresql@14" -> "postgresql")
        if let atIndex = serviceName.firstIndex(of: "@") {
            serviceName = String(serviceName[..<atIndex])
        }
        
        // Remove .plist extension if present
        if serviceName.hasSuffix(".plist") {
            serviceName = String(serviceName.dropLast(6))
        }
        
        // Capitalize for display
        return serviceName.isEmpty ? nil : formatServiceName(serviceName)
    }
    
    /// Get list of all detected Homebrew services
    public func detectedServices() -> [String] {
        if shouldRefreshCache() {
            scanBrewServices()
        }
        return Array(knownServices).sorted()
    }
    
    // MARK: - Private Methods
    
    private func shouldRefreshCache() -> Bool {
        guard let lastScan = lastScanDate else { return true }
        return Date().timeIntervalSince(lastScan) > scanInterval
    }
    
    private func scanBrewServices() {
        var services = Set<String>()
        
        for brewPath in brewPaths {
            // Check Cellar directory for installed formulas
            let cellarPath = "\(brewPath)/Cellar"
            if fileManager.fileExists(atPath: cellarPath) {
                scanDirectory(cellarPath, into: &services)
            }
            
            // Check opt directory for linked formulas
            let optPath = "\(brewPath)/opt"
            if fileManager.fileExists(atPath: optPath) {
                scanDirectory(optPath, into: &services)
            }
            
            // Check var directory for service data
            let varPath = "\(brewPath)/var"
            if fileManager.fileExists(atPath: varPath) {
                scanServiceDirectory(varPath, into: &services)
            }
        }
        
        // Also check LaunchAgents for Homebrew services
        let launchAgentsPaths = [
            "\(NSHomeDirectory())/Library/LaunchAgents",
            "/Library/LaunchAgents"
        ]
        
        for launchPath in launchAgentsPaths {
            scanLaunchAgents(launchPath, into: &services)
        }
        
        knownServices = services
        lastScanDate = Date()
        
        logger.info("Detected \(services.count) Homebrew services")
    }
    
    private func scanDirectory(_ path: String, into services: inout Set<String>) {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else {
            return
        }
        
        for item in contents {
            let itemPath = "\(path)/\(item)"
            var isDirectory: ObjCBool = false
            
            if fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // Look for bin directory
                    let binPath = "\(itemPath)/bin"
                    if fileManager.fileExists(atPath: binPath) {
                        if let binContents = try? fileManager.contentsOfDirectory(atPath: binPath) {
                            services.formUnion(binContents)
                        }
                    }
                    
                    // Also add the directory name itself (often the service name)
                    services.insert(item)
                }
            }
        }
    }
    
    private func scanServiceDirectory(_ path: String, into services: inout Set<String>) {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else {
            return
        }
        
        for item in contents {
            // Common service directories in var/
            if item == "postgresql" || item == "mysql" || item == "redis" || 
               item == "mongodb" || item == "elasticsearch" || item == "nginx" {
                services.insert(item)
            }
        }
    }
    
    private func scanLaunchAgents(_ path: String, into services: inout Set<String>) {
        guard let contents = try? fileManager.contentsOfDirectory(atPath: path) else {
            return
        }
        
        for item in contents {
            if item.hasPrefix("homebrew.mxcl.") {
                // Extract service name from plist filename
                // e.g., "homebrew.mxcl.postgresql@14.plist" -> "postgresql"
                let serviceName = item
                    .replacingOccurrences(of: "homebrew.mxcl.", with: "")
                    .replacingOccurrences(of: ".plist", with: "")
                
                if let atIndex = serviceName.firstIndex(of: "@") {
                    services.insert(String(serviceName[..<atIndex]))
                } else {
                    services.insert(serviceName)
                }
            }
        }
    }
    
    private func formatServiceName(_ name: String) -> String {
        // Format common service names nicely
        let formatted = name.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        
        // Capitalize each word
        return formatted.split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

// MARK: - Common Homebrew Services

public extension BrewServiceDetector {
    /// Known bandwidth-intensive Homebrew services
    static let bandwidthIntensiveServices = Set([
        "docker",
        "elasticsearch",
        "jenkins",
        "minio",
        "mongodb",
        "mysql",
        "postgresql",
        "redis",
        "kafka",
        "rabbitmq",
        "nginx",
        "apache",
        "httpd"
    ])
    
    /// Check if a service is known to be bandwidth-intensive
    func isBandwidthIntensive(_ serviceName: String) -> Bool {
        let normalized = serviceName.lowercased()
        return Self.bandwidthIntensiveServices.contains { normalized.contains($0) }
    }
}