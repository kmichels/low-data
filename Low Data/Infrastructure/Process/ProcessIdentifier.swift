//
//  ProcessIdentifier.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
import AppKit
import OSLog

/// Service for identifying processes from PIDs and network connections
@MainActor
public final class ProcessIdentifier {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.lowdata", category: "ProcessIdentifier")
    private var processCache = LRUCache<pid_t, ProcessIdentity>(capacity: 100)
    private let brewDetector: BrewServiceDetector
    
    // MARK: - Initialization
    
    public init(brewDetector: BrewServiceDetector = BrewServiceDetector()) {
        self.brewDetector = brewDetector
    }
    
    // MARK: - Public Methods
    
    /// Identify a process from its PID
    public func identify(pid: pid_t) -> ProcessIdentity {
        // Check cache first
        if let cached = processCache.get(pid) {
            return cached
        }
        
        // Get process info
        let identity = identifyProcess(pid: pid)
        
        // Cache the result
        processCache.put(pid, identity)
        
        return identity
    }
    
    /// Identify a process from audit token (used in Network Extension)
    public func identify(auditToken: Data) -> ProcessIdentity {
        // Extract PID from audit token
        let pid = extractPID(from: auditToken)
        return identify(pid: pid)
    }
    
    /// Clear the process cache
    public func clearCache() {
        processCache.clear()
    }
    
    // MARK: - Private Methods
    
    private func identifyProcess(pid: pid_t) -> ProcessIdentity {
        // Try to get app bundle first
        if let app = NSRunningApplication(processIdentifier: pid) {
            return identifyApplication(app)
        }
        
        // Try to get process info via sysctl
        if let info = getProcessInfo(pid: pid) {
            return identifyFromProcessInfo(info)
        }
        
        // Fallback to unknown
        return ProcessIdentity(
            type: .unknown,
            name: "Unknown Process (\(pid))"
        )
    }
    
    private func identifyApplication(_ app: NSRunningApplication) -> ProcessIdentity {
        let bundleId = app.bundleIdentifier
        let name = app.localizedName ?? app.executableURL?.lastPathComponent ?? "Unknown App"
        let path = app.executableURL?.path
        
        // Check if it's a system app
        let type: ProcessType = {
            if let bundle = bundleId {
                if bundle.hasPrefix("com.apple.") {
                    return .system
                }
            }
            if let appPath = path {
                if appPath.hasPrefix("/System/") || appPath.hasPrefix("/usr/") {
                    return .system
                }
            }
            return .application
        }()
        
        return ProcessIdentity(
            type: type,
            name: name,
            bundleId: bundleId,
            path: path,
            pid: app.processIdentifier
        )
    }
    
    private func identifyFromProcessInfo(_ info: ProcessInfo) -> ProcessIdentity {
        let name = info.name
        let path = info.path
        
        // Check if it's a Homebrew service
        if brewDetector.isBrewService(path: path) {
            return ProcessIdentity(
                type: .brewService,
                name: brewDetector.extractServiceName(from: path) ?? name,
                path: path,
                pid: info.pid
            )
        }
        
        // Check if it's a daemon
        if path.contains("/LaunchDaemons/") || path.contains("/LaunchAgents/") ||
           name.hasSuffix("d") || path.contains("/sbin/") {
            return ProcessIdentity(
                type: .daemon,
                name: name,
                path: path,
                pid: info.pid
            )
        }
        
        // Check if it's a system process
        if path.hasPrefix("/System/") || path.hasPrefix("/usr/") {
            return ProcessIdentity(
                type: .system,
                name: name,
                path: path,
                pid: info.pid
            )
        }
        
        return ProcessIdentity(
            type: .unknown,
            name: name,
            path: path,
            pid: info.pid
        )
    }
    
    private func getProcessInfo(pid: pid_t) -> ProcessInfo? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        
        let result = sysctl(&mib, 4, &info, &size, nil, 0)
        guard result == 0 else {
            logger.warning("Failed to get process info for PID \(pid)")
            return nil
        }
        
        // Extract process name
        let name = withUnsafePointer(to: &info.kp_proc.p_comm) { ptr in
            let buffer = ptr.withMemoryRebound(to: CChar.self, capacity: 16) { $0 }
            return String(cString: buffer)
        }
        
        // Get full path using proc_pidpath
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(MAXPATHLEN))
        
        let path: String?
        if pathLength > 0 {
            path = String(cString: pathBuffer)
        } else {
            path = nil
        }
        
        return ProcessInfo(pid: pid, name: name, path: path ?? "")
    }
    
    private func extractPID(from auditToken: Data) -> pid_t {
        // audit_token_t has pid at offset 20 (5th uint32)
        guard auditToken.count >= 24 else {
            logger.warning("Invalid audit token size: \(auditToken.count)")
            return 0
        }
        
        return auditToken.withUnsafeBytes { bytes in
            let uint32Pointer = bytes.bindMemory(to: UInt32.self)
            return pid_t(uint32Pointer[5])
        }
    }
}

// MARK: - Supporting Types

private struct ProcessInfo {
    let pid: pid_t
    let name: String
    let path: String
}

// MARK: - LRU Cache

private final class LRUCache<Key: Hashable, Value> {
    private struct CacheEntry {
        let value: Value
        var timestamp: Date
    }
    
    private var cache: [Key: CacheEntry] = [:]
    private let capacity: Int
    private let lock = NSLock()
    
    init(capacity: Int) {
        self.capacity = capacity
    }
    
    func get(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        
        if var entry = cache[key] {
            entry.timestamp = Date()
            cache[key] = entry
            return entry.value
        }
        return nil
    }
    
    func put(_ key: Key, _ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        
        // Remove oldest entry if at capacity
        if cache.count >= capacity && cache[key] == nil {
            if let oldestKey = cache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key {
                cache.removeValue(forKey: oldestKey)
            }
        }
        
        cache[key] = CacheEntry(value: value, timestamp: Date())
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
}

// MARK: - System Imports

import Darwin

private let CTL_KERN = 1
private let KERN_PROC = 14
private let KERN_PROC_PID = 1

@_silgen_name("proc_pidpath")
private func proc_pidpath(_ pid: pid_t, _ buffer: UnsafeMutablePointer<CChar>, _ bufferSize: UInt32) -> Int32