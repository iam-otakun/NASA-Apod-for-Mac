//
//  FileHandler.swift
//  NASA APOD
//
//  Only the self-updater's installer handling is kept from
//  BingWallpaper's FileHandler: where a downloaded .pkg lives.
//

import Foundation
import OSLog

private let logger = Logger(
    subsystem: Logging.subsystem,
    category: Logging.Category.FileHandler.rawValue
)

class FileHandler {

    static func savePkgInstallerToDisk(pkgInstaller: Data, appVersion: String) -> URL? {
        let temporaryDirectoryUrl = pkgInstallerPathUrl(appVersion: appVersion)
        do {
            try pkgInstaller.write(to: temporaryDirectoryUrl)
        } catch {
            logger.error("Failed to save pkg installer to disk with error: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        return temporaryDirectoryUrl
    }

    static func pkgInstallerAlreadyDownloaded(appVersion: String) -> URL? {
        let temporaryDirectoryUrl = pkgInstallerPathUrl(appVersion: appVersion)
        if FileManager.default.fileExists(atPath: temporaryDirectoryUrl.relativePath) == true {
            return temporaryDirectoryUrl
        }

        return nil
    }

    static func pkgInstallerPathUrl(appVersion: String) -> URL {
        var temporaryDirectoryUrl = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        temporaryDirectoryUrl.appendPathComponent("NASAApod_" + appVersion + ".pkg")
        return temporaryDirectoryUrl
    }
}
