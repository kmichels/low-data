//
//  NetworkMonitor.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
import Network
import CoreWLAN
import OSLog
import Combine

/// Monitors network changes and characteristics using NWPathMonitor
@MainActor
public class NetworkMonitor: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var currentNetwork: DetectedNetwork?
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var isExpensive: Bool = false
    @Published public private(set) var isConstrained: Bool = false
    @Published public private(set) var connectionType: NWInterface.InterfaceType?
    
    // MARK: - Private Properties
    
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.lowdata.networkmonitor")
    private let wifiClient = CWWiFiClient.shared()
    private let logger = Logger(subsystem: "com.lowdata", category: "NetworkMonitor")
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    public init() {
        startMonitoring()
    }
    
    deinit {
        pathMonitor.cancel()
    }
    
    // MARK: - Public Methods
    
    /// Forces a refresh of network information
    public func refresh() async {
        await updateNetworkInfo(from: pathMonitor.currentPath)
    }
    
    /// Start monitoring (alias for refresh for compatibility)
    public func start() async {
        await refresh()
    }
    
    /// Stop monitoring
    public func stop() {
        // Path monitor is already running, just clear current state
        currentNetwork = nil
    }
    
    /// Force update (alias for refresh)
    public func forceUpdate() async {
        await refresh()
    }
    
    // MARK: - Private Methods
    
    private func startMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                await self?.updateNetworkInfo(from: path)
            }
        }
        
        pathMonitor.start(queue: monitorQueue)
        logger.info("Network monitoring started")
    }
    
    @MainActor
    private func updateNetworkInfo(from path: NWPath) async {
        isConnected = path.status == .satisfied
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
        
        if isConnected {
            var network = DetectedNetwork()
            
            // Get connection type
            if path.usesInterfaceType(.wifi) {
                connectionType = .wifi
                network.interfaceType = .wifi
                await detectWiFiDetails(&network)
            } else if path.usesInterfaceType(.cellular) {
                connectionType = .cellular
                network.interfaceType = .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                connectionType = .wiredEthernet
                network.interfaceType = .ethernet
            } else if path.usesInterfaceType(.loopback) {
                connectionType = .loopback
                network.interfaceType = .other
            } else if path.usesInterfaceType(.other) {
                connectionType = .other
                // Check if it might be VPN based on interface name
                if let interface = path.availableInterfaces.first {
                    if interface.name.hasPrefix("utun") || interface.name.hasPrefix("ipsec") {
                        network.interfaceType = .vpn
                    } else {
                        network.interfaceType = .other
                    }
                }
            } else {
                connectionType = path.availableInterfaces.first?.type
                network.interfaceType = .other
            }
            
            // Get interface details
            if let interface = path.availableInterfaces.first {
                network.interfaceName = interface.name
                
                // Check for Tailscale (utun interfaces)
                if interface.name.hasPrefix("utun") {
                    network.isTailscale = true
                    network.tailscaleNetwork = interface.name
                }
            }
            
            // Get network addresses and routing info
            await detectNetworkAddresses(&network)
            
            // Estimate network quality based on path characteristics
            network.quality = estimateNetworkQuality(from: path)
            
            currentNetwork = network
            logger.info("Network updated: \(network.displayName), Type: \(String(describing: network.interfaceType))")
        } else {
            currentNetwork = nil
            connectionType = nil
            logger.info("Network disconnected")
        }
    }
    
    @MainActor
    private func detectWiFiDetails(_ network: inout DetectedNetwork) async {
        guard let interface = wifiClient.interface() else { return }
        
        network.ssid = interface.ssid()
        network.bssid = interface.bssid()
        network.rssi = interface.rssiValue()
        
        let ssid = network.ssid ?? "none"
        let bssid = network.bssid ?? "none"
        let rssi = network.rssi ?? 0
        logger.debug("WiFi details - SSID: \(ssid), BSSID: \(bssid), RSSI: \(rssi)")
    }
    
    @MainActor
    private func detectNetworkAddresses(_ network: inout DetectedNetwork) async {
        // Get IP addresses
        var ipAddresses: [IPAddress] = []
        
        // Get all network interfaces
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee,
                  let name = interface.ifa_name,
                  let addr = interface.ifa_addr else { continue }
            
            let interfaceName = String(cString: name)
            
            // Skip if not the current interface
            if let currentInterface = network.interfaceName,
               interfaceName != currentInterface { continue }
            
            let family = addr.pointee.sa_family
            
            // Process IPv4
            if family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(MemoryLayout<sockaddr_in>.size),
                              &hostname, socklen_t(hostname.count),
                              nil, 0, NI_NUMERICHOST) == 0 {
                    let address = String(cString: hostname)
                    if !address.hasPrefix("127.") {  // Skip loopback
                        ipAddresses.append(IPAddress(address))
                    }
                }
                
                // Check for gateway (if it's the default route interface)
                if interface.ifa_dstaddr != nil {
                    var gatewayHost = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(interface.ifa_dstaddr, socklen_t(MemoryLayout<sockaddr_in>.size),
                                  &gatewayHost, socklen_t(gatewayHost.count),
                                  nil, 0, NI_NUMERICHOST) == 0 {
                        let gateway = String(cString: gatewayHost)
                        if !gateway.hasPrefix("127.") && !gateway.isEmpty {
                            network.gateway = IPAddress(gateway)
                        }
                    }
                }
            }
            // Process IPv6
            else if family == UInt8(AF_INET6) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(MemoryLayout<sockaddr_in6>.size),
                              &hostname, socklen_t(hostname.count),
                              nil, 0, NI_NUMERICHOST) == 0 {
                    let address = String(cString: hostname)
                    if !address.hasPrefix("::1") && !address.hasPrefix("fe80") {  // Skip loopback and link-local
                        ipAddresses.append(IPAddress(address))
                    }
                }
            }
        }
        
        network.ipAddresses = ipAddresses.isEmpty ? nil : ipAddresses
        
        // Get DNS servers
        network.dnsServers = getDNSServers()
        
        // If we didn't get a gateway from interfaces, try to get it from routing table
        if network.gateway == nil {
            network.gateway = getDefaultGateway()
        }
    }
    
    private func getDNSServers() -> [IPAddress]? {
        // This is a simplified approach - in production you'd parse resolv.conf or use SystemConfiguration
        // For now, return nil - DNS detection needs proper implementation
        return nil
    }
    
    private func getDefaultGateway() -> IPAddress? {
        // Parse routing table to find default gateway
        // This would involve parsing `netstat -rn` output or using system calls
        // For now, attempting a simple heuristic
        
        guard let network = currentNetwork,
              let addresses = network.ipAddresses,
              let firstIPv4 = addresses.first(where: { !$0.isIPv6 }) else {
            return nil
        }
        
        // Common gateway patterns (x.x.x.1 or x.x.x.254)
        let components = firstIPv4.address.split(separator: ".")
        if components.count == 4 {
            let baseIP = components.prefix(3).joined(separator: ".")
            // Try .1 first (most common)
            return IPAddress("\(baseIP).1")
        }
        
        return nil
    }
    
    private func estimateNetworkQuality(from path: NWPath) -> NetworkQuality {
        // Estimate quality based on connection type and characteristics
        if !path.status.isConnected {
            return .unknown
        }
        
        if path.isConstrained {
            return .poor
        }
        
        if path.isExpensive {
            return .fair
        }
        
        // Check WiFi signal strength if available
        if connectionType == .wifi,
           let rssi = currentNetwork?.rssi {
            switch rssi {
            case -30...0:
                return .excellent
            case -60...(-30):
                return .good
            case -70...(-60):
                return .fair
            default:
                return .poor
            }
        }
        
        // Default based on connection type
        switch connectionType {
        case .wiredEthernet:
            return .excellent
        case .wifi:
            return .good
        case .cellular:
            return .fair
        default:
            return .unknown
        }
    }
}

// MARK: - NWPath Extension

private extension NWPath.Status {
    var isConnected: Bool {
        self == .satisfied
    }
}