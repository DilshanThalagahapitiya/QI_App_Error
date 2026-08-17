//
//  ErrorRegistry.swift
//  ErrorRegistryKit
//
//  Created by Dilshan Thalagahapitiya on 2026-08-18.
//

import Foundation

/// Thread-safe in-memory error registry.
///
/// This is the concrete implementation that the app's `ErrorHandler` uses.
/// It is initialized with an `ErrorRegistryDocument` (either from bundled
/// fallback JSON or from a remote fetch), and provides key/status-code lookups.
public final class ErrorRegistry: ErrorRegistryProviding, @unchecked Sendable {

    // MARK: - Private
    private let document: ErrorRegistryDocument
    private var keyLookup: [String: ErrorInfo] = [:]
    private var statusLookup: [String: [ErrorInfo]] = [:]

    // MARK: - Public
    public var version: String { document.version }
    public var allErrors: [ErrorInfo] { document.errors }

    /// The default error used when no match is found.
    public var defaultErrorInfo: ErrorInfo {
        ErrorInfo(
            key: "UNKNOWN_900_Unknown",
            domain: ErrorDomain.unknown.rawValue,
            statusCodes: [],
            title: document.defaults.title,
            message: document.defaults.message
        )
    }

    // MARK: - Init
    public init(document: ErrorRegistryDocument) {
        self.document = document
        buildLookupTables()
    }

    /// Convenience init from raw JSON data.
    public convenience init(jsonData: Data) throws {
        let decoder = JSONDecoder()
        let document = try decoder.decode(ErrorRegistryDocument.self, from: jsonData)
        self.init(document: document)
    }

    /// Convenience init from a JSON string.
    public convenience init(jsonString: String) throws {
        guard let data = jsonString.data(using: .utf8) else {
            throw ErrorRegistryKitError.invalidJSONString
        }
        try self.init(jsonData: data)
    }

    // MARK: - Build Lookup Tables
    private func buildLookupTables() {
        keyLookup.removeAll()
        statusLookup.removeAll()

        for error in document.errors {
            keyLookup[error.key] = error

            // Only index by status code when the error has status codes and a domain
            guard !error.statusCodes.isEmpty, !error.domain.isEmpty else { continue }

            for code in error.statusCodes {
                let statusKey = makeStatusKey(code: code, domain: error.domain)
                statusLookup[statusKey, default: []].append(error)
            }
        }
    }

    // MARK: - Protocol Conformance
    public func info(for key: String) -> ErrorInfo {
        keyLookup[key] ?? defaultErrorInfo
    }

    public func info(forStatusCode statusCode: Int, domain: String) -> ErrorInfo {
        // Exact domain + status match
        let exactKey = makeStatusKey(code: statusCode, domain: domain)
        if let matches = statusLookup[exactKey], let first = matches.first {
            return first
        }

        // Fallback: any entry matching the status code (regardless of domain)
        for error in document.errors where error.statusCodes.contains(statusCode) {
            return error
        }

        return defaultErrorInfo
    }

    // MARK: - Helpers
    private func makeStatusKey(code: Int, domain: String) -> String {
        "\(domain)|\(code)"
    }
}

// MARK: - ErrorRegistryKitError
public enum ErrorRegistryKitError: Error, LocalizedError {
    case invalidJSONString
    case invalidJSONData
    case resourceNotFound(String)
    case fetchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSONString:
            return "The JSON string could not be converted to Data."
        case .invalidJSONData:
            return "The JSON data could not be parsed into an ErrorRegistryDocument."
        case .resourceNotFound(let name):
            return "The bundled resource '\(name)' could not be found."
        case .fetchFailed(let message):
            return "Failed to fetch remote error registry: \(message)"
        }
    }
}