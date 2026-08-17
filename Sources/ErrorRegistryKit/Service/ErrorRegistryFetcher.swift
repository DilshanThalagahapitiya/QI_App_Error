//
//  ErrorRegistryFetcher.swift
//  ErrorRegistryKit
//
//  Created by Dilshan Thalagahapitiya on 2026-08-18.
//

import Foundation

/// Fetches the error registry JSON from a remote URL.
///
/// Uses `URLSession` with a short timeout. When the fetch fails,
/// callers should fall back to the `BundledFallbackRegistry`.
public final class ErrorRegistryFetcher: @unchecked Sendable {

    // MARK: - Configuration
    public struct Configuration: Sendable {
        public var timeoutInterval: TimeInterval
        public var cachePolicy: URLRequest.CachePolicy
        /// Optional bearer token for authenticated fetch
        public var bearerToken: String?

        public init(
            timeoutInterval: TimeInterval = 20,
            cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData,
            bearerToken: String? = nil
        ) {
            self.timeoutInterval = timeoutInterval
            self.cachePolicy = cachePolicy
            self.bearerToken = bearerToken
        }
    }

    // MARK: - Properties
    private let session: URLSession
    private let configuration: Configuration

    // MARK: - Init
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = configuration.timeoutInterval
        config.timeoutIntervalForResource = configuration.timeoutInterval + 10
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    // MARK: - Fetch
    /// Fetches and decodes the remote error registry document.
    /// - Parameter url: The remote registry URL (e.g., `https://crede.app/api/error-registry`)
    /// - Returns: The decoded `ErrorRegistryDocument` on success.
    public func fetch(from url: URL) async throws -> ErrorRegistryDocument {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = configuration.cachePolicy
        request.timeoutInterval = configuration.timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = configuration.bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ErrorRegistryKitError.fetchFailed("No HTTP response")
        }

        guard (200..<300).contains(http.statusCode) else {
            throw ErrorRegistryKitError.fetchFailed("HTTP \(http.statusCode)")
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ErrorRegistryDocument.self, from: data)
        } catch {
            throw ErrorRegistryKitError.invalidJSONData
        }
    }

    // MARK: - Download Raw JSON (for caching)
    /// Downloads the raw JSON string — useful for caching to disk before decoding.
    public func downloadRawJSON(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = configuration.cachePolicy
        request.timeoutInterval = configuration.timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = configuration.bearerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw ErrorRegistryKitError.fetchFailed("Non-2xx response")
        }

        return data
    }
}