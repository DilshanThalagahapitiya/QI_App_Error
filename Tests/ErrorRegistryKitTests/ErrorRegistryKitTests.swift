//
//  ErrorRegistryKitTests.swift
//  ErrorRegistryKitTests
//
//  Created by Dilshan Thalagahapitiya on 2026-08-18.
//

import XCTest
@testable import ErrorRegistryKit

final class ErrorRegistryKitTests: XCTestCase {

    // MARK: - Bundled Fallback

    func testBundledFallbackLoads() {
        let registry = BundledFallbackRegistry.shared
        XCTAssertGreaterThan(registry.allErrors.count, 30, "Bundled registry should have 30+ errors")
    }

    func testBundledFallbackLookupByKey() {
        let registry = BundledFallbackRegistry.shared
        let info = registry.info(for: "LOGIN_001_BadCredentials")
        XCTAssertEqual(info.key, "LOGIN_001_BadCredentials")
        XCTAssertEqual(info.title, "Invalid Credentials")
        XCTAssertFalse(info.message.isEmpty)
    }

    func testBundledFallbackLookupByStatusCode() {
        let registry = BundledFallbackRegistry.shared
        let info = registry.info(forStatusCode: 401, domain: "LOGIN")
        XCTAssertEqual(info.key, "LOGIN_001_BadCredentials")
    }

    func testBundledFallbackUnknownKeyReturnsDefault() {
        let registry = BundledFallbackRegistry.shared
        let info = registry.info(for: "NONEXISTENT_KEY_123")
        XCTAssertEqual(info.key, "UNKNOWN_900_Unknown")
    }

    func testVersionIsNotEmpty() {
        let registry = BundledFallbackRegistry.shared
        XCTAssertFalse(registry.version.isEmpty)
    }

    // MARK: - ErrorRegistry (from JSON String)

    func testInitFromJSONString() throws {
        let json = """
        {
          "version": "1.0.0",
          "lastUpdated": "2026-08-18T00:00:00Z",
          "defaults": {
            "title": "Error",
            "message": "Something went wrong!"
          },
          "errors": [
            {
              "key": "TEST_001_Custom",
              "domain": "TEST",
              "statusCodes": [400],
              "title": "Test Error",
              "message": "This is a custom test error."
            }
          ]
        }
        """
        let registry = try ErrorRegistry(jsonString: json)
        let info = registry.info(for: "TEST_001_Custom")
        XCTAssertEqual(info.key, "TEST_001_Custom")
        XCTAssertEqual(info.title, "Test Error")
        XCTAssertEqual(info.message, "This is a custom test error.")
    }

    func testInitFromInvalidJSONThrows() {
        XCTAssertThrowsError(try ErrorRegistry(jsonString: "not valid json"))
    }

    // MARK: - ErrorRegistry (Status Code Mapping)

    func testStatusCodeMappingByDomain() throws {
        let json = """
        {
          "version": "1.0.0",
          "lastUpdated": "2026-08-18T00:00:00Z",
          "defaults": {
            "title": "Error",
            "message": "Default"
          },
          "errors": [
            {
              "key": "LOGIN_001_BadCredentials",
              "domain": "LOGIN",
              "statusCodes": [401, 403],
              "title": "Invalid Credentials",
              "message": "Bad login"
            },
            {
              "key": "HTTP_401_Unauthorized",
              "domain": "NETWORK",
              "statusCodes": [401],
              "title": "Session Expired",
              "message": "Please sign in"
            }
          ]
        }
        """
        let registry = try ErrorRegistry(jsonString: json)

        // Domain-specific match
        let loginInfo = registry.info(forStatusCode: 401, domain: "LOGIN")
        XCTAssertEqual(loginInfo.key, "LOGIN_001_BadCredentials")

        // Non-domain specific match falls back to any entry with that status
        let networkInfo = registry.info(forStatusCode: 401, domain: "NETWORK")
        XCTAssertEqual(networkInfo.key, "HTTP_401_Unauthorized")
    }

    func testStatusCodeMappingUnknownStatus() throws {
        let json = """
        {
          "version": "1.0.0",
          "lastUpdated": "2026-08-18T00:00:00Z",
          "defaults": {
            "title": "Error",
            "message": "Default message"
          },
          "errors": []
        }
        """
        let registry = try ErrorRegistry(jsonString: json)
        let info = registry.info(forStatusCode: 999, domain: "UNKNOWN")
        XCTAssertEqual(info.key, "UNKNOWN_900_Unknown")
        XCTAssertEqual(info.message, "Default message")
    }

    // MARK: - AppError

    func testAppErrorCreation() {
        let error = AppError(
            key: "TEST_001",
            source: .app,
            domain: .login,
            title: "Test",
            message: "Test message"
        )
        XCTAssertEqual(error.key, "TEST_001")
        XCTAssertEqual(error.source, .app)
        XCTAssertEqual(error.domain, .login)
        XCTAssertFalse(error.id.isEmpty)
        XCTAssertFalse(error.file.isEmpty)
        XCTAssertFalse(error.function.isEmpty)
    }

    func testAppErrorLogDescriptionContainsKey() {
        let error = AppError(
            key: "LOGIN_001",
            source: .backend,
            domain: .network,
            title: "Error",
            message: "Test"
        )
        XCTAssertTrue(error.logDescription.contains("LOGIN_001"))
    }

    func testAppErrorUserReportKey() {
        let error = AppError(
            key: "LOGIN_001",
            source: .app,
            domain: .login,
            title: "Error",
            message: "Test"
        )
        XCTAssertTrue(error.userReportKey.hasPrefix("ERR-LOGIN_001-"))
    }

    // MARK: - ErrorDomain

    func testErrorDomainRawValues() {
        XCTAssertEqual(ErrorDomain.login.rawValue, "LOGIN")
        XCTAssertEqual(ErrorDomain.network.rawValue, "NETWORK")
        XCTAssertEqual(ErrorDomain.database.rawValue, "DB")
        XCTAssertEqual(ErrorDomain.unknown.rawValue, "UNKNOWN")
    }

    func testErrorDomainDescription() {
        XCTAssertEqual(ErrorDomain.login.description, "Login")
        XCTAssertEqual(ErrorDomain.network.description, "Network")
        XCTAssertEqual(ErrorDomain.unknown.description, "Unknown")
    }

    func testErrorDomainDecoding() throws {
        let decoder = JSONDecoder()
        let domain = try decoder.decode(ErrorDomain.self, from: Data("\"LOGIN\"".utf8))
        XCTAssertEqual(domain, .login)
    }

    // MARK: - ErrorRegistryCache (Offline-First)

    func testCacheSaveAndLoadRoundTrip() {
        let testFileName = "testCache_\(UUID().uuidString).json"
        let config = ErrorRegistryCache.Configuration(
            fileName: testFileName,
            maxRetentionDays: 30
        )
        let cache = ErrorRegistryCache(configuration: config)

        let document = ErrorRegistryDocument(
            version: "2.0.0",
            lastUpdated: ISO8601DateFormatter().string(from: Date()),
            defaults: ErrorDefaults(title: "Error", message: "Default"),
            errors: [
                ErrorInfo(key: "TEST_001", domain: "TEST", statusCodes: [400], title: "Test", message: "Test message")
            ]
        )

        // Save
        cache.save(document)
        Thread.sleep(forTimeInterval: 0.2)  // Wait for async write

        // Load
        let loaded = cache.load()
        XCTAssertNotNil(loaded, "Cached registry should load")
        XCTAssertEqual(loaded?.version, "2.0.0")
        XCTAssertEqual(loaded?.errors.first?.key, "TEST_001")

        // Cleanup
        cache.clear()
    }

    func testCacheReturnsNilWhenEmpty() {
        let testFileName = "testCache_Empty_\(UUID().uuidString).json"
        let config = ErrorRegistryCache.Configuration(
            fileName: testFileName,
            maxRetentionDays: 30
        )
        let cache = ErrorRegistryCache(configuration: config)

        let loaded = cache.load()
        XCTAssertNil(loaded, "Empty cache should return nil")
    }

    func testCacheLoadsLastKnownGood() {
        let testFileName = "testCache_LastKnown_\(UUID().uuidString).json"
        let config = ErrorRegistryCache.Configuration(
            fileName: testFileName,
            maxRetentionDays: 30
        )
        let cache = ErrorRegistryCache(configuration: config)

        // Save a "remote" document
        let document = ErrorRegistryDocument(
            version: "3.1.0",
            lastUpdated: ISO8601DateFormatter().string(from: Date()),
            defaults: ErrorDefaults(title: "Error", message: "Default"),
            errors: [
                ErrorInfo(key: "REMOTE_001", domain: "TEST", statusCodes: [], title: "Remote", message: "From remote")
            ]
        )
        cache.save(document)
        Thread.sleep(forTimeInterval: 0.2)

        // Simulate offline restart — load what was cached
        let reloadedCache = ErrorRegistryCache(configuration: config)
        let loaded = reloadedCache.load()

        XCTAssertNotNil(loaded, "Offline-first: last-known-good must load")
        XCTAssertEqual(loaded?.version, "3.1.0")
        XCTAssertEqual(loaded?.errors.first?.key, "REMOTE_001")

        // Cleanup
        reloadedCache.clear()
    }

    // MARK: - RemoteRegistryManager (Offline-First)

    func testDefaultsToBundledFallbackWhenNoRemoteURL() {
        // Configure with no remote URL — should stay bundled
        RemoteRegistryManager.shared.configure(
            .init(
                remoteURL: nil,
                autoRefreshOnReconnect: false,
                verboseLogging: false
            )
        )
        XCTAssertEqual(RemoteRegistryManager.shared.currentSource, .bundled)
        XCTAssertGreaterThan(RemoteRegistryManager.shared.currentRegistry.allErrors.count, 30)
    }

    func testConfigureLoadsFromCacheSynchronously() {
        // First, save a document to a known cache file
        let testFileName = "testManagerCache_\(UUID().uuidString).json"
        let config = ErrorRegistryCache.Configuration(
            fileName: testFileName,
            maxRetentionDays: 30
        )
        let cache = ErrorRegistryCache(configuration: config)

        let document = ErrorRegistryDocument(
            version: "5.0.0",
            lastUpdated: ISO8601DateFormatter().string(from: Date()),
            defaults: ErrorDefaults(title: "Error", message: "Default"),
            errors: [
                ErrorInfo(key: "CACHE_001", domain: "TEST", statusCodes: [], title: "Cached", message: "From cache")
            ]
        )
        cache.save(document)
        Thread.sleep(forTimeInterval: 0.2)

        // Now configure the manager with the same cache file
        RemoteRegistryManager.shared.configure(
            .init(
                remoteURL: nil,
                cacheConfiguration: config,
                autoRefreshOnReconnect: false,
                verboseLogging: false
            )
        )

        // Offline-first: should have loaded from cache synchronously
        XCTAssertEqual(RemoteRegistryManager.shared.currentSource, .cache)
        XCTAssertEqual(RemoteRegistryManager.shared.currentRegistry.version, "5.0.0")

        // Cleanup
        cache.clear()
    }

    // MARK: - Version Comparison (via ErrorRegistry)
    func testVersionedRegistryApplication() throws {
        // Simulate remote sending v2.0.0 while app has v1.0.0 cached
        let remoteJSON = """
        {
          "version": "2.0.0",
          "lastUpdated": "2026-08-18T00:00:00Z",
          "defaults": { "title": "Error", "message": "Default" },
          "errors": [
            {
              "key": "NEW_001_Added",
              "domain": "TEST",
              "statusCodes": [],
              "title": "New Error",
              "message": "Added in v2"
            }
          ]
        }
        """
        let remoteRegistry = try ErrorRegistry(jsonString: remoteJSON)

        // Old registry did NOT have this key
        let oldRegistry = BundledFallbackRegistry.shared
        let oldLookup = oldRegistry.info(for: "NEW_001_Added")
        XCTAssertEqual(oldLookup.key, "UNKNOWN_900_Unknown", "Old registry should not have the new key")

        // New registry DOES have it
        let newLookup = remoteRegistry.info(for: "NEW_001_Added")
        XCTAssertEqual(newLookup.key, "NEW_001_Added", "New registry should have the new key")
        XCTAssertEqual(newLookup.title, "New Error")
    }

    // MARK: - Codable Round Trip

    func testErrorInfoCodableRoundTrip() throws {
        let info = ErrorInfo(
            key: "TEST_001",
            domain: "TEST",
            statusCodes: [400, 401],
            title: "Test Title",
            message: "Test Message"
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(info)
        let decoded = try decoder.decode(ErrorInfo.self, from: data)

        XCTAssertEqual(decoded, info)
    }

    func testErrorRegistryDocumentCodableRoundTrip() throws {
        let document = ErrorRegistryDocument(
            version: "2.0.0",
            lastUpdated: "2026-08-18T00:00:00Z",
            defaults: ErrorDefaults(title: "Error", message: "Default"),
            errors: [
                ErrorInfo(key: "A_001", domain: "A", statusCodes: [400], title: "A", message: "A message")
            ]
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(document)
        let decoded = try decoder.decode(ErrorRegistryDocument.self, from: data)

        XCTAssertEqual(decoded.version, "2.0.0")
        XCTAssertEqual(decoded.errors.count, 1)
        XCTAssertEqual(decoded.errors.first?.key, "A_001")
    }
}