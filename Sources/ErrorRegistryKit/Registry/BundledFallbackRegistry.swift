//
//  BundledFallbackRegistry.swift
//  ErrorRegistryKit
//
//  Created by Dilshan Thalagahapitiya on 2026-08-18.
//

import Foundation

/// Loads the bundled `fallbackErrorRegistry.json` from the package resources.
///
/// This ensures the app always has a working registry even when:
/// - The device is offline on first launch
/// - The remote fetch fails
/// - The remote registry JSON is corrupt
public final class BundledFallbackRegistry: ErrorRegistryProviding, @unchecked Sendable {

    // MARK: - Properties
    public var version: String { registry.version }
    public var allErrors: [ErrorInfo] { registry.allErrors }

    /// The default error to use when no match is found.
    public var defaultErrorInfo: ErrorInfo { registry.defaultErrorInfo }

    private let registry: ErrorRegistry

    // MARK: - Resource Name
    private static let resourceName = "fallbackErrorRegistry"

    // MARK: - Singleton
    /// Shared instance for convenience. Loaded from bundled JSON.
    public static let shared: BundledFallbackRegistry = {
        do {
            return try BundledFallbackRegistry()
        } catch {
            // Fall back to a minimal empty registry if resource is missing
            // (should never happen in practice since the JSON is bundled)
            let emptyDocument = ErrorRegistryDocument(
                version: "0.0.0",
                lastUpdated: "",
                defaults: ErrorDefaults(title: "Error", message: "Something went wrong!"),
                errors: []
            )
            return BundledFallbackRegistry(document: emptyDocument)
        }
    }()

    // MARK: - Init
    /// Loads from the bundled JSON resource in the package.
    public init() throws {
        guard let url = Bundle.module.url(
            forResource: Self.resourceName,
            withExtension: "json"
        ) else {
            throw ErrorRegistryKitError.resourceNotFound(Self.resourceName)
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let document = try decoder.decode(ErrorRegistryDocument.self, from: data)
        self.registry = ErrorRegistry(document: document)
    }

    /// Init from an already-decoded document (used for testing & empty fallback).
    public init(document: ErrorRegistryDocument) {
        self.registry = ErrorRegistry(document: document)
    }

    // MARK: - Protocol Conformance
    public func info(for key: String) -> ErrorInfo {
        registry.info(for: key)
    }

    public func info(forStatusCode statusCode: Int, domain: String) -> ErrorInfo {
        registry.info(forStatusCode: statusCode, domain: domain)
    }
}