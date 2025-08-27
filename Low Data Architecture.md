# Low Data Architecture Documents

## Document 1: TPM/Product Overview Version

### Low Data: Product Architecture Overview

#### Vision

An intelligent network traffic management application for macOS that automatically conserves bandwidth on untrusted networks by learning usage patterns and blocking bandwidth-heavy applications.

#### Core Value Proposition

- **For regular users**: "Your Mac automatically saves bandwidth when you're not at home"
- **For power users**: "Granular control over which apps can use network based on location"
- **For digital nomads**: "Stop cloud services from eating hotel WiFi automatically"

#### Key Product Principles

1. **Trust-based simplicity**: Define trusted networks (home/office), everything else is restricted
2. **Zero-configuration functionality**: Works out-of-box with smart defaults
3. **Learning-driven intelligence**: Observes actual usage to make better decisions
4. **Progressive disclosure**: Simple for most, powerful when needed
5. **Privacy-first**: All data stays local, no cloud dependency

#### User Journey

##### First Run (5 minutes)

1. App launches, detects current network
2. "Is this your home/office network?" → One-click to trust
3. Shows current bandwidth users with simple explanations
4. Offers smart defaults based on detected apps
5. Menu bar icon appears, done

##### Daily Use (Zero interaction)

- **At home**: Everything works normally, app invisible
- **At hotel/café**: Heavy apps blocked automatically, saves bandwidth
- **Cellular**: Maximum conservation mode
- **Menu bar**: Shows status, blocked count, quick overrides

##### Power User Features (Progressive)

- Define complex trust rules (subnet ranges, multiple identifiers)
- Create custom profiles beyond trusted/untrusted
- View detailed traffic analytics
- Export/import rule sets
- Automation via Shortcuts/AppleScript

#### Technical Architecture Overview

##### System Components

```
┌─────────────────────────┐
│   Menu Bar Interface    │ ← Quick access/status
└───────────┬─────────────┘
            │
┌───────────▼─────────────┐
│      Main GUI App       │ ← Configuration/Analytics
└───────────┬─────────────┘
            │
┌───────────▼─────────────┐
│   System Extension      │ ← Network filtering
└───────────┬─────────────┘
            │
┌───────────▼─────────────┐
│  Core Data + Learning   │ ← Intelligence layer
└─────────────────────────┘
```

##### Data Flow

1. **Network Monitor** detects connection changes
2. **Trust Evaluator** determines if network is trusted
3. **Traffic Monitor** observes all network flows
4. **Intelligence Engine** identifies processes and patterns
5. **Rule Engine** makes block/allow decisions
6. **Learning System** improves over time

#### MVP Features (Version 1.0)

##### Must Have

- Trusted network identification (SSID + subnet)
- Automatic blocking on untrusted networks
- Process identification (apps, brew services, daemons)
- Default rules for common bandwidth hogs
- Menu bar status and quick controls
- Basic traffic visibility

##### Nice to Have

- Learning mode for first week
- Traffic analytics dashboard
- Temporary override options
- Process grouping (helpers with parent apps)

##### Future (Post-MVP)

- Multiple profile support
- iCloud sync of trusted networks
- Scheduling (time-based rules)
- Bandwidth quotas
- Network quality detection
- API for third-party integration

#### Success Metrics

- **Setup completion**: 90% finish in <5 minutes
- **Daily active use**: Check menu bar at least once
- **Bandwidth saved**: Average 2GB+ per hotel day
- **User intervention**: <1 manual override per day
- **Performance impact**: <1% CPU, <50MB RAM

#### Risk Mitigation

- **Privacy concerns**: All local, no data collection
- **Compatibility**: Test with top 100 Mac apps
- **User confusion**: Progressive disclosure, smart defaults
- **Power user needs**: Advanced mode, export capabilities
- **System updates**: Use stable Apple APIs only

---

## Document 2: Claude Code Technical Implementation Guide

### : Technical Architecture for Implementation

#### Project Configuration

```yaml
# Project Setup Instructions for Claude Code
Project Name: 
Platform: macOS 13.0+
Language: Swift 5.9+
UI Framework: SwiftUI
Architecture: Clean Architecture + MVVM
Testing: XCTest with 80% minimum coverage

Key Principles:
- Dependency injection everywhere
- Protocol-first design
- Async/await for all async operations
- Actor isolation for shared state
- Comprehensive error handling
- DocC documentation for public APIs
```

#### Project Structure

```
/
├── /                 # Main Application
│   ├── App/
│   │   ├── App.swift
│   │   ├── AppDelegate.swift
│   │   └── DependencyContainer.swift
│   ├── Domain/
│   │   ├── Entities/
│   │   │   ├── NetworkProfile.swift
│   │   │   ├── ProcessIdentity.swift
│   │   │   ├── TrafficObservation.swift
│   │   │   └── TrustedNetwork.swift
│   │   ├── UseCases/
│   │   │   ├── NetworkTrustUseCase.swift
│   │   │   ├── ProcessBlockingUseCase.swift
│   │   │   └── TrafficAnalysisUseCase.swift
│   │   └── Repositories/
│   │       ├── NetworkProfileRepository.swift
│   │       ├── TrafficDataRepository.swift
│   │       └── TrustedNetworkRepository.swift
│   ├── Data/
│   │   ├── CoreData/
│   │   │   ├── .xcdatamodeld
│   │   │   ├── CoreDataStack.swift
│   │   │   └── Entities/
│   │   │       ├── CDTrustedNetwork+CoreDataClass.swift
│   │   │       ├── CDTrafficObservation+CoreDataClass.swift
│   │   │       └── CDProcessProfile+CoreDataClass.swift
│   │   ├── Repositories/
│   │   │   ├── CoreDataNetworkProfileRepository.swift
│   │   │   └── CoreDataTrafficRepository.swift
│   │   └── Mappers/
│   │       ├── TrustedNetworkMapper.swift
│   │       └── TrafficObservationMapper.swift
│   ├── Presentation/
│   │   ├── Views/
│   │   │   ├── Main/
│   │   │   │   ├── MainWindow.swift
│   │   │   │   ├── NetworkStatusView.swift
│   │   │   │   └── BlockedAppsListView.swift
│   │   │   ├── Setup/
│   │   │   │   ├── SetupWizard.swift
│   │   │   │   └── TrustNetworkView.swift
│   │   │   └── MenuBar/
│   │   │       └── MenuBarView.swift
│   │   ├── ViewModels/
│   │   │   ├── MainViewModel.swift
│   │   │   ├── NetworkStatusViewModel.swift
│   │   │   └── SetupViewModel.swift
│   │   └── Coordinators/
│   │       └── AppCoordinator.swift
│   └── Infrastructure/
│       ├── Extensions/
│       │   ├── Foundation+Extensions.swift
│       │   └── SwiftUI+Extensions.swift
│       ├── NetworkDetection/
│       │   ├── NetworkMonitor.swift
│       │   ├── NetworkIdentifier.swift
│       │   └── TailscaleDetector.swift
│       └── ProcessDetection/
│           ├── ProcessIdentifier.swift
│           ├── BrewServiceDetector.swift
│           └── ProcessGrouper.swift
├── Extension/        # System Extension
│   ├── Info.plist
│   ├── Extension.entitlements
│   ├── FilterDataProvider.swift
│   ├── FilterRuleEngine.swift
│   ├── ProcessMatcher.swift
│   └── XPC/
│       ├── XPCServer.swift
│       └── XPCProtocol.swift
├── Core/             # Shared Framework
│   ├── Models/
│   │   ├── NetworkIdentity.swift
│   │   ├── ProcessInfo.swift
│   │   └── BlockingDecision.swift
│   ├── Utilities/
│   │   ├── Logger.swift
│   │   ├── IPAddress.swift
│   │   └── CIDR.swift
│   └── Constants.swift
└── Tests/
    ├── Unit/
    │   ├── Domain/
    │   ├── Data/
    │   └── Presentation/
    ├── Integration/
    │   ├── NetworkDetectionTests.swift
    │   ├── ProcessDetectionTests.swift
    │   └── FilteringTests.swift
    └── UI/
        ├── SetupFlowUITests.swift
        └── MainWindowUITests.swift
```

#### Core Implementation Files

##### 1. Domain Layer - TrustedNetwork.swift

```swift
// MARK: - Instructions for Claude Code
// This is the core domain entity. Keep it framework-agnostic.
// Use value types where possible for thread safety.

import Foundation

public struct TrustedNetwork: Identifiable, Equatable, Codable {
    public let id: UUID
    public let name: String
    public let identifiers: [NetworkIdentifier]
    public let dateAdded: Date
    public let isEnabled: Bool
    public let customRules: [ProcessRule]?
    
    public init(
        id: UUID = UUID(),
        name: String,
        identifiers: [NetworkIdentifier],
        dateAdded: Date = Date(),
        isEnabled: Bool = true,
        customRules: [ProcessRule]? = nil
    ) {
        self.id = id
        self.name = name
        self.identifiers = identifiers
        self.dateAdded = dateAdded
        self.isEnabled = isEnabled
        self.customRules = customRules
    }
}

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
        // Implementation here
        switch self {
        case .ssid(let name):
            return network.ssid == name
        case .subnet(let cidr):
            return cidr.contains(network.ipAddress)
        case .combination(let identifiers):
            return identifiers.allSatisfy { $0.matches(network) }
        // ... other cases
        default:
            return false
        }
    }
}
```

##### 2. Traffic Intelligence - TrafficIntelligence.swift

```swift
// MARK: - Instructions for Claude Code
// This actor manages all traffic learning and intelligence.
// Use actor isolation for thread safety.
// Implement sliding window for observations to limit memory.

import Foundation

public actor TrafficIntelligence {
    private let repository: TrafficDataRepository
    private var observations: CircularBuffer<TrafficObservation>
    private var processProfiles: [ProcessIdentity: ProcessProfile]
    private let maxObservations = 10000
    
    public init(repository: TrafficDataRepository) {
        self.repository = repository
        self.observations = CircularBuffer(capacity: maxObservations)
        self.processProfiles = [:]
    }
    
    /// Records a traffic observation for learning
    public func observe(
        process: ProcessIdentity,
        bytesIn: UInt64,
        bytesOut: UInt64,
        network: DetectedNetwork
    ) async {
        let observation = TrafficObservation(
            timestamp: Date(),
            process: process,
            bytesIn: bytesIn,
            bytesOut: bytesOut,
            networkType: network.trustLevel,
            networkQuality: network.quality
        )
        
        observations.append(observation)
        
        // Update process profile
        await updateProcessProfile(for: process, with: observation)
        
        // Persist periodically
        if observations.count % 100 == 0 {
            await persistObservations()
        }
    }
    
    /// Gets intelligent blocking recommendation
    public func recommendAction(
        for process: ProcessIdentity,
        on network: DetectedNetwork
    ) async -> BlockingRecommendation {
        guard let profile = processProfiles[process] else {
            return .askUser(reason: "Unknown process")
        }
        
        // Smart decision based on learned behavior
        if network.trustLevel == .trusted {
            return .allow(reason: "Trusted network")
        }
        
        // Check if this is a bandwidth hog
        if profile.averageBandwidth > 1_000_000 { // 1MB/s
            return .block(reason: "High bandwidth on untrusted network")
        }
        
        // Check if it's bursty
        if profile.isBursty && network.quality == .poor {
            return .block(reason: "Bursty traffic on poor network")
        }
        
        return .allow(reason: "Low impact process")
    }
    
    private func updateProcessProfile(
        for process: ProcessIdentity,
        with observation: TrafficObservation
    ) async {
        // Update running statistics
        var profile = processProfiles[process] ?? ProcessProfile(process: process)
        profile.addObservation(observation)
        processProfiles[process] = profile
    }
}
```

##### 3. Network Extension - FilterDataProvider.swift

```swift
// MARK: - Instructions for Claude Code
// This is the core system extension that does the actual filtering.
// Must be extremely performant - this is in the hot path for all network traffic.
// Use caching aggressively. Minimize allocations.

import NetworkExtension
import os.log

class FilterProvider: NEFilterDataProvider {
    private let logger = Logger(subsystem: "com..extension", category: "Filter")
    private var ruleEngine: FilterRuleEngine!
    private var processCache: LRUCache<pid_t, ProcessIdentity>!
    private var xpcConnection: XPCConnection!
    
    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        logger.info("Starting  filter")
        
        // Initialize components
        self.ruleEngine = FilterRuleEngine()
        self.processCache = LRUCache(capacity: 100)
        
        // Set up XPC connection to main app
        self.xpcConnection = XPCConnection()
        self.xpcConnection.connect()
        
        // Load initial rules
        Task {
            do {
                let rules = try await loadRules()
                await ruleEngine.updateRules(rules)
                completionHandler(nil)
            } catch {
                logger.error("Failed to start filter: \(error)")
                completionHandler(error)
            }
        }
    }
    
    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        // Fast path - check cache first
        let pid = flow.sourceProcessIdentifier ?? 0
        let process = processCache[pid] ?? identifyProcess(flow)
        
        // Get current network state (cached)
        let network = getCurrentNetwork()
        
        // Apply rules
        let decision = ruleEngine.evaluate(
            process: process,
            flow: flow,
            network: network
        )
        
        // Log if necessary (async to not block)
        if decision.shouldLog {
            Task.detached { [weak self] in
                await self?.logDecision(decision, flow: flow)
            }
        }
        
        // Return verdict
        switch decision.action {
        case .block:
            return NEFilterNewFlowVerdict.drop()
        case .allow:
            return NEFilterNewFlowVerdict.allow()
        }
    }
    
    private func identifyProcess(_ flow: NEFilterFlow) -> ProcessIdentity {
        // Identify the process making the connection
        var identity: ProcessIdentity
        
        if let audit = flow.sourceAppAuditToken,
           let bundleId = bundleIdentifier(for: audit) {
            // It's a regular app
            identity = ProcessIdentity(
                type: .application(bundleId: bundleId),
                name: displayName(for: bundleId),
                path: flow.sourceProcessPath
            )
        } else if let path = flow.sourceProcessPath {
            // Check if it's a brew service
            if path.starts(with: "/usr/local/") || path.starts(with: "/opt/homebrew/") {
                identity = ProcessIdentity(
                    type: .brewService,
                    name: URL(fileURLWithPath: path).lastPathComponent,
                    path: path
                )
            } else {
                // System process or daemon
                identity = ProcessIdentity(
                    type: .system,
                    name: URL(fileURLWithPath: path).lastPathComponent,
                    path: path
                )
            }
        } else {
            // Unknown process
            identity = ProcessIdentity(
                type: .unknown,
                name: "Unknown Process",
                path: nil
            )
        }
        
        // Cache it
        if let pid = flow.sourceProcessIdentifier {
            processCache[pid] = identity
        }
        
        return identity
    }
}
```

##### 4. Network Detection - NetworkMonitor.swift

```swift
// MARK: - Instructions for Claude Code
// Monitors network changes and identifies network characteristics.
// Must detect: WiFi SSID/BSSID, subnet, gateway, DNS, Tailscale interfaces.
// Use NWPathMonitor for efficiency.

import Network
import SystemConfiguration
import CoreWLAN
import os.log

@MainActor
public class NetworkMonitor: ObservableObject {
    @Published public private(set) var currentNetwork: DetectedNetwork?
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var trustLevel: NetworkTrustLevel = .untrusted
    
    private let pathMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com..networkmonitor")
    private let trustEvaluator: TrustEvaluator
    private let logger = Logger(subsystem: "com.", category: "NetworkMonitor")
    
    public init(trustEvaluator: TrustEvaluator) {
        self.trustEvaluator = trustEvaluator
        startMonitoring()
    }
    
    private func startMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                await self?.handlePathUpdate(path)
            }
        }
        pathMonitor.start(queue: queue)
    }
    
    private func handlePathUpdate(_ path: NWPath) async {
        logger.info("Network path updated: \(path.status)")
        
        self.isConnected = path.status == .satisfied
        
        guard isConnected else {
            self.currentNetwork = nil
            self.trustLevel = .untrusted
            return
        }
        
        // Detect network characteristics
        let network = await detectNetwork(from: path)
        self.currentNetwork = network
        
        // Evaluate trust
        self.trustLevel = await trustEvaluator.evaluate(network)
        
        logger.info("Network detected: \(network.displayName), Trust: \(self.trustLevel)")
    }
    
    private func detectNetwork(from path: NWPath) async -> DetectedNetwork {
        var network = DetectedNetwork()
        
        // Get interface information
        if let interface = path.availableInterfaces.first {
            network.interfaceName = interface.name
            network.interfaceType = interface.type
            
            // Check if it's Tailscale
            if interface.name.starts(with: "utun") {
                network.isTailscale = await checkTailscaleInterface(interface.name)
            }
        }
        
        // Get WiFi information
        if let wifi = CWWiFiClient.shared().interface() {
            network.ssid = wifi.ssid()
            network.bssid = wifi.bssid()
            network.rssi = wifi.rssiValue()
        }
        
        // Get IP information
        network.ipAddresses = getIPAddresses()
        network.gateway = getDefaultGateway()
        network.dnsServers = getDNSServers()
        
        // Determine network quality
        network.quality = estimateNetworkQuality(path)
        
        return network
    }
    
    private func checkTailscaleInterface(_ name: String) async -> Bool {
        // Check if this is actually a Tailscale interface
        // Could check for Tailscale daemon or specific IP ranges
        let tailscaleRanges = ["100.64.0.0/10", "fd7a:115c:a1e0::/48"]
        // Implementation here
        return false
    }
}
```

##### 5. Core Data Models - .xcdatamodeld

```xml
<!-- Instructions for Claude Code:
     Create this Core Data model with the following entities.
     Use lightweight migration compatible attributes.
     All entities should have indexes on commonly queried fields. -->

<!-- CDTrustedNetwork Entity -->
<entity name="CDTrustedNetwork" representedClassName="CDTrustedNetwork" syncable="YES">
    <attribute name="id" attributeType="UUID" usesScalarValueType="NO"/>
    <attribute name="name" attributeType="String"/>
    <attribute name="identifiersData" attributeType="Binary"/>
    <attribute name="dateAdded" attributeType="Date"/>
    <attribute name="isEnabled" attributeType="Boolean" defaultValueString="YES"/>
    <attribute name="customRulesData" optional="YES" attributeType="Binary"/>
    <uniquenessConstraints>
        <uniquenessConstraint>
            <constraint value="id"/>
        </uniquenessConstraint>
    </uniquenessConstraints>
</entity>

<!-- CDTrafficObservation Entity -->
<entity name="CDTrafficObservation" representedClassName="CDTrafficObservation" syncable="YES">
    <attribute name="timestamp" attributeType="Date"/>
    <attribute name="processIdentifier" attributeType="String"/>
    <attribute name="processName" attributeType="String"/>
    <attribute name="bytesIn" attributeType="Integer 64" defaultValueString="0"/>
    <attribute name="bytesOut" attributeType="Integer 64" defaultValueString="0"/>
    <attribute name="networkType" attributeType="String"/>
    <attribute name="networkSSID" optional="YES" attributeType="String"/>
    <indexes>
        <index name="byTimestamp">
            <index-field attributeName="timestamp"/>
        </index>
        <index name="byProcess">
            <index-field attributeName="processIdentifier"/>
        </index>
    </indexes>
</entity>

<!-- CDProcessProfile Entity -->
<entity name="CDProcessProfile" representedClassName="CDProcessProfile" syncable="YES">
    <attribute name="identifier" attributeType="String"/>
    <attribute name="displayName" attributeType="String"/>
    <attribute name="category" attributeType="String"/>
    <attribute name="averageBandwidth" attributeType="Double" defaultValueString="0"/>
    <attribute name="peakBandwidth" attributeType="Double" defaultValueString="0"/>
    <attribute name="isBursty" attributeType="Boolean" defaultValueString="NO"/>
    <attribute name="lastSeen" attributeType="Date"/>
    <attribute name="totalBytesIn" attributeType="Integer 64" defaultValueString="0"/>
    <attribute name="totalBytesOut" attributeType="Integer 64" defaultValueString="0"/>
    <uniquenessConstraints>
        <uniquenessConstraint>
            <constraint value="identifier"/>
        </uniquenessConstraint>
    </uniquenessConstraints>
</entity>
```

##### 6. Testing Structure - NetworkMonitorTests.swift

```swift
// MARK: - Instructions for Claude Code
// Write comprehensive tests for all components.
// Use dependency injection to make everything testable.
// Tests must be fast and isolated.

import XCTest
@testable import 

class NetworkMonitorTests: XCTestCase {
    var sut: NetworkMonitor!
    var mockTrustEvaluator: MockTrustEvaluator!
    
    override func setUp() {
        super.setUp()
        mockTrustEvaluator = MockTrustEvaluator()
        sut = NetworkMonitor(trustEvaluator: mockTrustEvaluator)
    }
    
    func test_detectNetwork_whenOnHomeWiFi_returnsTrustedNetwork() async {
        // Arrange
        let homeNetwork = DetectedNetwork(
            ssid: "HomeWiFi",
            gateway: "192.168.1.1",
            subnet: "192.168.1.0/24"
        )
        mockTrustEvaluator.stubResult = .trusted
        
        // Act
        await sut.updateNetwork(homeNetwork)
        
        // Assert
        XCTAssertEqual(sut.trustLevel, .trusted)
        XCTAssertEqual(sut.currentNetwork?.ssid, "HomeWiFi")
    }
    
    func test_detectNetwork_whenOnCellular_returnsUntrustedNetwork() async {
        // Arrange
        let cellularNetwork = DetectedNetwork(
            interfaceType: .cellular
        )
        mockTrustEvaluator.stubResult = .untrusted
        
        // Act  
        await sut.updateNetwork(cellularNetwork)
        
        // Assert
        XCTAssertEqual(sut.trustLevel, .untrusted)
        XCTAssertEqual(sut.currentNetwork?.interfaceType, .cellular)
    }
}

// Mock for testing
class MockTrustEvaluator: TrustEvaluating {
    var stubResult: NetworkTrustLevel = .untrusted
    var evaluateCallCount = 0
    
    func evaluate(_ network: DetectedNetwork) async -> NetworkTrustLevel {
        evaluateCallCount += 1
        return stubResult
    }
}
```

#### Key Implementation Guidelines for Claude Code

1. **Dependencies**: Always inject, never hard-code
2. **Async**: Use async/await, no callbacks or completion handlers
3. **Errors**: Define specific error types for each module
4. **Testing**: Write tests immediately after implementation
5. **Documentation**: Every public API needs DocC comments
6. **Performance**: Profile critical paths, especially in FilterDataProvider
7. **Memory**: Use value types where possible, weak references for delegates
8. **Security**: Validate all XPC communications, use App Groups for shared data
9. **Logging**: Structured logging with os_log, privacy-safe
10. **UI**: SwiftUI with ViewModels, no business logic in views

#### Build and Release Configuration

```yaml
# Xcode Configuration for Claude Code

Targets:
  -  (Main App)
    - Deployment: macOS 13.0+
    - Sandbox: YES
    - Hardened Runtime: YES
    - Entitlements:
      - com.apple.security.network.client
      - com.apple.security.temporary-exception.mach-lookup.global-name
  
  - Extension (System Extension)
    - Type: Network Extension
    - Provider: Filter Data Provider
    - Entitlements:
      - com.apple.security.app-sandbox
      - com.apple.security.network.server
      
  - Core (Shared Framework)
    - Type: Framework
    - Deployment: macOS 13.0+

Schemes:
  - Debug: Local testing, verbose logging
  - Release: Optimized, minimal logging  
  - UITest: UI testing configuration

Test Plans:
  - Unit: All unit tests, parallel execution
  - Integration: Integration tests, serial execution
  - Smoke: Critical path tests for CI
  - Full: Everything for release validation
```

#### Initial Sprint Planning

```yaml
Sprint 1 (MVP Core):
  - Basic trusted network detection (SSID only)
  - Simple block/allow for all apps
  - Core Data setup
  - Menu bar status

Sprint 2 (Intelligence):
  - Process identification (apps, brew, system)
  - Traffic monitoring
  - Basic learning system
  - Setup wizard

Sprint 3 (Polish):
  - Advanced network detection (subnet, gateway)
  - Process grouping
  - Traffic analytics view
  - Quick override options

Sprint 4 (Power User):
  - Complex trust rules
  - Export/import
  - Automation support
  - Performance optimization
```

This architecture provides a solid foundation that's both simple enough for MVP and robust enough to grow into a sophisticated traffic management system. The trust-based model keeps it intuitive while the learning system makes it intelligent.
