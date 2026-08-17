# ErrorRegistryKit

A self-contained Swift Package that provides a **remotely-updatable error registry** for the QI Audit iOS app.

> **Why this exists:** The old `ErrorRegistry.swift` was compiled directly into the app, meaning every message/key change required an App Store release. This package moves the registry to **remote JSON data**, so updating error messages can be done **without releasing a new build**.

---

## 📦 Features

| Feature | Description |
|---|---|
| **Offline-First** ⭐ | App launch → load last-known-good **from disk cache instantly** (no network needed). Fetches latest in background when online |
| **Auto-refresh on reconnect** | Uses `NWPathMonitor` — when the device comes back online, automatically fetches the latest registry |
| **Remote JSON registry** | Fetch error definitions from any HTTPS URL (your backend, S3/CloudFront, Firebase) |
| **Bundled fallback** | Ships with `fallbackErrorRegistry.json` so the app always works on first launch / no cache |
| **Last-known-good cache** | Stored in **Application Support** (persistent, NOT purgeable Caches) |
| **Rate-limited fetch** | Minimum fetch interval (default 1 hour) prevents hammering the server |
| **Semantic versioning** | Only applies a remote registry if its version is **newer** than the current one |
| **Domain + status-code mapping** | Look up errors by key, or by HTTP status code + domain (e.g., 401 + LOGIN → Invalid Credentials) |
| **Codable models** | `ErrorInfo`, `ErrorRegistryDocument`, `AppError` are fully Codable |
| **Swift concurrency** | Async fetch (`await fetcher.fetch(from:)`) |

---

## 🏗 Package Structure

```
Error_Reg_Package/
├── Package.swift
├── Sources/
│   └── ErrorRegistryKit/
│       ├── Models/
│       │   ├── ErrorInfo.swift           # Codable error definition
│       │   ├── ErrorDomain.swift         # Domain + Source enums
│       │   └── AppError.swift            # Resolved error model
│       ├── Protocol/
│       │   └── ErrorRegistryProviding.swift
│       ├── Registry/
│       │   ├── ErrorRegistry.swift       # Thread-safe in-memory registry
│       │   ├── BundledFallbackRegistry.swift
│       │   └── RemoteRegistryManager.swift  # Coordinator (fetch → cache → fallback)
│       ├── Service/
│       │   ├── ErrorRegistryFetcher.swift  # URLSession remote fetch
│       │   └── ErrorRegistryCache.swift    # Versioned disk cache
│       └── Resources/
│           └── fallbackErrorRegistry.json  # All 38 errors (bundled)
└── Tests/
    └── ErrorRegistryKitTests/
        └── ErrorRegistryKitTests.swift
```

---

## 🚀 Upload to Your Git Repository (Bitbucket)

Your project already uses **Bitbucket** (`bitbucket.org/cpanditha/crede_saas_qi_audit.git`).

### Step 1 — Create a new private repository

1. Go to **Bitbucket** → **Create repository**
2. Name: `error-registry-kit` (or `ErrorRegistryKit`)
3. Access level: **Private**
4. Leave "README" unchecked (we already have one)

### Step 2 — Initialize, commit, push

Run these commands from your terminal:

```bash
cd Error_Reg_Package

# Initialize git (if not already a repo)
git init

# Add all files
git add .
git commit -m "feat: Initial ErrorRegistryKit package

- Remote JSON error registry with bundled fallback
- Domain + status-code lookup
- Versioned caching
- Unit tests"

# Add your Bitbucket remote (REPLACE with your actual repo URL)
git remote add origin https://dilshanthalagahapitiya11@bitbucket.org/cpanditha/error-registry-kit.git

# Tag the release (semantic versioning)
git tag 1.0.0

# Push
git branch -M main
git push -u origin main --tags
```

### Step 3 — Future updates (new error messages / new keys)

1. Edit `Sources/ErrorRegistryKit/Resources/fallbackErrorRegistry.json`
2. Bump the version (`"version": "1.1.0"`)
3. Commit + tag + push:
   ```bash
   git add .
   git commit -m "feat: add new error keys"
   git tag 1.1.0
   git push origin main --tags
   ```

---

## 🔧 Add to Your QI Audit App (Xcode)

### Method 1 — Xcode GUI (easiest)

1. Open `CredeQIAudit.xcodeproj` in Xcode
2. Select your app target → **General** tab
3. Scroll to **Frameworks, Libraries, and Embedded Content**
4. Click **+** → **Add Other...** → **Add Package Dependency...**
5. Paste your Bitbucket repo URL:
   ```
   https://dilshanthalagahapitiya11@bitbucket.org/cpanditha/error-registry-kit.git
   ```
6. **Dependency Rule:** `Up to Next Major Version` from `1.0.0`
7. Click **Add Package**
8. When prompted, select the **ErrorRegistryKit** library product
9. Click **Add Package**

### Method 2 — File → Add Packages

1. In Xcode: **File → Add Packages…**
2. Paste the Bitbucket URL
3. Select `ErrorRegistryKit`
4. Click **Add Package**

---

## 🏝 Offline-First Design

Because QI Audit is used by field auditors **without internet**, the registry follows this flow:

```
┌─────────────────────────────────────────────────────────────────────┐
│                       APP LAUNCH (OFFLINE-FIRST)                    │
│                                                                     │
│  AppDelegate.configureErrorRegistry()                               │
│      │                                                              │
│      ▼                                                              │
│  1. LOAD FROM DISK CACHE (synchronous, instant)                     │
│      ├── Cache exists?  → Use last-known-good remote registry       │
│      │                    (app works offline immediately)           │
│      └── No cache?      → Use bundled fallback (first launch)       │
│                                                                     │
│  2. BACKGROUND TASK: updateIfNeeded()                               │
│      ├── Network connected?                                         │
│      │    ├── Rate limit elapsed (default 1hr)?                     │
│      │    │    ├── YES → Fetch latest from server                   │
│      │    │    │         ├── ✅ Newer version? → Apply + cache      │
│      │    │    │         └── ❌ Older/equal → Keep current          │
│      │    │    └── NO  → Skip (respect rate limit)                  │
│      │    └── Not connected → Skip (use cache until reconnect)      │
│      └── Register NWPathMonitor for reconnect                       │
│                                                                     │
│  3. NETWORK RECONNECTS (mid-session)                                │
│      └── NWPathMonitor fires → auto-fetch latest registry           │
│                                                                     │
│  4. NEXT LAUNCH (offline again)                                     │
│      └── Loads the NEW cached registry (updated from prior fetch)   │
└─────────────────────────────────────────────────────────────────────┘
```

### Offline guarantees

| Scenario | Registry used | Reason |
|---|---|---|
| First launch (offline) | **Bundled fallback** | No cache exists yet |
| Second launch (offline) | **Cached registry** | Last-known-good from previous online session |
| Online launch (rate-limit elapsed) | **Remote fetched registry** → cached | Fresh data applied + saved for next offline use |
| Online launch (within rate limit) | **Cached registry** | Avoids server hammering |
| Network drops mid-fetch | **Cached registry** | Fetch fails gracefully, keeps current |
| Network reconnects mid-session | **Remote fetched registry** → cached | Auto-refresh via NWPathMonitor |

---

## 💻 Integrating Into Your Code

### Step 1 — Add `import ErrorRegistryKit`

Add `import ErrorRegistryKit` to `ErrorHandler.swift`, `CredeQIAuditApp.swift`, and `BaseVM.swift`.

### Step 2 — Remove the old static registry

Delete `CredeQIAudit/Services/ErrorHandling/ErrorRegistry.swift` from the app target (right-click → Delete → Move to Trash).

### Step 3 — Configure the registry at launch

In `CredeQIAuditApp.swift` (`AppDelegate.didFinishLaunchingWithOptions`), add:

```swift
import ErrorRegistryKit

// MARK: - Configure Remote Error Registry (Offline-First)
private func configureErrorRegistry() {
    let remoteURL = URL(string: ConfigSettings.baseURL + "/api/error-registry")

    // Configure loads the cached registry SYNCHRONOUSLY.
    // By the time this returns, the app already has the best available
    // registry — even if the user is offline.
    RemoteRegistryManager.shared.configure(
        .init(
            remoteURL: remoteURL,
            fetcherConfiguration: .init(timeoutInterval: 20, bearerToken: nil),
            cacheConfiguration: .init(fileName: "errorRegistryCache.json", maxRetentionDays: 90),
            minimumFetchInterval: 3600,       // 1 hour rate limit
            autoRefreshOnReconnect: true,      // auto-fetch when network returns
            verboseLogging: true
        )
    )

    // Fetch latest in background — does NOT block first frame.
    // The app is already using the cached/bundled registry right now.
    Task {
        await RemoteRegistryManager.shared.updateIfNeeded()
        print("📋 [ErrorRegistry] Source: \(RemoteRegistryManager.shared.sourceDescription())")
    }
}
```

Call it from `didFinishLaunchingWithOptions` **before the first view renders**:

```swift
func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    FirebaseApp.configure()
    configureCloudWatchRUM()
    configureErrorRegistry()   // ← ADD THIS — loads cached registry synchronously
    return true
}
```

> **How `configure()` works offline-first:**
> 1. It synchronously reads `errorRegistryCache.json` from Application Support
> 2. If valid, it sets `currentRegistry` to that cached registry — **no network needed**
> 3. Only if no cache exists (first launch) does it fall back to bundled JSON
> 4. The `Task` above then fetches the latest from the server **in the background**,
>    applies + caches it if the version is newer
> 5. `NWPathMonitor` auto-refreshes whenever the device reconnects to the internet

### Step 4 — Refactor `ErrorHandler`

Replace every `ErrorRegistry.xxx` reference with a lookup against the manager's current registry:

```swift
import ErrorRegistryKit

final class ErrorHandler {

    static let shared = ErrorHandler()
    private init() {}

    /// The active registry — set by RemoteRegistryManager at launch.
    var registry: ErrorRegistryProviding = BundledFallbackRegistry.shared

    // MARK: - Old references → New lookups

    // OLD: let info = ErrorRegistry.unknownError
    // NEW:
    private var unknownError: ErrorInfo {
        registry.info(for: "UNKNOWN_900_Unknown")
    }

    private var networkConnectionLost: ErrorInfo {
        registry.info(for: "NETWORK_103_ConnectionLost")
    }

    private var networkNoInternet: ErrorInfo {
        registry.info(for: "NETWORK_101_NoInternet")
    }

    private var networkTimeout: ErrorInfo {
        registry.info(for: "NETWORK_102_Timeout")
    }

    private var networkServerUnavailable: ErrorInfo {
        registry.info(for: "NETWORK_104_ServerUnavailable")
    }

    private var decodingFailed: ErrorInfo {
        registry.info(for: "UNKNOWN_901_DecodingFailed")
    }

    private var loginBadCredentials: ErrorInfo {
        registry.info(for: "LOGIN_001_BadCredentials")
    }

    private var loginPasswordResetRequired: ErrorInfo {
        registry.info(for: "LOGIN_002_PasswordResetRequired")
    }

    private var httpBadRequest: ErrorInfo {
        registry.info(for: "HTTP_400_BadRequest")
    }

    private var httpUnauthorized: ErrorInfo {
        registry.info(for: "HTTP_401_Unauthorized")
    }

    private var httpNotFound: ErrorInfo {
        registry.info(for: "HTTP_404_NotFound")
    }

    private var httpTimeout: ErrorInfo {
        registry.info(for: "HTTP_408_Timeout")
    }

    private var httpTooManyRequests: ErrorInfo {
        registry.info(for: "HTTP_429_TooManyRequests")
    }

    private var httpPasswordResetRequired: ErrorInfo {
        registry.info(for: "HTTP_460_PasswordResetRequired")
    }

    private var httpServerError: ErrorInfo {
        registry.info(for: "HTTP_500_ServerError")
    }

    private var httpServiceUnavailable: ErrorInfo {
        registry.info(for: "HTTP_503_ServiceUnavailable")
    }

    // MARK: - Status-code mapping now uses the registry protocol

    private func info(forStatusCode statusCode: Int, domain: ErrorDomain, backendMessage: String) -> ErrorInfo {
        // Check for known backend messages first
        if backendMessage == String.NoInternetConnection {
            return networkNoInternet
        }
        if backendMessage == "Password reset required before first login." {
            return loginPasswordResetRequired
        }

        if domain == .login {
            switch statusCode {
            case 401, 403:
                return loginBadCredentials
            case 460:
                return httpPasswordResetRequired
            default:
                break
            }
        }

        return registry.info(forStatusCode: statusCode, domain: domain.rawValue)
    }
}
```

### Step 5 — (Optional) Update `AppError` to use the package model

The package ships with its own `AppError`. To avoid a naming conflict, you can either:

- **Option A:** Keep the app's `AppError.swift` and wrap the package model (recommended — less churn)
- **Option B:** Delete the app's `AppError.swift` and use the package's `AppError` (requires updating `ErrorLog.swift`, `ErrorLogManager.swift`, etc. with `import ErrorRegistryKit`)

---

## 🧪 Run the Tests

From the terminal, inside `Error_Reg_Package/`:

```bash
swift test
```

Expected output:

```
Test Suite 'ErrorRegistryKitTests' passed
Executed 23 tests, with 0 failures
```

---

## 🔄 Updating Errors Without a New Build

### If using a backend endpoint (`/api/error-registry`)

Your backend serves a JSON document shaped like `fallbackErrorRegistry.json`:

```json
{
  "version": "1.1.0",
  "lastUpdated": "2026-08-19T00:00:00Z",
  "defaults": { "title": "Error", "message": "An unexpected error occurred." },
  "errors": [
    { "key": "LOGIN_001_BadCredentials", "domain": "LOGIN", "statusCodes": [401, 403], "title": "Invalid Credentials", "message": "The username or password you have entered is invalid." }
  ]
}
```

**To update:** change the JSON on the server → users see the new messages on next app launch. ✅ No build needed.

### If using Firebase Remote Config

1. In Firebase Console → **Remote Config**
2. Add a parameter named `error_registry`
3. Value: the full JSON string (same schema as above)
4. **Fetch interval:** set to `3600` (1 hour minimum fetch interval) to avoid throttling
5. In the app, use `RemoteConfig.remoteConfig().configValue(forKey: "error_registry").stringValue` as an alternative data source

---

## 🛡 Security

- Use **HTTPS** for the remote registry URL
- Optionally pass a `bearerToken` to `ErrorRegistryFetcher.Configuration` for authenticated endpoints
- The bundled JSON contains no sensitive data — only error titles/messages

---

## 📄 License

Private — for use by the QI Audit project team only.