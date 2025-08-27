//
//  TrustEvaluationUseCase.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation

/// Use case for evaluating if the current network is trusted
public actor TrustEvaluationUseCase: NoInputUseCase {
    
    // MARK: - Dependencies
    
    private let networkMonitor: NetworkMonitor
    private let trustedNetworkRepository: TrustedNetworkRepository
    
    // MARK: - Initialization
    
    public init(networkMonitor: NetworkMonitor, 
                trustedNetworkRepository: TrustedNetworkRepository) {
        self.networkMonitor = networkMonitor
        self.trustedNetworkRepository = trustedNetworkRepository
    }
    
    // MARK: - Execution
    
    public func execute() async throws -> TrustEvaluationResult {
        // Get current network
        guard let currentNetwork = await networkMonitor.currentNetwork else {
            return TrustEvaluationResult(
                isTrusted: false,
                reason: .noNetwork,
                matchedNetwork: nil
            )
        }
        
        // Check if it matches any trusted network
        let trustedNetwork = try await trustedNetworkRepository.findMatch(for: currentNetwork)
        
        if let trusted = trustedNetwork {
            return TrustEvaluationResult(
                isTrusted: trusted.isEnabled,
                reason: trusted.isEnabled ? .matchedTrustedNetwork : .trustedButDisabled,
                matchedNetwork: trusted
            )
        }
        
        // Check for specific untrusted scenarios
        if currentNetwork.isPublicWiFi {
            return TrustEvaluationResult(
                isTrusted: false,
                reason: .publicWiFi,
                matchedNetwork: nil
            )
        }
        
        if currentNetwork.isCellular {
            return TrustEvaluationResult(
                isTrusted: false,
                reason: .cellular,
                matchedNetwork: nil
            )
        }
        
        return TrustEvaluationResult(
            isTrusted: false,
            reason: .unknownNetwork,
            matchedNetwork: nil
        )
    }
}

/// Result of trust evaluation
public struct TrustEvaluationResult {
    public let isTrusted: Bool
    public let reason: TrustReason
    public let matchedNetwork: TrustedNetwork?
    public let evaluatedAt: Date
    
    public init(isTrusted: Bool, 
                reason: TrustReason, 
                matchedNetwork: TrustedNetwork?) {
        self.isTrusted = isTrusted
        self.reason = reason
        self.matchedNetwork = matchedNetwork
        self.evaluatedAt = Date()
    }
}

/// Reason for trust decision
public enum TrustReason {
    case matchedTrustedNetwork
    case trustedButDisabled
    case publicWiFi
    case cellular
    case unknownNetwork
    case noNetwork
    
    public var description: String {
        switch self {
        case .matchedTrustedNetwork:
            return "Connected to trusted network"
        case .trustedButDisabled:
            return "Connected to trusted network (currently disabled)"
        case .publicWiFi:
            return "Connected to public WiFi"
        case .cellular:
            return "Using cellular connection"
        case .unknownNetwork:
            return "Connected to unknown network"
        case .noNetwork:
            return "No network connection"
        }
    }
}

/// Use case for adding a new trusted network
public actor AddTrustedNetworkUseCase: UseCase {
    
    // MARK: - Dependencies
    
    private let networkMonitor: NetworkMonitor
    private let trustedNetworkRepository: TrustedNetworkRepository
    
    // MARK: - Initialization
    
    public init(networkMonitor: NetworkMonitor,
                trustedNetworkRepository: TrustedNetworkRepository) {
        self.networkMonitor = networkMonitor
        self.trustedNetworkRepository = trustedNetworkRepository
    }
    
    // MARK: - Input/Output
    
    public struct Input {
        public let name: String
        public let trustCurrentNetwork: Bool
        public let customIdentifiers: [NetworkIdentifier]?
        public let trustLevel: NetworkTrustLevel
        public let customRules: [ProcessRule]?
        
        public init(name: String,
                   trustCurrentNetwork: Bool = true,
                   customIdentifiers: [NetworkIdentifier]? = nil,
                   trustLevel: NetworkTrustLevel = .trusted,
                   customRules: [ProcessRule]? = nil) {
            self.name = name
            self.trustCurrentNetwork = trustCurrentNetwork
            self.customIdentifiers = customIdentifiers
            self.trustLevel = trustLevel
            self.customRules = customRules
        }
    }
    
    // MARK: - Execution
    
    public func execute(_ input: Input) async throws -> TrustedNetwork {
        // Validate input
        guard !input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UseCaseError.invalidInput("Network name cannot be empty")
        }
        
        // Get identifiers
        var identifiers: [NetworkIdentifier] = []
        
        if let customIdentifiers = input.customIdentifiers {
            identifiers = customIdentifiers
        } else if input.trustCurrentNetwork {
            guard let currentNetwork = await networkMonitor.currentNetwork else {
                throw UseCaseError.networkUnavailable
            }
            
            // Build identifiers from current network
            if let ssid = currentNetwork.ssid {
                identifiers.append(.ssid(ssid))
            }
            if let subnet = currentNetwork.subnet {
                identifiers.append(.subnet(try! CIDR(subnet)))
            }
            if !currentNetwork.gatewayAddresses.isEmpty {
                identifiers.append(.gateway(IPAddress(currentNetwork.gatewayAddresses.first!)))
            }
        }
        
        guard !identifiers.isEmpty else {
            throw UseCaseError.invalidInput("No network identifiers available")
        }
        
        // Create network
        let network = TrustedNetwork(
            name: input.name,
            identifiers: identifiers,
            trustLevel: input.trustLevel,
            customRules: input.customRules ?? []
        )
        
        // Save to repository
        try await trustedNetworkRepository.save(network)
        
        return network
    }
}

/// Use case for monitoring trust state changes
public actor MonitorTrustStateUseCase {
    
    // MARK: - Dependencies
    
    private let trustEvaluationUseCase: TrustEvaluationUseCase
    private let networkMonitor: NetworkMonitor
    
    // MARK: - Initialization
    
    public init(trustEvaluationUseCase: TrustEvaluationUseCase,
                networkMonitor: NetworkMonitor) {
        self.trustEvaluationUseCase = trustEvaluationUseCase
        self.networkMonitor = networkMonitor
    }
    
    // MARK: - Input
    
    public struct Input {
        public let evaluationInterval: TimeInterval
        
        public init(evaluationInterval: TimeInterval = 5.0) {
            self.evaluationInterval = evaluationInterval
        }
    }
    
    // MARK: - Observation
    
    public func observe(_ input: Input) -> AsyncThrowingStream<TrustEvaluationResult, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Initial evaluation
                    let initialResult = try await trustEvaluationUseCase.execute()
                    continuation.yield(initialResult)
                    
                    // Monitor for changes
                    while !Task.isCancelled {
                        try await Task.sleep(nanoseconds: UInt64(input.evaluationInterval * 1_000_000_000))
                        
                        let result = try await trustEvaluationUseCase.execute()
                        continuation.yield(result)
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}