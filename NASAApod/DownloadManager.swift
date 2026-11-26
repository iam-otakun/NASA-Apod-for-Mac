//
//  DownloadManager.swift
//  NASA APOD
//
//  The three helpers AppUpdateManager needs (kept from
//  BingWallpaper's DownloadManager): HTML, redirect headers and
//  binary downloads over URLSession.
//

import Foundation
import OSLog

private let logger = Logger(
    subsystem: Logging.subsystem,
    category: Logging.Category.Download.rawValue
)

class DownloadManager {

    private static func downloadData(from url: URL) async throws -> (Data, URLResponse) {
        return try await URLSession.shared.data(from: url)
    }

    private static func downloadHttpHead(from url: URL) async throws -> URLResponse {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "HEAD"
        let (_, urlResponse) = try await URLSession.shared.data(for: urlRequest)
        return urlResponse
    }

    static func downloadHtml(from url: URL) async -> String? {
        do {
            let (data, _) = try await downloadData(from: url)
            return String(data: data, encoding: .utf8)
        } catch let error {
            logger.error("Failed to download HTML from \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func downloadHtmlHeaders(from url: URL) async -> URLResponse? {
        do {
            return try await downloadHttpHead(from: url)
        } catch let error {
            logger.error("Failed to download HTML headers from \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    static func downloadBinary(from url: URL) async throws -> Data {
        return try await downloadData(from: url).0
    }
}
