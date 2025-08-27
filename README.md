# Low Data

An intelligent network traffic management application for macOS that automatically conserves bandwidth on untrusted networks by learning usage patterns and blocking bandwidth-heavy applications.

## Overview

Low Data helps you save bandwidth when you're away from trusted networks (like home or office). It automatically detects when you're on public WiFi, cellular hotspots, or metered connections and intelligently blocks bandwidth-heavy applications while allowing essential traffic through.

## Key Features

- **Trust-based Network Management**: Define trusted networks (home/office) - everything else is automatically managed
- **Zero Configuration**: Works out-of-the-box with smart defaults
- **Intelligent Learning**: Observes your usage patterns to make better blocking decisions
- **Process-aware Filtering**: Identifies apps, Homebrew services, and system daemons
- **Menu Bar Control**: Quick status and override controls always accessible
- **Privacy-first**: All data stays local on your Mac - no cloud dependencies

## System Requirements

- macOS 13.0 (Ventura) or later
- Admin privileges for initial setup (System Extension installation)

## Installation

*Coming soon - the app is currently under development*

## How It Works

1. **Network Detection**: Low Data monitors your network connections and identifies whether you're on a trusted network
2. **Smart Filtering**: On untrusted networks, it automatically blocks known bandwidth-heavy applications
3. **Learning Mode**: The app learns from your usage patterns to improve its decisions over time
4. **Quick Overrides**: Need something unblocked temporarily? Use the menu bar for quick access

## Use Cases

- **Digital Nomads**: Stop cloud services from eating through hotel WiFi
- **Mobile Hotspots**: Prevent background apps from consuming cellular data
- **Coffee Shops**: Keep your bandwidth for what matters on public WiFi
- **Data Caps**: Stay under your ISP's data limits by controlling background traffic

## Development Status

This project is currently in active development. The MVP will include:

- Basic trusted network identification
- Automatic blocking on untrusted networks
- Process identification for common apps
- Menu bar interface
- Basic traffic visibility

## Building from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/kmichels/low-data.git
   cd low-data
   ```

2. Open in Xcode:
   ```bash
   open "Low Data.xcodeproj"
   ```

3. Build and run (⌘+R)

## Architecture

Low Data uses:
- **System Extension** (Network Extension) for traffic filtering
- **SwiftUI** for the user interface
- **Core Data** for persistence
- **Swift Concurrency** for async operations

## Contributing

This project is in early development. Contributions, ideas, and feedback are welcome! Please open an issue to discuss major changes before submitting PRs.

## License

*License to be determined*

## Privacy

Low Data is designed with privacy in mind:
- All data processing happens locally on your device
- No telemetry or analytics
- No cloud services required
- Network information never leaves your Mac

## Contact

Project by Konrad Michels - [GitHub](https://github.com/kmichels)

---

**Note**: This is an early-stage project under active development. Features and implementation details are subject to change.