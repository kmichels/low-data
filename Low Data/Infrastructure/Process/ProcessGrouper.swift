//
//  ProcessGrouper.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
import OSLog

/// Groups helper processes with their parent applications
public final class ProcessGrouper {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.lowdata", category: "ProcessGrouper")
    
    // Known helper process patterns
    private let helperPatterns: [(parent: String, helpers: [String])] = [
        // Dropbox and its helpers
        ("com.dropbox.Dropbox", [
            "com.dropbox.DropboxHelper",
            "com.dropbox.DropboxMacUpdate",
            "Dropbox Helper",
            "dbfseventsd"
        ]),
        
        // Google Chrome and helpers
        ("com.google.Chrome", [
            "com.google.Chrome.helper",
            "com.google.Chrome.helper.GPU",
            "com.google.Chrome.helper.Plugin",
            "com.google.Chrome.helper.Renderer",
            "Chrome Helper"
        ]),
        
        // Safari and helpers
        ("com.apple.Safari", [
            "com.apple.WebKit.WebContent",
            "com.apple.WebKit.Networking",
            "com.apple.WebKit.GPU",
            "Safari Web Content",
            "Safari Networking"
        ]),
        
        // Spotify
        ("com.spotify.client", [
            "com.spotify.client.helper",
            "Spotify Helper"
        ]),
        
        // Slack
        ("com.tinyspeck.slackmacgap", [
            "Slack Helper",
            "Slack Helper (Renderer)",
            "Slack Helper (GPU)",
            "Slack Helper (Plugin)"
        ]),
        
        // Microsoft Teams
        ("com.microsoft.teams", [
            "com.microsoft.teams.helper",
            "Teams Helper",
            "Microsoft Teams Helper"
        ]),
        
        // Visual Studio Code
        ("com.microsoft.VSCode", [
            "Code Helper",
            "Code Helper (Renderer)",
            "Code Helper (GPU)",
            "Code Helper (Plugin)"
        ]),
        
        // Docker
        ("com.docker.docker", [
            "com.docker.helper",
            "com.docker.vmnetd",
            "Docker",
            "dockerd"
        ]),
        
        // Adobe Creative Cloud
        ("com.adobe.CreativeCloud", [
            "Adobe Creative Cloud Helper",
            "AdobeCRDaemon",
            "Core Sync",
            "CCLibrary",
            "CCXProcess"
        ]),
        
        // 1Password
        ("com.1password.1Password", [
            "1Password Extension Helper",
            "1Password Launcher",
            "1Password-BrowserSupport"
        ])
    ]
    
    // Cache of process relationships
    private var parentCache: [String: String] = [:]
    private let cacheLock = NSLock()
    
    // MARK: - Public Methods
    
    /// Find the parent application for a helper process
    public func findParent(for process: ProcessIdentity) -> ProcessIdentity? {
        // Check cache first
        if let cachedParent = getCachedParent(for: process.identifier) {
            return identifyParent(bundleId: cachedParent)
        }
        
        // Check known patterns
        for pattern in helperPatterns {
            if matchesHelper(process: process, helpers: pattern.helpers) {
                cacheParent(pattern.parent, for: process.identifier)
                return identifyParent(bundleId: pattern.parent)
            }
        }
        
        // Try to infer from bundle identifier
        if let parentBundleId = inferParentFromBundleId(process.bundleId) {
            cacheParent(parentBundleId, for: process.identifier)
            return identifyParent(bundleId: parentBundleId)
        }
        
        // Try to infer from process name
        if let parentBundleId = inferParentFromName(process.name) {
            cacheParent(parentBundleId, for: process.identifier)
            return identifyParent(bundleId: parentBundleId)
        }
        
        return nil
    }
    
    /// Group a list of processes by their parent applications
    public func groupProcesses(_ processes: [ProcessIdentity]) -> [ProcessGroup] {
        var groups: [String: ProcessGroup] = [:]
        var ungrouped: [ProcessIdentity] = []
        
        for process in processes {
            if let parent = findParent(for: process) {
                let key = parent.identifier
                if groups[key] == nil {
                    groups[key] = ProcessGroup(parent: parent, helpers: [])
                }
                groups[key]?.helpers.append(process)
            } else if process.type == .application {
                // It's a parent application itself
                let key = process.identifier
                if groups[key] == nil {
                    groups[key] = ProcessGroup(parent: process, helpers: [])
                }
            } else {
                // Can't determine parent
                ungrouped.append(process)
            }
        }
        
        // Add ungrouped processes as standalone groups
        for process in ungrouped {
            groups[process.identifier] = ProcessGroup(parent: process, helpers: [])
        }
        
        return Array(groups.values).sorted { $0.parent.name < $1.parent.name }
    }
    
    /// Check if a process is a helper for another application
    public func isHelper(_ process: ProcessIdentity) -> Bool {
        // Check if it matches any known helper pattern
        for pattern in helperPatterns {
            if matchesHelper(process: process, helpers: pattern.helpers) {
                return true
            }
        }
        
        // Check common helper indicators in name
        let name = process.name.lowercased()
        return name.contains("helper") ||
               name.contains("renderer") ||
               name.contains("gpu") ||
               name.contains("plugin") ||
               name.contains("extension")
    }
    
    // MARK: - Private Methods
    
    private func matchesHelper(process: ProcessIdentity, helpers: [String]) -> Bool {
        let processId = process.identifier.lowercased()
        let processName = process.name.lowercased()
        
        for helper in helpers {
            let helperLower = helper.lowercased()
            if processId.contains(helperLower) || processName.contains(helperLower) {
                return true
            }
        }
        
        return false
    }
    
    private func inferParentFromBundleId(_ bundleId: String?) -> String? {
        guard let bundleId = bundleId else { return nil }
        
        // Remove .helper, .Helper, .GPU, etc. suffixes
        let suffixes = [".helper", ".Helper", ".GPU", ".Renderer", ".Plugin", ".WebContent", ".Networking"]
        
        var parentId = bundleId
        for suffix in suffixes {
            if parentId.hasSuffix(suffix) {
                parentId = String(parentId.dropLast(suffix.count))
                break
            }
        }
        
        return parentId != bundleId ? parentId : nil
    }
    
    private func inferParentFromName(_ name: String) -> String? {
        // Try to extract parent app name from helper process name
        // e.g., "Dropbox Helper" -> "Dropbox"
        
        let helperKeywords = ["Helper", "Renderer", "GPU", "Plugin", "Extension"]
        
        for keyword in helperKeywords {
            if name.contains(keyword) {
                let parentName = name.replacingOccurrences(of: keyword, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "  ", with: " ")
                    .replacingOccurrences(of: "(", with: "")
                    .replacingOccurrences(of: ")", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !parentName.isEmpty && parentName != name {
                    // Try to find matching parent in known patterns
                    for pattern in helperPatterns {
                        if pattern.parent.lowercased().contains(parentName.lowercased()) {
                            return pattern.parent
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    private func identifyParent(bundleId: String) -> ProcessIdentity {
        // Try to find the actual running parent process
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
            return ProcessIdentity(
                type: .application,
                name: app.localizedName ?? bundleId,
                bundleId: bundleId,
                path: app.executableURL?.path
            )
        }
        
        // Return a placeholder identity
        return ProcessIdentity(
            type: .application,
            name: extractAppName(from: bundleId),
            bundleId: bundleId
        )
    }
    
    private func extractAppName(from bundleId: String) -> String {
        // Extract app name from bundle ID
        // e.g., "com.google.Chrome" -> "Chrome"
        let components = bundleId.split(separator: ".")
        if let lastComponent = components.last {
            return String(lastComponent)
        }
        return bundleId
    }
    
    // MARK: - Cache Management
    
    private func getCachedParent(for processId: String) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return parentCache[processId]
    }
    
    private func cacheParent(_ parentId: String, for processId: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        parentCache[processId] = parentId
        
        // Limit cache size
        if parentCache.count > 200 {
            // Remove oldest entries (simple strategy)
            let toRemove = parentCache.count - 150
            for _ in 0..<toRemove {
                if let firstKey = parentCache.keys.first {
                    parentCache.removeValue(forKey: firstKey)
                }
            }
        }
    }
}

// MARK: - Supporting Types

/// Represents a group of related processes
public struct ProcessGroup {
    public let parent: ProcessIdentity
    public var helpers: [ProcessIdentity]
    
    /// Total bandwidth used by all processes in the group
    public var totalBandwidth: Int64 {
        // This would be calculated from traffic observations
        // Placeholder for now
        return 0
    }
    
    /// Display name for the group
    public var displayName: String {
        parent.displayName
    }
}