//
//  ErrorDomain.swift
//  ErrorRegistryKit
//
//  Created by Dilshan Thalagahapitiya on 2026-08-18.
//

import Foundation

/// Domain/context where an error occurred.
/// Mirrors the app's `ErrorDomain` enum, kept here for the package to be self-contained.
public enum ErrorDomain: String, Codable, CaseIterable, Sendable {
    case login = "LOGIN"
    case sync = "SYNC"
    case tokenRefresh = "TOKEN"
    case tenant = "TENANT"
    case user = "USER"
    case role = "ROLE"
    case auditUpload = "UPLOAD"
    case auditConfig = "CONFIG"
    case questionFetch = "QUESTIONS"
    case network = "NETWORK"
    case database = "DB"
    case imageUpload = "IMAGE"
    case unknown = "UNKNOWN"

    public var description: String {
        switch self {
        case .login: return "Login"
        case .sync: return "Data Sync"
        case .tokenRefresh: return "Token Refresh"
        case .tenant: return "Tenant Info"
        case .user: return "User Info"
        case .role: return "User Role"
        case .auditUpload: return "Audit Upload"
        case .auditConfig: return "Audit Config"
        case .questionFetch: return "Question Fetch"
        case .network: return "Network"
        case .database: return "Database"
        case .imageUpload: return "Image Upload"
        case .unknown: return "Unknown"
        }
    }
}

/// Source of the error — backend or app.
public enum ErrorSource: String, Codable, Sendable {
    case backend = "Backend"
    case app = "App"
}