//
//  ErrorRegistryProviding.swift
//  ErrorRegistryKit
//
//  Created by Dilshan Thalagahapitiya on 2026-08-18.
//

import Foundation

/// Protocol that any error registry implementation must conform to.
///
/// This abstraction allows `ErrorHandler` to work with either the bundled
/// fallback registry or a remote-fetched registry without knowing the source.
public protocol ErrorRegistryProviding: Sendable {
    /// Look up error info by its unique key.
    /// - Parameter key: Error key (e.g., "LOGIN_001_BadCredentials")
    /// - Returns: Matching `ErrorInfo`, or `defaults` converted to `ErrorInfo` if not found.
    func info(for key: String) -> ErrorInfo

    /// Look up error info by HTTP status code and domain.
    /// - Parameters:
    ///   - statusCode: HTTP status code (e.g., 401, 500)
    ///   - domain: Domain raw value (e.g., "LOGIN", "NETWORK")
    /// - Returns: First matching `ErrorInfo` whose `statusCodes` contains `statusCode`
    ///            and whose `domain` matches, or `defaults` if not found.
    func info(forStatusCode statusCode: Int, domain: String) -> ErrorInfo
    
    /// Returns all error definitions currently loaded.
    var allErrors: [ErrorInfo] { get }
    
    /// The current registry document version (e.g., "1.0.0").
    var version: String { get }
}