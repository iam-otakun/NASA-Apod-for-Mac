//
//  AppUpdateManager.swift
//  NASA APOD
//
//  Self-update against this app's own GitHub repository, following
//  BingWallpaper's AppUpdateManager: read the latest release tag off
//  the /releases/latest redirect, compare versions, download the
//  release's .pkg and offer to open it. While the repository has no
//  releases (or does not exist yet) the check simply finds nothing.
//

import Foundation
import AppKit
import OSLog

private let logger = Logger(
    subsystem: Logging.subsystem,
    category: Logging.Category.AppUpdate.rawValue
)

class AppUpdateManager {

    private static let githubLatestReleaseUrl = URL(string: "https://github.com/iam-otakun/NASA-Apod-for-Mac/releases/latest")!
    private static let githubExpandedAssetsPrefix = "https://github.com/iam-otakun/NASA-Apod-for-Mac/releases/expanded_assets/"
    private static let githubDomain = "https://github.com"

    static func currentAppVersion() -> String {
        return Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
    }

    static func fetchLatestAppVersionFromGithub() async -> String? {
        let latestHtmlHeaders = await DownloadManager.downloadHtmlHeaders(from: githubLatestReleaseUrl)
        guard let tag = latestHtmlHeaders?.url?.lastPathComponent,
              // A missing repository or release answers with a page
              // whose final URL is not a version tag at all.
              tag.range(of: #"^v?\d+(\.\d+)*$"#, options: .regularExpression) != nil else {
            return nil
        }
        return tag
    }

    private static func newVersionAvailable(_ currentAppVersion: String, _ latestAppVersion: String) -> Bool {
        let currentAppVersion = currentAppVersion.replacingOccurrences(of: "v", with: "")
        let latestAppVersion = latestAppVersion.replacingOccurrences(of: "v", with: "")
        return currentAppVersion.versionCompare(latestAppVersion) == .orderedAscending
    }

    static func checkForUpdate(notifyUserAboutNoNewVersion: Bool = false) async {
        guard let latestGithubAppVersion = await fetchLatestAppVersionFromGithub() else {
            logger.error("Failed to fetch latest app version from github")
            if notifyUserAboutNoNewVersion == true {
                await showUpdateCheckFailedDialog()
            }
            return
        }

        let currentAppVersion = currentAppVersion()

        if newVersionAvailable(currentAppVersion, latestGithubAppVersion) == false {
            logger.info("No app update required, \(currentAppVersion, privacy: .public) is already the newest version")

            if notifyUserAboutNoNewVersion == true {
                await showAlreadyUpToDateDialog()
            }
            return
        }

        if let pkgInstallerPathUrl = FileHandler.pkgInstallerAlreadyDownloaded(appVersion: latestGithubAppVersion) {
            if await showShouldUpdateNowDialog(currentAppVersion: currentAppVersion, latestAppVersion: latestGithubAppVersion) == true {
                NSWorkspace.shared.open(pkgInstallerPathUrl)
            }
            return
        }

        guard let pkgInstaller = await downloadLatestInstallerFromGithub(latestGithubAppVersion: latestGithubAppVersion) else {
            logger.error("Failed to download latest app installer from github")
            if notifyUserAboutNoNewVersion == true {
                await showUpdateDownloadFailedDialog()
            }
            return
        }

        guard let pkgInstallerPathUrl = FileHandler.savePkgInstallerToDisk(pkgInstaller: pkgInstaller, appVersion: latestGithubAppVersion) else {
            return
        }

        if await showShouldUpdateNowDialog(currentAppVersion: currentAppVersion, latestAppVersion: latestGithubAppVersion) == true {
            NSWorkspace.shared.open(pkgInstallerPathUrl)
        }
    }

    static func downloadLatestInstallerFromGithub(latestGithubAppVersion: String) async -> Data? {
        var githubExpandedAssetsUrl = URL(string: githubExpandedAssetsPrefix)!
        githubExpandedAssetsUrl.appendPathComponent(latestGithubAppVersion)

        guard let html = await DownloadManager.downloadHtml(from: githubExpandedAssetsUrl) else { return nil }

        guard let aHref = html.split(separator: "\n").filter({ line in line.contains(".pkg") && line.contains("/\(latestGithubAppVersion)/") }).first else {
            logger.error("Failed to extract pkg link from latest github release website")
            return nil
        }

        let newAppVersionDownloadPostfix = aHref.components(separatedBy: "href=\"").dropFirst().first!.components(separatedBy: "\"").first!

        var newAppVersionDownloadUrl = URL(string: githubDomain)!
        newAppVersionDownloadUrl.appendPathComponent(newAppVersionDownloadPostfix)

        return try? await DownloadManager.downloadBinary(from: newAppVersionDownloadUrl)
    }

    @MainActor
    private static func showShouldUpdateNowDialog(currentAppVersion: String, latestAppVersion: String) -> Bool {
        let currentAppVersion = currentAppVersion.replacingOccurrences(of: "v", with: "")
        let latestAppVersion = latestAppVersion.replacingOccurrences(of: "v", with: "")
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("New version of NASA APOD available", comment: "Alert title")
        alert.informativeText = String(format: NSLocalizedString("Do you want to update now?\nCurrent version: %@\nNew version: %@", comment: "Alert text"), currentAppVersion, latestAppVersion)
        let updateButton = alert.addButton(withTitle: NSLocalizedString("Update", comment: "Button"))
        alert.addButton(withTitle: NSLocalizedString("Later", comment: "Button"))
        alert.alertStyle = .informational

        alert.window.defaultButtonCell = updateButton.cell as? NSButtonCell

        return alert.runModal() == NSApplication.ModalResponse.alertFirstButtonReturn
    }

    @MainActor
    private static func showAlreadyUpToDateDialog() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("NASA APOD already up to date", comment: "Alert title")
        alert.informativeText = NSLocalizedString("There is no new version of NASA APOD available", comment: "Alert text")
        let updateButton = alert.addButton(withTitle: NSLocalizedString("Ok", comment: "Button"))
        alert.alertStyle = .informational

        alert.window.defaultButtonCell = updateButton.cell as? NSButtonCell

        alert.runModal()
    }

    @MainActor
    private static func showUpdateCheckFailedDialog() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Couldn't check for updates", comment: "Alert title")
        alert.informativeText = NSLocalizedString("The update server could not be reached. Check your network connection and try again later.", comment: "Alert text")
        let okButton = alert.addButton(withTitle: NSLocalizedString("Ok", comment: "Button"))
        alert.alertStyle = .warning

        alert.window.defaultButtonCell = okButton.cell as? NSButtonCell

        alert.runModal()
    }

    @MainActor
    private static func showUpdateDownloadFailedDialog() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Update download failed", comment: "Alert title")
        alert.informativeText = NSLocalizedString("The new version could not be downloaded. Please try again later.", comment: "Alert text")
        let okButton = alert.addButton(withTitle: NSLocalizedString("Ok", comment: "Button"))
        alert.alertStyle = .warning

        alert.window.defaultButtonCell = okButton.cell as? NSButtonCell

        alert.runModal()
    }
}
