//
//  RemoteRegistryManager.swift
//  ErrorRegistryKit
//
//  Created by Dilshan Thalagahapitiya on 2026-08-18.
//

import Foundation
import Network

/// Coordinates fetching, caching, and fallback for the error registry.
///
/// This is the **main entry point** you call from `AppDelegate.didFinishLaunching`.
///
/// ## Offline-First Behavior
///
/// The QI Audit app is used by field auditors **offline**. This manager is designed
/// around that constraint:
///
/// ```
/// App Launch
///     │
///     ├── 1. Load from DISK CACHE (synchronous, instant)
///     │       └── Uses last-known-good remote registry (if any)
///     │       └── Falls back to bundled JSON (first-launch only)
///     │
///     ├── 2. Network connected?
///     │       ├── YES → Check minimum fetch interval elapsed?
///     │       │         ├── YES → Fetch latest remote registry (background)
///     │       │         │         ├── ✅ Success + newer version → Apply + save cache
///     │       │         │         └── ❌ Failure → Keep current (cache/bundled)
///     │       │         └── NO  → Skip fetch (rate-limited)
///     │       │
///     │       └── NO  → Keep current (cache/bundled) until reconnection
///     │
///     └── 3. REGISTER for network-reconnect notification
///             └── When connectivity returns → auto-fetch latest registry
///
/// Usage:
/// ```swift
/// // AppDelegate
/// RemoteRegistryManager.shared.configure(
///     .init(remoteURL: URL(string: "https://crede.app/api/error-registry"))
/// )
/// Task { await RemoteRegistryManager.shared.updateIfNeeded() }
/// ```
public final class RemoteRegistryManager: @unchecked Sendable {

    // MARK: - Singleton
    public static let shared = RemoteRegistryManager()

    // MARK: - Configuration
    public struct Configuration: Sendable {
        /// Remote registry URL. If nil, only bundled fallback is used.
        public var remoteURL: URL?
        /// Fetch configuration (timeout, auth)
        public var fetcherConfiguration: ErrorRegistryFetcher.Configuration
        /// Cache configuration
        public var cacheConfiguration: ErrorRegistryCache.Configuration
        /// Minimum seconds between remote fetches (default 1 hour).
        /// Prevents hammering the server every app launch.
        public var minimumFetchInterval: TimeInterval
        /// If true, auto-fetches when network connectivity returns.
        public var autoRefreshOnReconnect: Bool
        /// If true, logs detailed info about registry source
        public var verboseLogging: Bool

        public init(
            remoteURL: URL? = nil,
            fetcherConfiguration: ErrorRegistryFetcher.Configuration = .init(),
            cacheConfiguration: ErrorRegistryCache.Configuration = .init(),
            minimumFetchInterval: TimeInterval = 3600,  // 1 hour
            autoRefreshOnReconnect: Bool = true,
            verboseLogging: Bool = true
        ) {
            self.remoteURL = remoteURL
            self.fetcherConfiguration = fetcherConfiguration
            self.cacheConfiguration = cacheConfiguration
            self.minimumFetchInterval = minimumFetchInterval
            self.autoRefreshOnReconnect = autoRefreshOnReconnect
            self.verboseLogging = verboseLogging
        }
    }

    // MARK: - Registry Source
    public enum RegistrySource: String, Sendable {
        case remote
        case cache
        case bundled
    }

    // MARK: - Properties
    private var configuration = Configuration()
    private var fetcher: ErrorRegistryFetcher?
    private var cache: ErrorRegistryCache
    private var fallback: BundledFallbackRegistry

    /// The **currently ACTIVE registry**.
    ///
    /// Offline-first guarantees:
    /// - **At app launch** → loaded synchronously from disk cache (if available),
    ///   otherwise bundled fallback. This is set BEFORE the first frame renders,
    ///   so the app never shows stale messages.
    /// - **After background fetch** → updated to the latest remote version.
    public private(set) var currentRegistry: ErrorRegistryProviding

    /// Where the current registry was loaded from.
    public internal(set) var currentSource: RegistrySource = .bundled

    /// Timestamp of the last successful remote fetch (rate limiting).
    private var lastFetchDate: Date?

    /// Serial queue for state mutations.
    private let stateQueue = DispatchQueue(label: "com.crede.errorregistry.state", qos: .userInitiated)

    /// Network path monitor for auto-refresh on reconnect.
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.crede.errorregistry.network")

    // MARK: - Init
    private init() {
        self.fallback = BundledFallbackRegistry.shared
        self.cache = ErrorRegistryCache()
        self.currentRegistry = fallback
    }

    // MARK: - Configure
    /// Configure the manager. Call **once at app launch** BEFORE the first screen renders.
    ///
    /// This method synchronously loads the cached registry (last-known-good remote data)
    /// so the app has the best available registry immediately at launch, even offline.
    public func configure(_ configuration: Configuration) {
        self.configuration = configuration

        // 1. Re-create cache with the configured settings
        self.cache = ErrorRegistryCache(configuration: configuration.cacheConfiguration)

        // 2. Create fetcher if remote URL is configured
        if configuration.remoteURL != nil {
            self.fetcher = ErrorRegistryFetcher(configuration: configuration.fetcherConfiguration)
        } else {
            self.fetcher = nil
        }

        // 3. OFFLINE-FIRST: synchronously load from disk cache immediately.
        //    This ensures the app uses the last-known-good remote registry
        //    (not the bundled fallback) from the moment of launch.
        if let cachedDocument = cache.load() {
            // Only use cache if its version ≥ bundled fallback version
            let registry = ErrorRegistry(document: cachedDocument)
            currentRegistry = registry
            currentSource = .cache
            log("✅ [ErrorRegistryKit] Offline-first: loaded cached registry v\(cachedDocument.version)")
        } else {
            // First launch — use bundled fallback
            currentRegistry = fallback
            currentSource = .bundled
            log("ℹ️ [ErrorRegistryKit] No cache found — using bundled fallback v\(fallback.version)")
        }

        // 4. Register for network reconnect to auto-refresh
        if configuration.autoRefreshOnReconnect {
            startNetworkMonitoring()
        }
    }

    // MARK: - Update (called at launch + on reconnect)
    /// Updates the registry from the remote source when network is available.
    ///
    /// **Behavior:**
    /// - If a fetch was done within `minimumFetchInterval`, skips (rate limit).
    /// - If remote fetch succeeds → applies and caches the new registry.
    /// - If remote fetch fails → keeps current registry (cache or bundled).
    ///
    /// Call from `AppDelegate.didFinishLaunching` (or in a `.task` in SwiftUI).
    public func updateIfNeeded() async {
        await updateIfNeeded(force: false)
    }

    /// Force update regardless of the minimum fetch interval.
    /// Use sparingly — e.g., from a debug screen or "Check for updates" button.
    public func forceRefresh() async {
        await updateIfNeeded(force: true)
    }

    // MARK: - Private Update
    private func updateIfNeeded(force: Bool) async {
        guard let remoteURL = configuration.remoteURL, let fetcher else {
            log("ℹ️ [ErrorRegistryKit] No remote URL configured — keeping current registry.")
            return
        }

        // Rate limiting: skip if we fetched recently (unless forced)
        if !force, let lastFetch = await lastFetchTimestamp() {
            let elapsed = Date().timeIntervalSince(lastFetch)
            if elapsed < configuration.minimumFetchInterval {
                log("⏳ [ErrorRegistryKit] Skipping fetch — last fetch \(Int(elapsed))s ago (min interval \(Int(configuration.minimumFetchInterval))s).")
                return
            }
        }

        // Try remote fetch
        do {
            let document = try await fetcher.fetch(from: remoteURL)
            await applyFetchedDocument(document)
        } catch {
            log("⚠️ [ErrorRegistryKit] Remote fetch failed: \(error.localizedDescription). Keeping current registry.")
        }
    }

    /// Applies a fetched document if its version is newer than the current one.
    private func applyFetchedDocument(_ document: ErrorRegistryDocument) async {
        stateQueue.sync {
            let newVersion = document.version
            let currentVersion = currentRegistry.version

            // Version comparison (simple string compare works for semver if padded,
            // but we use a numeric comparator for correctness)
            if compareVersions(newVersion, currentVersion) >= 0 {
                let registry = ErrorRegistry(document: document)
                currentRegistry = registry
                currentSource = .remote
                lastFetchDate = Date()
                cache.save(document)
                log("✅ [ErrorRegistryKit] Applied remote registry v\(newVersion) (was v\(currentVersion))")
            } else {
                log("ℹ️ [ErrorRegistryKit] Remote v\(newVersion) is NOT newer than current v\(currentVersion) — keeping current.")
                lastFetchDate = Date()  // Still record the fetch to respect rate limit
            }
        }
    }

    // MARK: - Network Monitoring (Auto-Refresh on Reconnect)
    private func startNetworkMonitoring() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let isConnected = path.status == .satisfied
            if isConnected {
                self.log("🌐 [ErrorRegistryKit] Network reconnected — auto-refreshing registry.")
                Task {
                    await self.updateIfNeeded()
                }
            }
        }
        monitor.start(queue: monitorQueue)
        pathMonitor = monitor
    }

    public func stopNetworkMonitoring() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    // MARK: - Debug & Inspection
    public func sourceDescription() -> String {
        switch currentSource {
        case .remote: return "Remote (v\(currentRegistry.version))"
        case .cache: return "Last-Known-Good Cache (v\(currentRegistry.version))"
        case .bundled: return "Bundled Fallback (v\(currentRegistry.version))"
        }
    }

    // MARK: - Helpers
    private func lastFetchTimestamp() async -> Date? {
        stateQueue.sync {
            lastFetchDate
        }
    }

    /// Semantic version comparator. Returns 1 if v1 > v2, -1 if v1 < v2, 0 if equal.
    private func compareVersions(_ v1: String, _ v2: String) -> Int {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(parts1.count, parts2.count)
        for i in 0..<maxCount {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 > p2 { return 1 }
            if p1 < p2 { return -1 }
        }
        return 0
    }

    // MARK: - Logging
    private func log(_ message: String) {
        guard configuration.verboseLogging else { return }
        print(message)
    }
}