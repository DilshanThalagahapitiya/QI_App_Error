//
//  ErrorRegistryCache.swift
//  ErrorRegistryKit
//
//  Created by Dilshan Thalagahapitiya on 2026-08-18.
//

import Foundation

/// Versioned disk cache for the remote error registry JSON.
///
/// Caches the last successfully-fetched registry so that if the next
/// fetch fails, the app can still use the last-known-good remote data
/// instead of falling all the way back to the bundled defaults.
///
/// **IMPORTANT for offline-first:**
/// The cache is stored in `Application Support`, NOT `Caches`.
/// iOS can purge the `Caches` directory at any time (disk pressure),
/// which would break offline-first behavior. `Application Support`
/// is persistent and only removed when the app is deleted.
public final class ErrorRegistryCache: @unchecked Sendable {

    // MARK: - Configuration
    public struct Configuration: Sendable {
        public var fileName: String
        public var maxRetentionDays: Int

        public init(fileName: String = "errorRegistryCache.json", maxRetentionDays: Int = 90) {
            self.fileName = fileName
            self.maxRetentionDays = maxRetentionDays
        }
    }

    // MARK: - Properties
    private let fileManager = FileManager.default
    private let configuration: Configuration
    private let ioQueue = DispatchQueue(label: "com.crede.errorregistry.cache", qos: .utility)

    // MARK: - Init
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        purgeExpired()
    }

    // MARK: - Cache URL
    /// Uses Application Support (persistent) — NOT Caches (purgeable by iOS).
    private var cacheURL: URL? {
        guard let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        // Create the directory if needed
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        // Use a subdirectory for ErrorRegistryKit to keep things clean
        let registryDir = dir.appendingPathComponent("ErrorRegistryKit", isDirectory: true)
        try? fileManager.createDirectory(at: registryDir, withIntermediateDirectories: true)

        return registryDir.appendingPathComponent(configuration.fileName)
    }

    // MARK: - Load
    /// Loads the cached registry document, if valid and not expired.
    public func load() -> ErrorRegistryDocument? {
        ioQueue.sync {
            guard let url = cacheURL,
                  let data = try? Data(contentsOf: url) else {
                return nil
            }

            let decoder = JSONDecoder()
            guard let document = try? decoder.decode(ErrorRegistryDocument.self, from: data) else {
                // Corrupt cache — remove it and return nil
                try? fileManager.removeItem(at: url)
                return nil
            }

            // Expiry check
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: document.lastUpdated) {
                let cutoff = Date().addingTimeInterval(-Double(configuration.maxRetentionDays) * 86400)
                if date < cutoff {
                    // Expired — remove and return nil
                    try? fileManager.removeItem(at: url)
                    return nil
                }
            }

            return document
        }
    }

    // MARK: - Save
    /// Saves a registry document to disk for future use.
    public func save(_ document: ErrorRegistryDocument) {
        ioQueue.async { [weak self] in
            guard let self, let url = self.cacheURL else { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(document) else { return }
            try? data.write(to: url, options: [.atomic])
        }
    }

    // MARK: - Clear
    /// Removes the cached registry (e.g., after a corrupt-version detection).
    public func clear() {
        ioQueue.async { [weak self] in
            guard let self, let url = self.cacheURL else { return }
            try? self.fileManager.removeItem(at: url)
        }
    }

    // MARK: - Purge
    /// Removes expired cache entries. Called at init and could be called on foreground.
    public func purgeExpired() {
        ioQueue.async { [weak self] in
            guard let self, let url = self.cacheURL, let data = try? Data(contentsOf: url) else { return }

            let decoder = JSONDecoder()
            guard let document = try? decoder.decode(ErrorRegistryDocument.self, from: data) else {
                // Corrupt — remove
                try? self.fileManager.removeItem(at: url)
                return
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: document.lastUpdated) {
                let cutoff = Date().addingTimeInterval(-Double(self.configuration.maxRetentionDays) * 86400)
                if date < cutoff {
                    try? self.fileManager.removeItem(at: url)
                }
            }
        }
    }

    // MARK: - Exists
    /// Returns `true` if a cached registry exists (for debugging / source description).
    public var hasCachedRegistry: Bool {
        ioQueue.sync {
            guard let url = cacheURL else { return false }
            return fileManager.fileExists(atPath: url.path)
        }
    }
}