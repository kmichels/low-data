//
//  NetworkIdentifier.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation

/// Represents different ways to identify a network for trust evaluation
public enum NetworkIdentifier: Codable, Equatable {
    case ssid(String)
    case bssid(String)
    case subnet(CIDR)
    case gateway(IPAddress)
    case interface(String)
    case tailscaleNetwork(String)
    case combination([NetworkIdentifier]) // All must match
    
    /// Determines if this identifier matches the given network state
    public func matches(_ network: DetectedNetwork) -> Bool {
        switch self {
        case .ssid(let name):
            return network.ssid == name
            
        case .bssid(let address):
            return network.bssid?.lowercased() == address.lowercased()
            
        case .subnet(let cidr):
            return network.ipAddresses?.contains { cidr.contains($0) } ?? false
            
        case .gateway(let gwAddress):
            return network.gateway == gwAddress
            
        case .interface(let name):
            return network.interfaceName == name
            
        case .tailscaleNetwork(let identifier):
            return network.isTailscale && network.tailscaleNetwork == identifier
            
        case .combination(let identifiers):
            return identifiers.allSatisfy { $0.matches(network) }
        }
    }
}

// MARK: - Supporting Types

/// Represents an IP address (IPv4 or IPv6)
public struct IPAddress: Codable, Equatable {
    public let address: String
    public let isIPv6: Bool
    
    public init(_ address: String) {
        self.address = address
        self.isIPv6 = address.contains(":")
    }
}

/// Represents a CIDR network range
public struct CIDR: Codable, Equatable {
    public let network: String
    public let prefixLength: Int
    
    public init(_ cidr: String) throws {
        let components = cidr.split(separator: "/")
        guard components.count == 2,
              let prefix = Int(components[1]) else {
            throw NetworkError.invalidCIDR(cidr)
        }
        
        self.network = String(components[0])
        self.prefixLength = prefix
    }
    
    /// Check if an IP address is contained within this CIDR range
    public func contains(_ address: IPAddress) -> Bool {
        // Simplified for MVP - in production would use proper IP math
        // This is a placeholder that checks if the network portion matches
        let networkComponents = network.split(separator: ".")
        let addressComponents = address.address.split(separator: ".")
        
        guard !address.isIPv6,
              networkComponents.count == 4,
              addressComponents.count == 4 else {
            return false
        }
        
        let octetsToCheck = prefixLength / 8
        for i in 0..<octetsToCheck {
            if networkComponents[i] != addressComponents[i] {
                return false
            }
        }
        
        return true
    }
}

/// Represents detected network information
public struct DetectedNetwork: Codable {
    public var interfaceName: String?
    public var interfaceType: NetworkInterfaceType?
    public var ssid: String?
    public var bssid: String?
    public var rssi: Int?
    public var ipAddresses: [IPAddress]?
    public var gateway: IPAddress?
    public var dnsServers: [IPAddress]?
    public var isTailscale: Bool = false
    public var tailscaleNetwork: String?
    public var quality: NetworkQuality = .unknown
    
    public init() {}
    
    public var displayName: String {
        if let ssid = ssid {
            return ssid
        } else if isTailscale {
            return "Tailscale Network"
        } else if interfaceType == .cellular {
            return "Cellular"
        } else if interfaceType == .ethernet {
            return "Ethernet"
        } else if interfaceType == .vpn {
            return "VPN"
        } else if let interfaceName = interfaceName {
            // Use interface name as fallback (e.g., "en0", "lo0")
            return "Network (\(interfaceName))"
        } else {
            return "Unknown Network"
        }
    }
    
    public var id: String {
        // Create a unique ID for network comparison
        if let ssid = ssid, let bssid = bssid {
            return "\(ssid):\(bssid)"
        } else if let ssid = ssid {
            return ssid
        } else if let interfaceName = interfaceName {
            return interfaceName
        } else {
            return "unknown"
        }
    }
    
    public var isPublicWiFi: Bool {
        // Consider WiFi public if no password or common public network names
        guard interfaceType == .wifi else { return false }
        
        if let ssid = ssid {
            let publicNames = ["guest", "public", "free", "open", "starbucks", "airport", "hotel"]
            let lowerSSID = ssid.lowercased()
            return publicNames.contains { lowerSSID.contains($0) } || bssid == nil
        }
        
        return false
    }
    
    public var isCellular: Bool {
        return interfaceType == .cellular
    }
    
    public var isWiFi: Bool {
        return interfaceType == .wifi
    }
    
    public var isExpensive: Bool {
        return interfaceType == .cellular
    }
    
    public var subnet: String? {
        // Derive subnet from IP addresses
        guard let firstIP = ipAddresses?.first else { return nil }
        
        // Simplified: assume /24 for private networks
        let components = firstIP.address.split(separator: ".")
        guard components.count == 4 else { return nil }
        
        return "\(components[0]).\(components[1]).\(components[2]).0/24"
    }
    
    public var gatewayAddresses: [String] {
        if let gateway = gateway {
            return [gateway.address]
        }
        return []
    }
}

public enum NetworkInterfaceType: String, Codable {
    case wifi
    case ethernet
    case cellular
    case vpn
    case other
}

public enum NetworkQuality: String, Codable {
    case excellent
    case good
    case fair
    case poor
    case unknown
}

public enum NetworkError: LocalizedError {
    case invalidCIDR(String)
    case invalidIPAddress(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidCIDR(let cidr):
            return "Invalid CIDR notation: \(cidr)"
        case .invalidIPAddress(let address):
            return "Invalid IP address: \(address)"
        }
    }
}