//
//  FilterDataProvider.swift
//  Low Data Extension
//
//  Created by Konrad Michels on 8/27/25.
//

import NetworkExtension
import OSLog

/// Main Network Extension filter provider
class FilterDataProvider: NEFilterDataProvider {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.lowdata.extension", category: "FilterDataProvider")
    
    // Core components
    private let ruleEngine: FilterRuleEngine
    private let trafficObserver: TrafficObserver
    private let networkMonitor: NetworkMonitor
    private let processIdentifier: ProcessIdentifier
    private let processGrouper: ProcessGrouper
    
    // XPC listener for communication with main app
    private var xpcListener: FilterControlXPCListener?
    
    // Performance-critical caches
    private let connectionCache = LRUCache<FlowKey, FilterDecision>(capacity: 1000)
    private let processCache = LRUCache<pid_t, ProcessIdentity>(capacity: 200)
    
    // MARK: - Initialization
    
    override init() {
        // Initialize core components
        self.networkMonitor = NetworkMonitor()
        self.processIdentifier = ProcessIdentifier()
        self.processGrouper = ProcessGrouper()
        self.ruleEngine = FilterRuleEngine()
        self.trafficObserver = TrafficObserver()
        
        super.init()
        
        logger.info("FilterDataProvider initialized")
    }
    
    // MARK: - NEFilterDataProvider Overrides
    
    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        logger.info("Starting filter...")
        
        Task {
            do {
                // Start network monitoring
                await networkMonitor.start()
                
                // Initialize rule engine with current network
                if let network = networkMonitor.currentNetwork {
                    await ruleEngine.updateCurrentNetwork(network)
                }
                
                // Start XPC listener
                startXPCListener()
                
                // Load saved configuration
                await loadConfiguration()
                
                logger.info("Filter started successfully")
                completionHandler(nil)
                
            } catch {
                logger.error("Failed to start filter: \(error.localizedDescription)")
                completionHandler(error)
            }
        }
    }
    
    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.info("Stopping filter with reason: \(reason.rawValue)")
        
        // Stop XPC listener
        xpcListener?.stopListener()
        xpcListener = nil
        
        // Stop network monitoring
        networkMonitor.stop()
        
        // Save statistics
        Task {
            await saveStatistics()
            completionHandler()
        }
    }
    
    // MARK: - Flow Handling (Performance Critical!)
    
    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        // PERFORMANCE: This is called for EVERY new connection
        // Must be extremely fast - target <1ms
        
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            if elapsed > 1.0 {
                logger.warning("Slow flow decision: \(elapsed)ms")
            }
        }
        
        // Fast path: Check if filtering is enabled
        guard ruleEngine.isEnabled else {
            return .allow()
        }
        
        // Fast path: System connections always allowed
        if isSystemConnection(flow) {
            return .allow()
        }
        
        // Extract flow information
        guard let flowInfo = extractFlowInfo(flow) else {
            logger.warning("Failed to extract flow info")
            return .allow()
        }
        
        // Check cache first
        if let cached = connectionCache.get(flowInfo.key) {
            return applyDecision(cached, to: flow)
        }
        
        // Identify process (with caching)
        let process = identifyProcess(from: flow)
        
        // Make filtering decision
        let decision = ruleEngine.evaluate(
            process: process,
            flow: flowInfo,
            isCurrentNetworkTrusted: ruleEngine.currentNetworkTrusted
        )
        
        // Cache the decision
        connectionCache.put(flowInfo.key, decision)
        
        // Record observation
        if decision.shouldRecord {
            recordObservation(process: process, flow: flowInfo, decision: decision)
        }
        
        // Apply the decision
        return applyDecision(decision, to: flow)
    }
    
    override func handleInboundData(from flow: NEFilterFlow, readBytesStartOffset: Int, readBytes: Data) -> NEFilterDataVerdict {
        // Track inbound bytes
        if let flowInfo = extractFlowInfo(flow) {
            trafficObserver.recordBytes(inbound: Int64(readBytes.count), for: flowInfo.key)
        }
        
        return .allow()
    }
    
    override func handleOutboundData(from flow: NEFilterFlow, readBytesStartOffset: Int, readBytes: Data) -> NEFilterDataVerdict {
        // Track outbound bytes
        if let flowInfo = extractFlowInfo(flow) {
            trafficObserver.recordBytes(outbound: Int64(readBytes.count), for: flowInfo.key)
        }
        
        return .allow()
    }
    
    override func handleRemediation(for flow: NEFilterFlow) -> NEFilterRemediationVerdict {
        // Show block page when connection is blocked
        if let url = (flow as? NEFilterSocketFlow)?.url {
            logger.info("Remediation requested for \(url.absoluteString)")
        }
        
        return .drop()
    }
    
    // MARK: - Private Methods
    
    private func isSystemConnection(_ flow: NEFilterFlow) -> Bool {
        // Fast check for system connections that should never be blocked
        guard let socketFlow = flow as? NEFilterSocketFlow else { return false }
        
        // Allow local connections
        if let remoteEndpoint = socketFlow.remoteEndpoint as? NWHostEndpoint {
            if remoteEndpoint.hostname == "localhost" || 
               remoteEndpoint.hostname == "127.0.0.1" ||
               remoteEndpoint.hostname.hasSuffix(".local") {
                return true
            }
        }
        
        // Allow critical Apple services
        if let url = socketFlow.url {
            let host = url.host ?? ""
            if host.hasSuffix(".apple.com") || 
               host.hasSuffix(".icloud.com") ||
               host.hasSuffix(".mzstatic.com") {
                return true
            }
        }
        
        return false
    }
    
    private func extractFlowInfo(_ flow: NEFilterFlow) -> FlowInfo? {
        guard let socketFlow = flow as? NEFilterSocketFlow else {
            return nil
        }
        
        let remoteHost = (socketFlow.remoteEndpoint as? NWHostEndpoint)?.hostname ?? "unknown"
        let remotePort = (socketFlow.remoteEndpoint as? NWHostEndpoint)?.port ?? "0"
        let localPort = (socketFlow.localEndpoint as? NWHostEndpoint)?.port ?? "0"
        
        return FlowInfo(
            key: FlowKey(
                remoteHost: remoteHost,
                remotePort: remotePort,
                localPort: localPort,
                direction: socketFlow.direction
            ),
            url: socketFlow.url,
            hostname: remoteHost,
            port: Int(remotePort) ?? 0
        )
    }
    
    private func identifyProcess(from flow: NEFilterFlow) -> ProcessIdentity {
        // Get audit token for the flow
        guard let socketFlow = flow as? NEFilterSocketFlow,
              let auditToken = socketFlow.sourceAppAuditToken else {
            return ProcessIdentity(type: .unknown, name: "Unknown")
        }
        
        // Extract PID from audit token
        let pid = extractPID(from: auditToken)
        
        // Check process cache first
        if let cached = processCache.get(pid) {
            return cached
        }
        
        // Identify process
        let identity = processIdentifier.identify(pid: pid)
        
        // Cache the result
        processCache.put(pid, identity)
        
        return identity
    }
    
    private func extractPID(from auditToken: Data) -> pid_t {
        // audit_token_t structure has PID at offset 20 (5th uint32)
        guard auditToken.count >= 24 else { return 0 }
        
        return auditToken.withUnsafeBytes { bytes in
            let uint32Pointer = bytes.bindMemory(to: UInt32.self)
            return pid_t(uint32Pointer[5])
        }
    }
    
    private func applyDecision(_ decision: FilterDecision, to flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        switch decision.action {
        case .allow:
            return .allow()
            
        case .block:
            logger.info("Blocked: \(decision.reason)")
            return .drop()
            
        case .inspect:
            // Need to inspect data
            return .filterDataVerdict(withFilterInbound: true, peekInboundBytes: Int.max,
                                     filterOutbound: true, peekOutboundBytes: Int.max)
        }
    }
    
    private func recordObservation(process: ProcessIdentity, flow: FlowInfo, decision: FilterDecision) {
        let observation = TrafficObservation(
            process: process,
            bytesIn: 0,  // Will be updated by handleInboundData
            bytesOut: 0, // Will be updated by handleOutboundData
            isTrustedNetwork: ruleEngine.currentNetworkTrusted
        )
        
        trafficObserver.record(observation)
    }
    
    // MARK: - XPC Communication
    
    private func startXPCListener() {
        xpcListener = FilterControlXPCListener(
            filterProvider: self,
            networkMonitor: networkMonitor,
            trafficObserver: trafficObserver,
            filterRuleEngine: ruleEngine
        )
        xpcListener?.startListener()
    }
    
    // MARK: - Configuration
    
    private func loadConfiguration() async {
        // Load saved configuration from shared container
        logger.info("Loading configuration...")
        
        // TODO: Load from App Groups shared container
        // For now, use defaults
        await ruleEngine.loadDefaultRules()
    }
    
    private func saveStatistics() async {
        // Save statistics to shared container
        logger.info("Saving statistics...")
        
        // TODO: Save to App Groups shared container
        let stats = trafficObserver.getStatistics()
        logger.info("Total blocked: \(stats.totalBlocked) bytes, allowed: \(stats.totalAllowed) bytes")
    }
}

// MARK: - Supporting Types

struct FlowKey: Hashable {
    let remoteHost: String
    let remotePort: String
    let localPort: String
    let direction: NETrafficDirection
}

struct FlowInfo {
    let key: FlowKey
    let url: URL?
    let hostname: String
    let port: Int
}

enum FilterAction {
    case allow
    case block
    case inspect
}

struct FilterDecision {
    let action: FilterAction
    let reason: String
    let shouldRecord: Bool
    
    static func allow(reason: String = "Allowed") -> FilterDecision {
        FilterDecision(action: .allow, reason: reason, shouldRecord: false)
    }
    
    static func block(reason: String) -> FilterDecision {
        FilterDecision(action: .block, reason: reason, shouldRecord: true)
    }
    
    static func inspect(reason: String = "Inspecting") -> FilterDecision {
        FilterDecision(action: .inspect, reason: reason, shouldRecord: true)
    }
}

// MARK: - LRU Cache (Performance Critical)

final class LRUCache<Key: Hashable, Value> {
    private struct CacheEntry {
        let value: Value
        var accessCount: Int = 0
    }
    
    private var cache: [Key: CacheEntry] = [:]
    private let capacity: Int
    private let lock = NSLock()
    
    init(capacity: Int) {
        self.capacity = capacity
    }
    
    func get(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        
        if var entry = cache[key] {
            entry.accessCount += 1
            cache[key] = entry
            return entry.value
        }
        return nil
    }
    
    func put(_ key: Key, _ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        
        // Remove least recently used if at capacity
        if cache.count >= capacity && cache[key] == nil {
            if let lruKey = cache.min(by: { $0.value.accessCount < $1.value.accessCount })?.key {
                cache.removeValue(forKey: lruKey)
            }
        }
        
        cache[key] = CacheEntry(value: value)
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
}