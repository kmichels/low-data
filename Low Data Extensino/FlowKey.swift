//
//  FlowKey.swift
//  Low Data Extension
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
import NetworkExtension

/// Key for identifying unique network flows
public struct FlowKey: Hashable, Codable {
    public let remoteHost: String
    public let remotePort: String
    public let localPort: String
    public let direction: Int // Changed from NETrafficDirection for Codable
    
    public init(remoteHost: String, remotePort: String, localPort: String, direction: NETrafficDirection) {
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.localPort = localPort
        self.direction = direction.rawValue
    }
}

/// Information about a network flow
public struct FlowInfo {
    public let key: FlowKey
    public let url: URL?
    public let hostname: String
    public let port: Int
    
    public init(key: FlowKey, url: URL?, hostname: String, port: Int) {
        self.key = key
        self.url = url
        self.hostname = hostname
        self.port = port
    }
}