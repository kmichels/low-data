//
//  ExtensionActivationView.swift
//  Low Data
//
//  Created on 8/28/25.
//

import SwiftUI

struct ExtensionActivationView: View {
    @StateObject private var extensionManager = ExtensionManager.shared
    @StateObject private var xpcClient = FilterControlXPCClient.shared
    
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isConnecting = false
    
    var body: some View {
        VStack(spacing: 30) {
            // Status Header
            statusHeader
            
            // Main Content
            VStack(spacing: 20) {
                switch extensionManager.extensionStatus {
                case .notInstalled:
                    notInstalledView
                case .needsApproval:
                    needsApprovalView
                case .installed:
                    installedView
                case .running:
                    runningView
                case .requiresReboot:
                    requiresRebootView
                case .error(let message):
                    errorView(message)
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .task {
            await checkConnection()
        }
    }
    
    // MARK: - Status Header
    
    private var statusHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.system(size: 48))
                .foregroundColor(statusColor)
                .symbolRenderingMode(.hierarchical)
            
            Text(statusTitle)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(statusSubtitle)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var statusIcon: String {
        switch extensionManager.extensionStatus {
        case .notInstalled: return "shield.slash"
        case .needsApproval: return "exclamationmark.shield"
        case .installed: return "shield"
        case .running: return "shield.checkmark"
        case .requiresReboot: return "restart.circle"
        case .error: return "xmark.shield"
        }
    }
    
    private var statusColor: Color {
        switch extensionManager.extensionStatus {
        case .notInstalled: return .gray
        case .needsApproval: return .orange
        case .installed: return .blue
        case .running: return .green
        case .requiresReboot: return .orange
        case .error: return .red
        }
    }
    
    private var statusTitle: String {
        switch extensionManager.extensionStatus {
        case .notInstalled: return "Extension Not Installed"
        case .needsApproval: return "Approval Required"
        case .installed: return "Extension Installed"
        case .running: return "Extension Active"
        case .requiresReboot: return "Reboot Required"
        case .error: return "Extension Error"
        }
    }
    
    private var statusSubtitle: String {
        switch extensionManager.extensionStatus {
        case .notInstalled: 
            return "The network filter extension needs to be installed"
        case .needsApproval: 
            return "Please approve the extension in System Settings"
        case .installed: 
            return "Extension is ready to be activated"
        case .running: 
            return "Network filtering is active"
        case .requiresReboot: 
            return "Please restart your Mac to complete installation"
        case .error(let message): 
            return message
        }
    }
    
    // MARK: - State Views
    
    private var notInstalledView: some View {
        VStack(spacing: 16) {
            Text("Low Data needs to install a system extension to filter network traffic.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button(action: installExtension) {
                if extensionManager.isActivating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                        .frame(width: 20, height: 20)
                } else {
                    Label("Install Extension", systemImage: "arrow.down.circle")
                }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(extensionManager.isActivating)
        }
    }
    
    private var needsApprovalView: some View {
        VStack(spacing: 16) {
            Text("The extension requires your approval to run.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                Label("Open System Settings", systemImage: "1.circle.fill")
                Label("Go to Privacy & Security", systemImage: "2.circle.fill")
                Label("Allow the Low Data extension", systemImage: "3.circle.fill")
            }
            .font(.callout)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            HStack(spacing: 12) {
                Button("Open System Settings") {
                    openSystemSettings()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Check Status") {
                    extensionManager.checkExtensionStatus()
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
    }
    
    private var installedView: some View {
        VStack(spacing: 16) {
            Text("Extension is installed but not active.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                Button(action: activateFiltering) {
                    Label("Activate Filtering", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                
                Button(action: uninstallExtension) {
                    Label("Uninstall", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
    }
    
    private var runningView: some View {
        VStack(spacing: 20) {
            // Connection Status
            HStack {
                Circle()
                    .fill(xpcClient.isConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                
                Text(xpcClient.isConnected ? "Connected to Extension" : "Connecting...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Filter Status
            if let status = xpcClient.filterStatus {
                VStack(spacing: 12) {
                    HStack {
                        Text("Filtering:")
                        Spacer()
                        Text(status.isEnabled ? "Enabled" : "Disabled")
                            .foregroundColor(status.isEnabled ? .green : .orange)
                    }
                    
                    HStack {
                        Text("Network:")
                        Spacer()
                        Text(status.currentNetworkTrusted ? "Trusted" : "Untrusted")
                            .foregroundColor(status.currentNetworkTrusted ? .green : .orange)
                    }
                    
                    HStack {
                        Text("Blocked:")
                        Spacer()
                        Text("\(status.blockedConnectionCount)")
                    }
                    
                    HStack {
                        Text("Allowed:")
                        Spacer()
                        Text("\(status.allowedConnectionCount)")
                    }
                }
                .font(.system(.body, design: .monospaced))
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            // Actions
            HStack(spacing: 12) {
                Button(action: toggleFiltering) {
                    Label(
                        xpcClient.filterStatus?.isEnabled == true ? "Disable" : "Enable",
                        systemImage: xpcClient.filterStatus?.isEnabled == true ? "pause.fill" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                
                Button(action: refreshStatus) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                
                Button(action: deactivateFiltering) {
                    Label("Deactivate", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
    }
    
    private var requiresRebootView: some View {
        VStack(spacing: 16) {
            Text("A system restart is required to complete the installation.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button("Restart Now") {
                restartSystem()
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button("Retry") {
                Task {
                    await retryInstallation()
                }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - Actions
    
    private func installExtension() {
        Task {
            let result = await extensionManager.activateExtension()
            
            switch result {
            case .success:
                await checkConnection()
            case .needsUserApproval:
                break // UI will update automatically
            case .failed(let error):
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func uninstallExtension() {
        Task {
            _ = await extensionManager.deactivateExtension()
        }
    }
    
    private func activateFiltering() {
        Task {
            do {
                try await extensionManager.enableContentFilter()
                await checkConnection()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func deactivateFiltering() {
        Task {
            do {
                try await extensionManager.disableContentFilter()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func toggleFiltering() {
        Task {
            do {
                let isEnabled = xpcClient.filterStatus?.isEnabled ?? false
                try await xpcClient.setFilteringEnabled(!isEnabled)
                try await xpcClient.fetchFilterStatus()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func refreshStatus() {
        Task {
            await checkConnection()
        }
    }
    
    private func checkConnection() async {
        if extensionManager.extensionStatus == .running {
            isConnecting = true
            
            // Connect to XPC
            xpcClient.connect()
            
            // Fetch status
            do {
                try await xpcClient.fetchFilterStatus()
                try await xpcClient.fetchCurrentNetwork()
            } catch {
                print("Failed to fetch status: \(error)")
            }
            
            isConnecting = false
        }
    }
    
    private func retryInstallation() async {
        _ = await extensionManager.activateExtension()
    }
    
    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SystemExtensions") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func restartSystem() {
        let source = """
            tell application "System Events"
                restart
            end tell
            """
        
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
        }
    }
}