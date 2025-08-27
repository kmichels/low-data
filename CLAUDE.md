# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Low Data is an intelligent network traffic management application for macOS that automatically conserves bandwidth on untrusted networks by learning usage patterns and blocking bandwidth-heavy applications.

## Development Commands

### Build and Run
```bash
# Build the project
xcodebuild -scheme "Low Data" build

# Run tests
xcodebuild -scheme "Low Data" test

# Run UI tests
xcodebuild -scheme "Low DataUITests" test

# Clean build folder
xcodebuild -scheme "Low Data" clean

# Build for release
xcodebuild -scheme "Low Data" -configuration Release build
```

### Testing
```bash
# Run all tests
xcodebuild test -scheme "Low Data" -destination 'platform=macOS'

# Run specific test class
xcodebuild test -scheme "Low Data" -destination 'platform=macOS' -only-testing:Low_DataTests/NetworkMonitorTests

# Run with coverage
xcodebuild test -scheme "Low Data" -destination 'platform=macOS' -enableCodeCoverage YES
```

## Architecture Overview

### High-Level Components

1. **Main GUI App** - SwiftUI-based configuration and analytics interface
2. **System Extension** - Network Extension for actual traffic filtering
3. **Menu Bar Interface** - Quick access and status display
4. **Core Data + Learning** - Intelligence layer for traffic analysis

### Key Design Principles

- **Clean Architecture + MVVM** pattern throughout
- **Protocol-first design** with dependency injection
- **Actor isolation** for shared state management
- **Async/await** for all asynchronous operations
- **Trust-based model**: Networks are either trusted (home/office) or untrusted

### Module Structure

```
Low Data/
├── Domain/           # Business logic, use cases, repository protocols
├── Data/            # Core Data implementation, repositories
├── Presentation/    # Views, ViewModels, UI components
└── Infrastructure/  # Network detection, process identification

Low Data Extension/
├── FilterDataProvider.swift  # Core filtering logic (performance critical)
├── FilterRuleEngine.swift    # Rule evaluation
└── XPC/                      # Communication with main app
```

### Critical Implementation Notes

#### Network Extension (FilterDataProvider)
- **Performance Critical**: This is in the hot path for ALL network traffic
- Use aggressive caching (LRUCache for process identification)
- Minimize allocations
- Fast path checks before complex evaluations

#### Network Detection
- Must detect: WiFi SSID/BSSID, subnet, gateway, DNS, Tailscale interfaces
- Use NWPathMonitor for efficiency
- CWWiFiClient for WiFi details
- Check for Tailscale via utun interfaces

#### Process Identification
- Identify: Applications (bundle ID), Brew services, system daemons
- Cache process identities by PID
- Group helper processes with parent apps

#### Traffic Intelligence
- Use actor isolation for thread safety
- Implement sliding window (CircularBuffer) for observations
- Limit to 10,000 observations in memory
- Persist periodically to Core Data

### Core Data Entities

1. **CDTrustedNetwork** - Trusted network configurations
2. **CDTrafficObservation** - Traffic monitoring data
3. **CDProcessProfile** - Learned process behavior

All entities need indexes on commonly queried fields.

### Testing Requirements

- **Minimum 80% code coverage**
- Use XCTest framework
- Dependency injection for all components
- Mock external dependencies
- Tests must be fast and isolated

### Security & Privacy

- All data stays local (no cloud sync in MVP)
- Use App Groups for shared data between app and extension
- Validate all XPC communications
- Structured logging with os_log (privacy-safe)
- Never log sensitive network information

### Performance Targets

- <1% CPU usage during normal operation
- <50MB RAM footprint
- Filter decisions must be made in <1ms
- Setup completion in <5 minutes

### Development Workflow

1. Always inject dependencies, never hard-code
2. Use async/await, no callbacks or completion handlers
3. Define specific error types for each module
4. Write tests immediately after implementation
5. Every public API needs DocC comments
6. Profile critical paths, especially in FilterDataProvider
7. Use value types where possible, weak references for delegates

### Key Technical Decisions

- **Platform**: macOS 13.0+ only
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Persistence**: Core Data
- **Network Extension**: NEFilterDataProvider
- **Concurrency**: Swift Concurrency (async/await, actors)

### MVP Features (v1.0)

Must Have:
- Trusted network identification (SSID + subnet)
- Automatic blocking on untrusted networks
- Process identification (apps, brew services, daemons)
- Default rules for common bandwidth hogs
- Menu bar status and quick controls
- Basic traffic visibility

### Common Tasks

When implementing network trust evaluation:
1. Check NetworkMonitor.swift for detection logic
2. Use TrustEvaluator protocol for evaluation
3. Store trusted networks in Core Data
4. Update FilterRuleEngine with new rules

When adding new process detection:
1. Update ProcessIdentifier.swift
2. Add detection logic to FilterDataProvider
3. Update process cache strategy
4. Add tests for new detection method

When modifying filtering rules:
1. Update FilterRuleEngine.swift
2. Ensure XPC protocol is updated if needed
3. Test with common applications
4. Verify performance impact