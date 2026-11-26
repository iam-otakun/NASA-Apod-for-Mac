//
//  Settings.swift
//  NASA APOD
//
//  Launch-at-login, carried over from BingWallpaper's Settings: the
//  modern SMAppService registration first (with the unregister-first
//  refresh that keeps duplicate Login Items entries from piling up),
//  a per-user LaunchAgent as fallback for ad-hoc signed copies.
//  The archive folder is NOT kept here — it lives in
//  ~/.nasa-apod.conf, the file shared with the plugin and the
//  Windows app (see ApodService).
//

import Foundation
import ServiceManagement
import OSLog

private let logger = Logger(
    subsystem: Logging.subsystem,
    category: Logging.Category.Settings.rawValue
)

public class Settings {
    private let defaults = UserDefaults.standard

    public init() {
        migrateLegacyLoginItemIfNeeded()
    }

    /// `true` when the user's intent is "launch at login enabled".
    ///
    /// On macOS 15+/26 the system frequently keeps a freshly registered
    /// login item in `.requiresApproval` until the user confirms it in
    /// System Settings → General → Login Items. We treat that as "on"
    /// so the checkbox doesn't snap back to off the instant the user
    /// toggles it.
    var launchAtLogin: Bool {
        if LaunchAgentLoginItem.isEnabled {
            return true
        }
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    /// `true` when the login item is registered but waiting for the
    /// user to approve it in System Settings.
    var launchAtLoginRequiresApproval: Bool {
        return SMAppService.mainApp.status == .requiresApproval
    }

    /// Register or unregister the main app as a login item. Throws on
    /// failure so the caller can surface the error to the user.
    ///
    /// `SMAppService` registration can fail for self-built / ad-hoc
    /// signed copies of the app, so on failure we fall back to a
    /// per-user LaunchAgent, which provides the same behaviour.
    func setLaunchAtLogin(_ newValue: Bool) throws {
        do {
            if newValue {
                // Refresh this copy's registration first: a plain
                // register() on an already registered copy can leave a
                // stale duplicate entry behind in Login Items.
                try? SMAppService.mainApp.unregister()
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            // The modern path worked; make sure no fallback agent lingers.
            try? LaunchAgentLoginItem.setEnabled(false)
        } catch {
            let actionString = newValue ? "register" : "unregister"
            logger.error("Failed to \(actionString, privacy: .public) login item with error: \(String(describing: error), privacy: .public). Falling back to LaunchAgent.")
            do {
                try LaunchAgentLoginItem.setEnabled(newValue)
            } catch {
                throw error
            }
        }
    }

    private func migrateLegacyLoginItemIfNeeded() {
        guard defaults.object(forKey: Settings.SM_LOGIN_ENABLED_LEGACY) != nil else { return }
        let wasEnabled = defaults.bool(forKey: Settings.SM_LOGIN_ENABLED_LEGACY)
        defaults.removeObject(forKey: Settings.SM_LOGIN_ENABLED_LEGACY)
        if wasEnabled, SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
    }

    private static let SM_LOGIN_ENABLED_LEGACY = "SM_LOGIN_ENABLED"
}

/// Fallback launch-at-login via a per-user LaunchAgent, used when
/// `SMAppService` registration fails (notably for self-built, ad-hoc
/// signed copies of the app).
enum LaunchAgentLoginItem {
    private static var plistURL: URL {
        let label = Bundle.main.bundleIdentifier ?? "com.otakun.NASAApod"
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).launch.plist")
    }

    static var isEnabled: Bool {
        return FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard let executablePath = Bundle.main.executablePath else {
                throw NSError(domain: "LaunchAgentLoginItem", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not locate the app executable"])
            }
            let label = Bundle.main.bundleIdentifier ?? "com.otakun.NASAApod"
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executablePath],
                "RunAtLoad": true
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: plistURL, options: .atomic)
        } else if isEnabled {
            try FileManager.default.removeItem(at: plistURL)
        }
    }
}
