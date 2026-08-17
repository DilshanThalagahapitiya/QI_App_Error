//
//  AppError.swift
//  ErrorRegistryKit
//
//  Created by Dilshan Thalagahapitiya on 2026-08-18.
//

import Foundation

/// A resolved error object that the app can display to the user.
/// This is the Codable struct the app's `ErrorHandler` returns after resolving an `Error`.
public struct AppError: Error, Codable, Identifiable, Sendable {
    /// Unique identifier for this specific error occurrence
    public let id: String
    /// Error key for tracing (e.g., "LOGIN_001", "SYNC_002")
    public let key: String
    /// Source of the error — backend or app
    public let source: ErrorSource
    /// Domain/context where the error occurred
    public let domain: ErrorDomain
    /// Title shown to the user
    public let title: String
    /// User-friendly message shown to the user
    public let message: String
    /// HTTP status code if applicable
    public let statusCode: Int
    /// Original error message from backend (if any)
    public let backendMessage: String?
    /// File where the error occurred (for debugging)
    public let file: String
    /// Function where the error occurred (for debugging)
    public let function: String
    /// Timestamp of when the error occurred
    public let timestamp: Date

    public init(
        key: String,
        source: ErrorSource,
        domain: ErrorDomain,
        title: String,
        message: String,
        statusCode: Int = 0,
        backendMessage: String? = nil,
        file: String = #file,
        function: String = #function
    ) {
        self.id = UUID().uuidString
        self.key = key
        self.source = source
        self.domain = domain
        self.title = title
        self.message = message
        self.statusCode = statusCode
        self.backendMessage = backendMessage
        self.file = (file as NSString).lastPathComponent
        self.function = function
        self.timestamp = Date()
    }
}

// MARK: - AppError + Logging
extension AppError {
    /// Formatted log string for debugging
    public var logDescription: String {
        """
        ╔══════════════════════════════════════════════════════
        ║ [\(key)] \(domain.description) Error
        ║ Source      : \(source.rawValue)
        ║ Title       : \(title)
        ║ Message     : \(message)
        ║ Status Code : \(statusCode)
        ║ File        : \(file)
        ║ Function    : \(function)
        ║ Timestamp   : \(timestamp)
        ╚══════════════════════════════════════════════════════
        """
    }

    /// Compact string for user to report to support
    public var userReportKey: String {
        return "ERR-\(key)-\(timestamp.timeIntervalSince1970)"
    }
}