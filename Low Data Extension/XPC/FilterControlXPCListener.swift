//
//  FilterControlXPCListener.swift
//  Low Data Extension
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
import NetworkExtension
import OSLog

/// XPC listener service for the system extension
public final class FilterControlXPCListener: NSObject {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.lowdata.extension", category: "FilterControlXPCListener")
    private var listener: NSXPCListener?
    private weak var filterProvider: NEFilterDataProvider?
    
    // Network and traffic state (shared with filter provider)
    private let networkMonitor: NetworkMonitor
    private let trafficObserver: TrafficObserver
    private let filterRuleEngine: FilterRuleEngine
    
    // MARK: - Initialization
    
    public init(filterProvider: NEFilterDataProvider? = nil,
                networkMonitor: NetworkMonitor,
                trafficObserver: TrafficObserver,
                filterRuleEngine: FilterRuleEngine) {
        self.filterProvider = filterProvider
        self.networkMonitor = networkMonitor
        self.trafficObserver = trafficObserver
        self.filterRuleEngine = filterRuleEngine
        
        super.init()
    }
    
    // MARK: - Listener Management
    
    public func startListener() {
        guard listener == nil else {
            logger.warning("XPC listener already started")
            return
        }
        
        // Create listener with mach service name
        let newListener = NSXPCListener(machServiceName: XPCServiceNames.systemExtension)
        
        // Set delegate
        newListener.delegate = self
        
        // Resume listening
        newListener.resume()
        
        self.listener = newListener
        
        logger.info("XPC listener started successfully")
    }
    
    public func stopListener() {
        listener?.invalidate()
        listener = nil
        
        logger.info("XPC listener stopped")
    }
}

// MARK: - NSXPCListenerDelegate

extension FilterControlXPCListener: NSXPCListenerDelegate {
    
    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        
        // Validate the connection
        guard validateConnection(newConnection) else {
            logger.warning("Rejected XPC connection - validation failed")
            return false
        }
        
        // Configure the connection
        newConnection.exportedInterface = NSXPCInterface(with: FilterControlXPCProtocol.self)
        newConnection.exportedObject = self
        
        // Set handlers
        newConnection.interruptionHandler = { [weak self] in
            self?.logger.info("XPC connection interrupted")
        }
        
        newConnection.invalidationHandler = { [weak self] in
            self?.logger.info("XPC connection invalidated")
        }
        
        // Resume the connection
        newConnection.resume()
        
        logger.info("Accepted new XPC connection")
        
        return true
    }
    
    private func validateConnection(_ connection: NSXPCConnection) -> Bool {
        // Use the XPCConnectionValidator to validate the connection
        return XPCConnectionValidator.validate(
            connection, 
            allowedBundleIdentifiers: XPCServiceConfiguration.mainAppIdentifiers
        )
    }
}

// MARK: - FilterControlXPCProtocol Implementation

extension FilterControlXPCListener: FilterControlXPCProtocol {
    
    // MARK: - Configuration
    
    public func updateTrustedNetworks(_ networks: Data, reply: @escaping (Bool, Error?) -> Void) {
        do {
            let decoder = JSONDecoder()
            let trustedNetworks = try decoder.decode([TrustedNetwork].self, from: networks)
            
            // Update filter rule engine
            filterRuleEngine.updateTrustedNetworks(trustedNetworks)
            
            logger.info("Updated \(trustedNetworks.count) trusted networks")
            reply(true, nil)
            
        } catch {
            logger.error("Failed to update trusted networks: \(error.localizedDescription)")
            reply(false, error)
        }
    }
    
    public func updateFilterRules(_ rules: Data, reply: @escaping (Bool, Error?) -> Void) {
        do {
            let decoder = JSONDecoder()
            let processRules = try decoder.decode([ProcessRule].self, from: rules)
            
            // Update filter rule engine
            filterRuleEngine.updateProcessRules(processRules)
            
            logger.info("Updated \(processRules.count) filter rules")
            reply(true, nil)
            
        } catch {
            logger.error("Failed to update filter rules: \(error.localizedDescription)")
            reply(false, error)
        }
    }
    
    public func setFilteringEnabled(_ enabled: Bool, reply: @escaping (Bool, Error?) -> Void) {
        filterRuleEngine.setEnabled(enabled)
        
        logger.info("Filtering \(enabled ? "enabled" : "disabled")")
        reply(true, nil)
    }
    
    // MARK: - Status
    
    public func getFilterStatus(reply: @escaping (Data?, Error?) -> Void) {
        do {
            let status = FilterStatus(
                isEnabled: filterRuleEngine.isEnabled,
                currentNetworkTrusted: filterRuleEngine.currentNetworkTrusted,
                blockedConnectionCount: trafficObserver.blockedConnectionCount,
                allowedConnectionCount: trafficObserver.allowedConnectionCount,
                totalBytesBlocked: trafficObserver.totalBytesBlocked,
                totalBytesAllowed: trafficObserver.totalBytesAllowed,
                uptimeSeconds: trafficObserver.uptimeSeconds,
                lastUpdateDate: Date()
            )
            
            let encoder = JSONEncoder()
            let data = try encoder.encode(status)
            
            reply(data, nil)
            
        } catch {
            logger.error("Failed to get filter status: \(error.localizedDescription)")
            reply(nil, error)
        }
    }
    
    public func getCurrentNetwork(reply: @escaping (Data?, Error?) -> Void) {
        do {
            guard let network = networkMonitor.currentNetwork else {
                reply(nil, nil)
                return
            }
            
            let encoder = JSONEncoder()
            let data = try encoder.encode(network)
            
            reply(data, nil)
            
        } catch {
            logger.error("Failed to get current network: \(error.localizedDescription)")
            reply(nil, error)
        }
    }
    
    public func getStatistics(reply: @escaping (Data?, Error?) -> Void) {
        do {
            let stats = trafficObserver.getStatistics()
            
            let encoder = JSONEncoder()
            let data = try encoder.encode(stats)
            
            reply(data, nil)
            
        } catch {
            logger.error("Failed to get statistics: \(error.localizedDescription)")
            reply(nil, error)
        }
    }
    
    // MARK: - Traffic Monitoring
    
    public func getRecentTraffic(limit: Int, reply: @escaping (Data?, Error?) -> Void) {
        do {
            let observations = trafficObserver.getRecentObservations(limit: limit)
            
            let encoder = JSONEncoder()
            let data = try encoder.encode(observations)
            
            reply(data, nil)
            
        } catch {
            logger.error("Failed to get recent traffic: \(error.localizedDescription)")
            reply(nil, error)
        }
    }
    
    public func getTrafficForProcess(_ processId: String, reply: @escaping (Data?, Error?) -> Void) {
        do {
            let observations = trafficObserver.getObservationsForProcess(processId)
            
            let encoder = JSONEncoder()
            let data = try encoder.encode(observations)
            
            reply(data, nil)
            
        } catch {
            logger.error("Failed to get traffic for process: \(error.localizedDescription)")
            reply(nil, error)
        }
    }
    
    // MARK: - Control
    
    public func clearStatistics(reply: @escaping (Bool, Error?) -> Void) {
        trafficObserver.clearStatistics()
        
        logger.info("Statistics cleared")
        reply(true, nil)
    }
    
    public func reevaluateNetwork(reply: @escaping (Bool, Error?) -> Void) {
        Task {
            await networkMonitor.forceUpdate()
            
            // Re-evaluate trust state
            if let network = networkMonitor.currentNetwork {
                let trusted = filterRuleEngine.evaluateNetworkTrust(network)
                filterRuleEngine.currentNetworkTrusted = trusted
                
                logger.info("Re-evaluated network - trusted: \(trusted)")
            }
            
            reply(true, nil)
        }
    }
}

// MARK: - Placeholder Types (These will be implemented in the System Extension)

/// Observes and records traffic
public class TrafficObserver {
    public var blockedConnectionCount: Int = 0
    public var allowedConnectionCount: Int = 0
    public var totalBytesBlocked: Int64 = 0
    public var totalBytesAllowed: Int64 = 0
    public var uptimeSeconds: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
    
    private let startTime = Date()
    private var observations: [TrafficObservation] = []
    
    public func getStatistics() -> FilterTrafficStatistics {
        // Placeholder implementation
        return FilterTrafficStatistics(
            totalBlocked: totalBytesBlocked,
            totalAllowed: totalBytesAllowed,
            topBlockedProcesses: [],
            topAllowedProcesses: [],
            startDate: startTime,
            lastUpdateDate: Date()
        )
    }
    
    public func getRecentObservations(limit: Int) -> [TrafficObservation] {
        Array(observations.suffix(limit))
    }
    
    public func getObservationsForProcess(_ processId: String) -> [TrafficObservation] {
        observations.filter { $0.processIdentifier == processId }
    }
    
    public func clearStatistics() {
        blockedConnectionCount = 0
        allowedConnectionCount = 0
        totalBytesBlocked = 0
        totalBytesAllowed = 0
        observations.removeAll()
    }
}

/// Manages filter rules and evaluates connections
public class FilterRuleEngine {
    public var isEnabled: Bool = false
    public var currentNetworkTrusted: Bool = false
    
    private var trustedNetworks: [TrustedNetwork] = []
    private var processRules: [ProcessRule] = []
    
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }
    
    public func updateTrustedNetworks(_ networks: [TrustedNetwork]) {
        trustedNetworks = networks
    }
    
    public func updateProcessRules(_ rules: [ProcessRule]) {
        processRules = rules
    }
    
    public func evaluateNetworkTrust(_ network: DetectedNetwork) -> Bool {
        // Placeholder - will be implemented properly in System Extension
        for trustedNetwork in trustedNetworks where trustedNetwork.isEnabled {
            if trustedNetwork.matches(network) {
                return true
            }
        }
        return false
    }
}