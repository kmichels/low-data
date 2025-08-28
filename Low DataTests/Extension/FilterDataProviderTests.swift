//
//  FilterDataProviderTests.swift
//  Low DataTests
//
//  Created by Konrad Michels on 8/27/25.
//

import XCTest
import NetworkExtension
@testable import Low_Data

final class FilterDataProviderTests: XCTestCase {
    
    // Note: Full FilterDataProvider testing requires Network Extension entitlements
    // These tests focus on the supporting components
    
    // MARK: - LRU Cache Tests
    
    func test_lruCache_basic() {
        // Given
        let cache = LRUCache<String, Int>(capacity: 3)
        
        // When
        cache.put("one", 1)
        cache.put("two", 2)
        cache.put("three", 3)
        
        // Then
        XCTAssertEqual(cache.get("one"), 1)
        XCTAssertEqual(cache.get("two"), 2)
        XCTAssertEqual(cache.get("three"), 3)
        XCTAssertNil(cache.get("four"))
    }
    
    func test_lruCache_evictsLeastRecentlyUsed() {
        // Given
        let cache = LRUCache<String, Int>(capacity: 3)
        
        // When - Fill cache
        cache.put("one", 1)
        cache.put("two", 2)
        cache.put("three", 3)
        
        // Access "one" to make it more recently used
        _ = cache.get("one")
        
        // Add new item (should evict "two" or "three", not "one")
        cache.put("four", 4)
        
        // Then
        XCTAssertNotNil(cache.get("one")) // Should still be there
        XCTAssertNotNil(cache.get("four")) // New item
        
        // One of these should be evicted
        let twoExists = cache.get("two") != nil
        let threeExists = cache.get("three") != nil
        XCTAssertTrue(twoExists || threeExists) // At least one remains
        XCTAssertFalse(twoExists && threeExists) // But not both
    }
    
    func test_lruCache_clear() {
        // Given
        let cache = LRUCache<String, String>(capacity: 5)
        cache.put("key1", "value1")
        cache.put("key2", "value2")
        
        // When
        cache.clear()
        
        // Then
        XCTAssertNil(cache.get("key1"))
        XCTAssertNil(cache.get("key2"))
    }
    
    func test_lruCache_threadSafety() {
        // Given
        let cache = LRUCache<Int, String>(capacity: 100)
        let expectation = XCTestExpectation(description: "Concurrent operations complete")
        expectation.expectedFulfillmentCount = 2
        
        // When - Concurrent reads and writes
        DispatchQueue.global().async {
            for i in 0..<50 {
                cache.put(i, "value\(i)")
            }
            expectation.fulfill()
        }
        
        DispatchQueue.global().async {
            for i in 0..<50 {
                _ = cache.get(i)
            }
            expectation.fulfill()
        }
        
        // Then
        wait(for: [expectation], timeout: 1.0)
        
        // Cache should still work
        cache.put(999, "test")
        XCTAssertEqual(cache.get(999), "test")
    }
    
    // MARK: - Flow Key Tests
    
    func test_flowKey_equality() {
        // Given
        let key1 = FlowKey(
            remoteHost: "example.com",
            remotePort: "443",
            localPort: "12345",
            direction: .outbound
        )
        
        let key2 = FlowKey(
            remoteHost: "example.com",
            remotePort: "443",
            localPort: "12345",
            direction: .outbound
        )
        
        let key3 = FlowKey(
            remoteHost: "different.com",
            remotePort: "443",
            localPort: "12345",
            direction: .outbound
        )
        
        // Then
        XCTAssertEqual(key1, key2)
        XCTAssertNotEqual(key1, key3)
    }
    
    func test_flowKey_hashable() {
        // Given
        let key1 = FlowKey(
            remoteHost: "example.com",
            remotePort: "443",
            localPort: "12345",
            direction: .outbound
        )
        
        let key2 = FlowKey(
            remoteHost: "example.com",
            remotePort: "443",
            localPort: "12345",
            direction: .outbound
        )
        
        // When
        var set = Set<FlowKey>()
        set.insert(key1)
        set.insert(key2)
        
        // Then - Should only have one entry (keys are equal)
        XCTAssertEqual(set.count, 1)
    }
    
    // MARK: - Filter Decision Tests
    
    func test_filterDecision_factoryMethods() {
        // When
        let allowDecision = FilterDecision.allow(reason: "Test allow")
        let blockDecision = FilterDecision.block(reason: "Test block")
        let inspectDecision = FilterDecision.inspect(reason: "Test inspect")
        
        // Then
        XCTAssertEqual(allowDecision.action, .allow)
        XCTAssertEqual(allowDecision.reason, "Test allow")
        XCTAssertFalse(allowDecision.shouldRecord)
        
        XCTAssertEqual(blockDecision.action, .block)
        XCTAssertEqual(blockDecision.reason, "Test block")
        XCTAssertTrue(blockDecision.shouldRecord)
        
        XCTAssertEqual(inspectDecision.action, .inspect)
        XCTAssertEqual(inspectDecision.reason, "Test inspect")
        XCTAssertTrue(inspectDecision.shouldRecord)
    }
    
    // MARK: - Performance Tests
    
    func test_performance_cacheOperations() {
        let cache = LRUCache<Int, String>(capacity: 1000)
        
        // Populate cache
        for i in 0..<1000 {
            cache.put(i, "value\(i)")
        }
        
        measure {
            // Perform mixed operations
            for i in 0..<100 {
                _ = cache.get(i)
                cache.put(i + 1000, "new\(i)")
            }
        }
    }
    
    func test_performance_flowKeyHashing() {
        let keys = (0..<1000).map { i in
            FlowKey(
                remoteHost: "host\(i).com",
                remotePort: "443",
                localPort: "\(12345 + i)",
                direction: i % 2 == 0 ? .outbound : .inbound
            )
        }
        
        measure {
            var set = Set<FlowKey>()
            for key in keys {
                set.insert(key)
            }
        }
    }
}

// MARK: - Mock NEFilterFlow for Testing

class MockNEFilterSocketFlow: NEFilterSocketFlow {
    var mockURL: URL?
    var mockRemoteEndpoint: NWEndpoint?
    var mockLocalEndpoint: NWEndpoint?
    var mockDirection: NETrafficDirection = .outbound
    
    override var url: URL? {
        return mockURL
    }
    
    override var remoteEndpoint: NWEndpoint? {
        return mockRemoteEndpoint
    }
    
    override var localEndpoint: NWEndpoint? {
        return mockLocalEndpoint
    }
    
    override var direction: NETrafficDirection {
        return mockDirection
    }
}