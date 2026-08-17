//
//  ErrorInfo.swift
//  ErrorRegistryKit
//
//  Created by Dilshan Thalagahapitiya on 2026-08-18.
//

import Foundation

/// A single error definition in the registry.
///
/// This is the Codable replacement for the old tuple-based `ErrorRegistry.ErrorInfo`.
/// It can be decoded directly from the remote JSON registry or the bundled fallback JSON.
public struct ErrorInfo: Codable, Equatable, Sendable {
    /// Unique error key (e.g., "LOGIN_001_BadCredentials")
    public let key: String
    /// Domain raw value (e.g., "LOGIN", "NETWORK", "UPLOAD", "DB")
    public let domain: String
    /// HTTP status codes that map to this error (empty when not status-code driven)
    public let statusCodes: [Int]
    /// Title shown to the user
    public let title: String
    /// User-friendly message shown to the user
    public let message: String

    public init(
        key: String,
        domain: String,
        statusCodes: [Int] = [],
        title: String,
        message: String
    ) {
        self.key = key
        self.domain = domain
        self.statusCodes = statusCodes
        self.title = title
        self.message = message
    }

    /// Legacy init that mirrors the old tuple shape for easy migration
    public init(key: String, title: String, message: String) {
        self.init(
            key: key,
            domain: "",
            statusCodes: [],
            title: title,
            message: message
        )
    }
}

// MARK: - ErrorRegistryDocument
/// Top-level JSON document for the error registry.
public struct ErrorRegistryDocument: Codable, Equatable, Sendable {
    /// Semantic version of this registry document (e.g., "1.0.0")
    public let version: String
    /// ISO8601 timestamp of when the registry was last updated
    public let lastUpdated: String
    /// Default title/message used when no key matches
    public let defaults: ErrorDefaults
    /// All error definitions
    public let errors: [ErrorInfo]

    public init(
        version: String,
        lastUpdated: String,
        defaults: ErrorDefaults,
        errors: [ErrorInfo]
    ) {
        self.version = version
        self.lastUpdated = lastUpdated
        self.defaults = defaults
        self.errors = errors
    }
}

// MARK: - ErrorDefaults
public struct ErrorDefaults: Codable, Equatable, Sendable {
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}