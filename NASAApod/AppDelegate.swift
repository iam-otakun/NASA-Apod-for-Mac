//
//  AppDelegate.swift
//  NASA APOD
//
//  A menu-bar-only app (LSUIElement): AppDelegate wires the
//  service, the menu and the two programmatic windows together.
//  Launch behaviour follows the house rule from BingWallpaper
//  0.8.0: a login-item launch stays silent in the menu bar; only a
//  launch the user started shows the Settings window.
//

import Cocoa

/// Explicit entry point: create the delegate, hand it to the
/// shared application and run. (The `@main`-on-the-delegate
/// synthesis left the delegate unwired in this storyboard-less
/// setup — the app ran its event loop without ever hearing
/// applicationDidFinishLaunching.)
@main
struct AppMain {
    static func main() {
        let delegate = AppDelegate()
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private let service = ApodService()
    private lazy var menuController = MenuController(service: service)
    private lazy var settingsWc = SettingsWindowController()
    private lazy var detailWc = DetailWindowController()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        menuController.onShowSettings = { [weak self] in
            self?.showSettings()
        }
        menuController.onShowDetail = { [weak self] entry in
            guard let self else { return }
            self.detailWc.present(entry: entry, preloadedImage: self.service.displayImage)
        }
        menuController.setup()

        settingsWc.onArchiveSettingsChanged = { [weak self] in
            // Re-run the fetch so today lands in the new folder too;
            // existing files are skipped, so this stays cheap.
            self?.service.refresh()
        }

        service.start()

        if launchedAsLoginItem == false {
            showSettings()
        }

        Task {
            await AppUpdateManager.checkForUpdate()
        }
    }

    private func showSettings() {
        settingsWc.showWindow(nil)
    }

    /// `true` when macOS launched the app as a login item (the open
    /// application Apple event then carries the
    /// `keyAELaunchedAsLogInItem` parameter).
    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else {
            return false
        }
        return event.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem) != nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Activating the already running app (Dock or Finder icon
        // click) brings Settings up, like a manual launch. Becoming
        // active by itself (e.g. after a login-item launch) must not.
        if flag == false {
            showSettings()
        }
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
