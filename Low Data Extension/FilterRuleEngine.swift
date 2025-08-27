//
//  FilterRuleEngine.swift
//  Low Data Extension
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
import OSLog

/// Engine for evaluating filtering rules
@MainActor
final class FilterRuleEngine {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.lowdata.extension", category: "FilterRuleEngine")
    
    // State
    private(set) var isEnabled: Bool = true
    private(set) var currentNetworkTrusted: Bool = false
    private var currentNetwork: DetectedNetwork?
    
    // Rules and configuration
    private var trustedNetworks: [TrustedNetwork] = []
    private var processRules: [ProcessRule] = []
    private var defaultRules: [ProcessRule] = []
    
    // Statistics
    private var decisionCount: Int = 0
    private var blockCount: Int = 0
    
    // MARK: - Public Methods
    
    func evaluate(process: ProcessIdentity, flow: FlowInfo, isCurrentNetworkTrusted: Bool) -> FilterDecision {
        decisionCount += 1
        
        // Fast path: If on trusted network and not restricted, allow everything
        if isCurrentNetworkTrusted && !isRestrictedNetwork() {
            return .allow(reason: "Trusted network")
        }
        
        // Check process-specific rules first
        if let rule = findRule(for: process) {
            return applyRule(rule, process: process, flow: flow)
        }
        
        // Check if it's a known bandwidth-heavy process
        if !isCurrentNetworkTrusted && isBandwidthHeavyProcess(process) {
            blockCount += 1
            return .block(reason: "Bandwidth-heavy app on untrusted network")
        }
        
        // Default behavior
        if isCurrentNetworkTrusted {
            return .allow(reason: "Trusted network - default allow")
        } else {
            // On untrusted networks, be more restrictive
            if isBackgroundProcess(process) {
                blockCount += 1
                return .block(reason: "Background process on untrusted network")
            }
            return .allow(reason: "User-initiated traffic")
        }
    }
    
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        logger.info("Filtering \(enabled ? "enabled" : "disabled")")
    }
    
    func updateCurrentNetwork(_ network: DetectedNetwork) async {
        currentNetwork = network
        currentNetworkTrusted = evaluateNetworkTrust(network)
        
        logger.info("Network updated: \(network.displayName) - trusted: \(currentNetworkTrusted)")
    }
    
    func updateTrustedNetworks(_ networks: [TrustedNetwork]) {
        trustedNetworks = networks
        
        // Re-evaluate current network trust
        if let network = currentNetwork {
            currentNetworkTrusted = evaluateNetworkTrust(network)
        }
        
        logger.info("Updated \(networks.count) trusted networks")
    }
    
    func updateProcessRules(_ rules: [ProcessRule]) {
        processRules = rules.sorted { $0.priority > $1.priority }
        logger.info("Updated \(rules.count) process rules")
    }
    
    func loadDefaultRules() async {
        // Default rules for common bandwidth-heavy applications
        defaultRules = [
            // Cloud storage
            ProcessRule(
                processIdentifier: "com.dropbox.Dropbox",
                action: .block,
                priority: 100,
                description: "Block Dropbox sync on untrusted networks"
            ),
            ProcessRule(
                processIdentifier: "com.google.GoogleDrive",
                action: .block,
                priority: 100,
                description: "Block Google Drive sync"
            ),
            ProcessRule(
                processIdentifier: "com.microsoft.OneDrive",
                action: .block,
                priority: 100,
                description: "Block OneDrive sync"
            ),
            
            // Backup software
            ProcessRule(
                processIdentifier: "com.backblaze.Backblaze",
                action: .block,
                priority: 90,
                description: "Block Backblaze backup"
            ),
            ProcessRule(
                processIdentifier: "com.crashplan.CrashPlan",
                action: .block,
                priority: 90,
                description: "Block CrashPlan backup"
            ),
            
            // Media/streaming
            ProcessRule(
                processIdentifier: "com.spotify.client",
                action: .allow,
                priority: 50,
                description: "Allow Spotify but monitor"
            ),
            
            // Development tools
            ProcessRule(
                processIdentifier: "docker",
                action: .block,
                priority: 80,
                description: "Block Docker image pulls"
            ),
            
            // Package managers
            ProcessRule(
                processIdentifier: "brew",
                action: .block,
                priority: 70,
                description: "Block Homebrew downloads"
            ),
            ProcessRule(
                processIdentifier: "npm",
                action: .block,
                priority: 70,
                description: "Block npm package downloads"
            )
        ]
        
        logger.info("Loaded \(defaultRules.count) default rules")
    }
    
    func evaluateNetworkTrust(_ network: DetectedNetwork) -> Bool {
        // Check if network matches any trusted network
        for trustedNetwork in trustedNetworks where trustedNetwork.isEnabled {
            if trustedNetwork.matches(network) {
                logger.info("Network matched trusted: \(trustedNetwork.name)")
                return true
            }
        }
        
        // Check for public WiFi
        if network.isPublicWiFi {
            logger.info("Network identified as public WiFi")
            return false
        }
        
        // Cellular is never trusted (expensive)
        if network.isCellular {
            logger.info("Network is cellular - not trusted")
            return false
        }
        
        return false
    }
    
    // MARK: - Private Methods
    
    private func findRule(for process: ProcessIdentity) -> ProcessRule? {
        // Check user-defined rules first
        for rule in processRules {
            if matchesRule(process: process, rule: rule) {
                return rule
            }
        }
        
        // Check default rules
        for rule in defaultRules {
            if matchesRule(process: process, rule: rule) {
                return rule
            }
        }
        
        return nil
    }
    
    private func matchesRule(process: ProcessIdentity, rule: ProcessRule) -> Bool {
        // Match by bundle ID
        if let bundleId = process.bundleId,
           bundleId == rule.processIdentifier {
            return true
        }
        
        // Match by process name
        if process.name.lowercased() == rule.processIdentifier.lowercased() {
            return true
        }
        
        // Match if rule identifier is contained in process name
        if process.name.lowercased().contains(rule.processIdentifier.lowercased()) {
            return true
        }
        
        return false
    }
    
    private func applyRule(_ rule: ProcessRule, process: ProcessIdentity, flow: FlowInfo) -> FilterDecision {
        switch rule.action {
        case .allow:
            return .allow(reason: rule.description ?? "Rule: Allow")
        case .block:
            blockCount += 1
            return .block(reason: rule.description ?? "Rule: Block")
        case .inspect:
            return .inspect(reason: rule.description ?? "Rule: Inspect")
        }
    }
    
    private func isBandwidthHeavyProcess(_ process: ProcessIdentity) -> Bool {
        let knownHeavyProcesses = [
            "dropbox", "googledrive", "onedrive", "icloud",
            "backblaze", "crashplan", "carbonite",
            "steam", "origin", "epic games",
            "qbittorrent", "transmission", "utorrent",
            "docker", "vagrant"
        ]
        
        let processName = process.name.lowercased()
        return knownHeavyProcesses.contains { processName.contains($0) }
    }
    
    private func isBackgroundProcess(_ process: ProcessIdentity) -> Bool {
        // Check if it's a daemon or helper process
        if process.type == .daemon || process.type == .helper {
            return true
        }
        
        // Check for common background process patterns
        let backgroundPatterns = [
            "helper", "daemon", "agent", "service",
            "updater", "installer", "syncer"
        ]
        
        let processName = process.name.lowercased()
        return backgroundPatterns.contains { processName.contains($0) }
    }
    
    private func isRestrictedNetwork() -> Bool {
        // Check if current network has restricted trust level
        guard let network = currentNetwork else { return false }
        
        for trustedNetwork in trustedNetworks where trustedNetwork.isEnabled {
            if trustedNetwork.matches(network) {
                return trustedNetwork.trustLevel == .restricted
            }
        }
        
        return false
    }
    
    // MARK: - Statistics
    
    func getStatistics() -> RuleEngineStatistics {
        return RuleEngineStatistics(
            totalDecisions: decisionCount,
            blockedCount: blockCount,
            allowedCount: decisionCount - blockCount,
            currentNetworkTrusted: currentNetworkTrusted,
            activeRulesCount: processRules.count + defaultRules.count
        )
    }
}

// MARK: - Supporting Types

struct RuleEngineStatistics {
    let totalDecisions: Int
    let blockedCount: Int
    let allowedCount: Int
    let currentNetworkTrusted: Bool
    let activeRulesCount: Int
}