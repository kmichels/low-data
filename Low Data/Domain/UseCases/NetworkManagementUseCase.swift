//
//  NetworkManagementUseCase.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation

/// Use case for managing trusted networks
public actor ManageTrustedNetworksUseCase: NoInputUseCase {
    
    // MARK: - Dependencies
    
    private let trustedNetworkRepository: TrustedNetworkRepository
    private let networkMonitor: NetworkMonitor
    
    // MARK: - Initialization
    
    public init(trustedNetworkRepository: TrustedNetworkRepository,
                networkMonitor: NetworkMonitor) {
        self.trustedNetworkRepository = trustedNetworkRepository
        self.networkMonitor = networkMonitor
    }
    
    // MARK: - Output
    
    public struct Output {
        public let trustedNetworks: [TrustedNetwork]
        public let currentNetwork: DetectedNetwork?
        public let currentNetworkTrusted: Bool
        public let suggestedNetworks: [SuggestedNetwork]
        
        public struct SuggestedNetwork {
            public let network: DetectedNetwork
            public let reason: String
            public let lastSeen: Date
        }
    }
    
    // MARK: - Execution
    
    public func execute() async throws -> Output {
        // Get all trusted networks
        let trustedNetworks = try await trustedNetworkRepository.fetchAll()
        
        // Get current network
        let currentNetwork = await networkMonitor.currentNetwork
        
        // Check if current network is trusted
        let currentTrusted: Bool = {
            guard let current = currentNetwork else { return false }
            return trustedNetworks.contains { $0.matches(current) && $0.isEnabled }
        }()
        
        // Generate suggestions (in real app, this would analyze history)
        var suggestions: [Output.SuggestedNetwork] = []
        
        // Suggest current network if not trusted and it's a private network
        if let current = currentNetwork, 
           !currentTrusted,
           !current.isPublicWiFi,
           !current.isCellular {
            suggestions.append(Output.SuggestedNetwork(
                network: current,
                reason: "Currently connected private network",
                lastSeen: Date()
            ))
        }
        
        return Output(
            trustedNetworks: trustedNetworks,
            currentNetwork: currentNetwork,
            currentNetworkTrusted: currentTrusted,
            suggestedNetworks: suggestions
        )
    }
}

/// Use case for updating trusted network settings
public actor UpdateTrustedNetworkUseCase: UseCase {
    
    // MARK: - Dependencies
    
    private let trustedNetworkRepository: TrustedNetworkRepository
    
    // MARK: - Initialization
    
    public init(trustedNetworkRepository: TrustedNetworkRepository) {
        self.trustedNetworkRepository = trustedNetworkRepository
    }
    
    // MARK: - Input
    
    public struct Input {
        public let networkId: UUID
        public let updates: Updates
        
        public struct Updates {
            public let name: String?
            public let isEnabled: Bool?
            public let trustLevel: NetworkTrustLevel?
            public let identifiers: [NetworkIdentifier]?
            public let customRules: [ProcessRule]?
            
            public init(name: String? = nil,
                       isEnabled: Bool? = nil,
                       trustLevel: NetworkTrustLevel? = nil,
                       identifiers: [NetworkIdentifier]? = nil,
                       customRules: [ProcessRule]? = nil) {
                self.name = name
                self.isEnabled = isEnabled
                self.trustLevel = trustLevel
                self.identifiers = identifiers
                self.customRules = customRules
            }
        }
        
        public init(networkId: UUID, updates: Updates) {
            self.networkId = networkId
            self.updates = updates
        }
    }
    
    // MARK: - Execution
    
    public func execute(_ input: Input) async throws -> TrustedNetwork {
        // Fetch existing network
        guard var network = try await trustedNetworkRepository.fetch(by: input.networkId) else {
            throw TrustedNetworkError.networkNotFound(input.networkId)
        }
        
        // Apply updates
        if let name = input.updates.name {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw UseCaseError.invalidInput("Network name cannot be empty")
            }
            network.name = name
        }
        
        if let isEnabled = input.updates.isEnabled {
            network.isEnabled = isEnabled
        }
        
        if let trustLevel = input.updates.trustLevel {
            network.trustLevel = trustLevel
        }
        
        if let identifiers = input.updates.identifiers {
            guard !identifiers.isEmpty else {
                throw UseCaseError.invalidInput("Network must have at least one identifier")
            }
            network.identifiers = identifiers
        }
        
        if let customRules = input.updates.customRules {
            network.customRules = customRules
        }
        
        // Save updated network
        try await trustedNetworkRepository.save(network)
        
        return network
    }
}

/// Use case for deleting trusted networks
public actor DeleteTrustedNetworkUseCase: UseCase {
    
    // MARK: - Dependencies
    
    private let trustedNetworkRepository: TrustedNetworkRepository
    
    // MARK: - Initialization
    
    public init(trustedNetworkRepository: TrustedNetworkRepository) {
        self.trustedNetworkRepository = trustedNetworkRepository
    }
    
    // MARK: - Input
    
    public typealias Input = UUID  // Network ID
    
    // MARK: - Output
    
    public struct Output {
        public let deletedNetwork: TrustedNetwork
        public let remainingNetworkCount: Int
    }
    
    // MARK: - Execution
    
    public func execute(_ networkId: UUID) async throws -> Output {
        // Fetch network to return in output
        guard let network = try await trustedNetworkRepository.fetch(by: networkId) else {
            throw TrustedNetworkError.networkNotFound(networkId)
        }
        
        // Delete the network
        try await trustedNetworkRepository.delete(network)
        
        // Get remaining count
        let remaining = try await trustedNetworkRepository.fetchAll()
        
        return Output(
            deletedNetwork: network,
            remainingNetworkCount: remaining.count
        )
    }
}

/// Use case for detecting network changes
public actor DetectNetworkChangesUseCase {
    
    // MARK: - Dependencies
    
    private let networkMonitor: NetworkMonitor
    private let trustedNetworkRepository: TrustedNetworkRepository
    
    // MARK: - Initialization
    
    public init(networkMonitor: NetworkMonitor,
                trustedNetworkRepository: TrustedNetworkRepository) {
        self.networkMonitor = networkMonitor
        self.trustedNetworkRepository = trustedNetworkRepository
    }
    
    // MARK: - Input
    
    public struct Input {
        public let checkInterval: TimeInterval
        public let notifyOnTrustChange: Bool
        
        public init(checkInterval: TimeInterval = 2.0,
                   notifyOnTrustChange: Bool = true) {
            self.checkInterval = checkInterval
            self.notifyOnTrustChange = notifyOnTrustChange
        }
    }
    
    // MARK: - Output
    
    public enum Output {
        case networkChanged(NetworkChangeEvent)
        case trustStateChanged(TrustChangeEvent)
        case connectionLost
        case connectionRestored(DetectedNetwork)
        
        public struct NetworkChangeEvent {
            public let previousNetwork: DetectedNetwork?
            public let currentNetwork: DetectedNetwork
            public let timestamp: Date
        }
        
        public struct TrustChangeEvent {
            public let network: DetectedNetwork
            public let wasTrusted: Bool
            public let isTrusted: Bool
            public let timestamp: Date
        }
    }
    
    // MARK: - Observation
    
    public func observe(_ input: Input) -> AsyncThrowingStream<Output, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var lastNetwork: DetectedNetwork?
                var lastTrustedState: Bool?
                
                while !Task.isCancelled {
                    do {
                        let currentNetwork = await networkMonitor.currentNetwork
                        
                        // Check for connection changes
                        if lastNetwork == nil && currentNetwork != nil {
                            continuation.yield(.connectionRestored(currentNetwork!))
                        } else if lastNetwork != nil && currentNetwork == nil {
                            continuation.yield(.connectionLost)
                        } else if let last = lastNetwork, 
                                  let current = currentNetwork,
                                  last.id != current.id {
                            // Network changed
                            continuation.yield(.networkChanged(Output.NetworkChangeEvent(
                                previousNetwork: last,
                                currentNetwork: current,
                                timestamp: Date()
                            )))
                            
                            // Check trust state if requested
                            if input.notifyOnTrustChange {
                                let isTrusted = try await trustedNetworkRepository.isTrusted(current)
                                if let wasT = lastTrustedState, wasT != isTrusted {
                                    continuation.yield(.trustStateChanged(Output.TrustChangeEvent(
                                        network: current,
                                        wasTrusted: wasT,
                                        isTrusted: isTrusted,
                                        timestamp: Date()
                                    )))
                                }
                                lastTrustedState = isTrusted
                            }
                        }
                        
                        lastNetwork = currentNetwork
                        
                        try await Task.sleep(nanoseconds: UInt64(input.checkInterval * 1_000_000_000))
                    } catch {
                        continuation.finish(throwing: error)
                        break
                    }
                }
                
                continuation.finish()
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

/// Use case for exporting/importing network configurations
public actor ExportNetworkConfigurationUseCase: NoInputUseCase {
    
    // MARK: - Dependencies
    
    private let trustedNetworkRepository: TrustedNetworkRepository
    
    // MARK: - Initialization
    
    public init(trustedNetworkRepository: TrustedNetworkRepository) {
        self.trustedNetworkRepository = trustedNetworkRepository
    }
    
    // MARK: - Output
    
    public struct Output {
        public let configuration: NetworkConfiguration
        public let exportDate: Date
        
        public struct NetworkConfiguration: Codable {
            public let version: String
            public let trustedNetworks: [TrustedNetwork]
            public let exportedAt: Date
            
            public init(trustedNetworks: [TrustedNetwork]) {
                self.version = "1.0"
                self.trustedNetworks = trustedNetworks
                self.exportedAt = Date()
            }
        }
    }
    
    // MARK: - Execution
    
    public func execute() async throws -> Output {
        let networks = try await trustedNetworkRepository.fetchAll()
        
        return Output(
            configuration: Output.NetworkConfiguration(trustedNetworks: networks),
            exportDate: Date()
        )
    }
}

/// Use case for importing network configurations
public actor ImportNetworkConfigurationUseCase: UseCase {
    
    // MARK: - Dependencies
    
    private let trustedNetworkRepository: TrustedNetworkRepository
    
    // MARK: - Initialization
    
    public init(trustedNetworkRepository: TrustedNetworkRepository) {
        self.trustedNetworkRepository = trustedNetworkRepository
    }
    
    // MARK: - Input
    
    public struct Input {
        public let configurationData: Data
        public let mergeWithExisting: Bool
        
        public init(configurationData: Data, mergeWithExisting: Bool = true) {
            self.configurationData = configurationData
            self.mergeWithExisting = mergeWithExisting
        }
    }
    
    // MARK: - Output
    
    public struct Output {
        public let importedNetworks: [TrustedNetwork]
        public let skippedNetworks: [TrustedNetwork]
        public let totalNetworks: Int
    }
    
    // MARK: - Execution
    
    public func execute(_ input: Input) async throws -> Output {
        // Decode configuration
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let configuration = try? decoder.decode(
            ExportNetworkConfigurationUseCase.Output.NetworkConfiguration.self,
            from: input.configurationData
        ) else {
            throw UseCaseError.invalidInput("Invalid configuration data")
        }
        
        var importedNetworks: [TrustedNetwork] = []
        var skippedNetworks: [TrustedNetwork] = []
        
        if !input.mergeWithExisting {
            // Delete all existing networks first
            let existing = try await trustedNetworkRepository.fetchAll()
            for network in existing {
                try await trustedNetworkRepository.delete(network)
            }
        }
        
        // Get existing networks for comparison
        let existingNetworks = input.mergeWithExisting ? 
            try await trustedNetworkRepository.fetchAll() : []
        
        // Import each network
        for network in configuration.trustedNetworks {
            // Check if already exists (by identifiers)
            let alreadyExists = existingNetworks.contains { existing in
                existing.identifiers.contains { identifier in
                    network.identifiers.contains(identifier)
                }
            }
            
            if alreadyExists && input.mergeWithExisting {
                skippedNetworks.append(network)
            } else {
                // Create new network with new ID to avoid conflicts
                let newNetwork = TrustedNetwork(
                    name: network.name,
                    identifiers: network.identifiers,
                    trustLevel: network.trustLevel,
                    customRules: network.customRules
                )
                try await trustedNetworkRepository.save(newNetwork)
                importedNetworks.append(newNetwork)
            }
        }
        
        let totalNetworks = try await trustedNetworkRepository.fetchAll().count
        
        return Output(
            importedNetworks: importedNetworks,
            skippedNetworks: skippedNetworks,
            totalNetworks: totalNetworks
        )
    }
}