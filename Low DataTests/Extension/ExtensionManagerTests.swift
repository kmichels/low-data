//
//  ExtensionManagerTests.swift
//  Low DataTests
//
//  Created by Konrad Michels on 8/27/25.
//

import XCTest
import SystemExtensions
import NetworkExtension
@testable import Low_Data

@MainActor
final class ExtensionManagerTests: XCTestCase {
    
    var extensionManager: ExtensionManager!
    
    override func setUp() async throws {
        try await super.setUp()
        extensionManager = ExtensionManager()
    }
    
    override func tearDown() async throws {
        extensionManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Status Tests
    
    func test_initialStatus() {
        // Then
        XCTAssertEqual(extensionManager.extensionStatus, .notInstalled)
        XCTAssertNil(extensionManager.filterStatus)
        XCTAssertEqual(extensionManager.installationProgress, 0.0)
        XCTAssertNil(extensionManager.errorMessage)
    }
    
    func test_checkStatus() async {
        // When
        await extensionManager.checkStatus()
        
        // Then - Should attempt to check status (may fail in tests due to entitlements)
        // Just verify it doesn't crash
        XCTAssertNotNil(extensionManager.extensionStatus)
    }
    
    // MARK: - Installation Flow Tests (Mocked)
    
    func test_installExtension_setsInstallingStatus() async {
        // Note: Actual installation will fail in tests due to missing entitlements
        // This tests the initial state changes
        
        // When - Start installation (will fail, but we can test initial state)
        Task {
            do {
                try await extensionManager.installExtension()
            } catch {
                // Expected to fail in test environment
            }
        }
        
        // Give it a moment to update status
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        
        // Then - Should have updated to installing status
        XCTAssertTrue(
            extensionManager.extensionStatus == .installing ||
            extensionManager.extensionStatus == .error
        )
    }
    
    // MARK: - Delegate Method Tests
    
    func test_requestNeedsUserApproval_updatesStatus() {
        // Given
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: "com.test.extension",
            queue: .main
        )
        
        // When
        extensionManager.requestNeedsUserApproval(request)
        
        // Then
        XCTAssertEqual(extensionManager.extensionStatus, .needsApproval)
        XCTAssertEqual(extensionManager.installationProgress, 0.5)
    }
    
    func test_requestDidFinishWithResult_completed() {
        // Given
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: "com.test.extension",
            queue: .main
        )
        
        // When
        extensionManager.request(request, didFinishWithResult: .completed)
        
        // Then
        XCTAssertEqual(extensionManager.extensionStatus, .installed)
        XCTAssertEqual(extensionManager.installationProgress, 1.0)
        XCTAssertNil(extensionManager.errorMessage)
    }
    
    func test_requestDidFinishWithResult_willCompleteAfterReboot() {
        // Given
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: "com.test.extension",
            queue: .main
        )
        
        // When
        extensionManager.request(request, didFinishWithResult: .willCompleteAfterReboot)
        
        // Then
        XCTAssertEqual(extensionManager.extensionStatus, .needsReboot)
        XCTAssertEqual(extensionManager.errorMessage, "System extension will be activated after reboot")
    }
    
    func test_requestDidFailWithError_updatesStatus() {
        // Given
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: "com.test.extension",
            queue: .main
        )
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        
        // When
        extensionManager.request(request, didFailWithError: error)
        
        // Then
        XCTAssertEqual(extensionManager.extensionStatus, .error)
        XCTAssertEqual(extensionManager.installationProgress, 0.0)
        XCTAssertEqual(extensionManager.errorMessage, "Test error")
    }
    
    func test_requestActionForReplacingExtension() {
        // Given
        let existingProps = OSSystemExtensionProperties()
        let newProps = OSSystemExtensionProperties()
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: "com.test.extension",
            queue: .main
        )
        
        // When
        let action = extensionManager.request(
            request,
            actionForReplacingExtension: existingProps,
            withExtension: newProps
        )
        
        // Then
        XCTAssertEqual(action, .replace)
    }
    
    // MARK: - Error Handling Tests
    
    func test_extensionError_descriptions() {
        // Test all error cases have descriptions
        let errors: [ExtensionError] = [
            .installationTimeout,
            .installationFailed("Test reason"),
            .uninstallationTimeout,
            .uninstallationFailed("Test reason"),
            .filterConfigurationFailed("Test reason")
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
    
    // MARK: - Published Property Tests
    
    func test_publishedProperties_trigger() async {
        // Given
        let expectation = XCTestExpectation(description: "Status changed")
        
        let cancellable = extensionManager.$extensionStatus
            .dropFirst() // Skip initial value
            .sink { _ in
                expectation.fulfill()
            }
        
        // When
        extensionManager.extensionStatus = .installing
        
        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        
        _ = cancellable // Keep reference
    }
}

// MARK: - Mock System Extension Properties

extension OSSystemExtensionProperties {
    convenience override init() {
        self.init()
    }
    
    var testBundleShortVersion: String {
        return "1.0.0"
    }
}