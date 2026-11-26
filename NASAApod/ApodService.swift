//
//  ApodService.swift
//  NASA APOD
//
//  The engine room, mirroring the SwiftBar plugin's main flow:
//  fetch the APOD page (browser User-Agent, generous timeouts),
//  parse it with ApodParser, archive the day under the completeness
//  rule, and keep a diagnostic line per event in ~/.nasa-apod.log —
//  the same log the plugin writes.
//
//  Completeness rule (shared with the plugin and the Windows app):
//  every day leaves its artefact in the archive. Image days: the
//  original picture plus a same-named .txt (title, date, credit,
//  full explanation, source links). Video days: the .txt always,
//  plus the .mp4 itself when it is at most 100 MB. og:image is
//  never used; when extraction fails the app shows an error state
//  instead of saving a wrong picture.
//

import Foundation
import AppKit
import AVFoundation
import OSLog

private let logger = Logger(
    subsystem: Logging.subsystem,
    category: Logging.Category.Service.rawValue
)

/// Append one timestamped line to ~/.nasa-apod.log, the diagnostic
/// log shared with the SwiftBar plugin.
enum ApodLog {
    private static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".nasa-apod.log")
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone.current
        return f
    }()
    private static let queue = DispatchQueue(label: "com.otakun.NASAApod.log")

    static func write(_ message: String) {
        queue.async {
            // The plugin stamps local time without an offset
            // ("2026-11-26T10:13:43 displaying APOD date ...").
            let stamp = formatter.string(from: Date()).replacingOccurrences(
                of: #"\+\d\d:\d\d$|Z$"#, with: "", options: .regularExpression)
            let line = "\(stamp) \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}

/// ~/.nasa-apod.conf — the single source of truth for the archive
/// folder, shared with the plugin and the Windows app:
/// no ARCHIVE_DIR line -> default ~/Pictures/NASA-Apod,
/// empty value -> archiving off, otherwise the given path.
enum ApodConfig {
    static let confURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".nasa-apod.conf")

    static var defaultArchiveDirectory: URL {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures/NASA-Apod")
    }

    /// The raw ARCHIVE_DIR value: nil when never set.
    static func confValue() -> String? {
        guard let text = try? String(contentsOf: confURL, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: "\n") where line.hasPrefix("ARCHIVE_DIR=") {
            return String(line.dropFirst("ARCHIVE_DIR=".count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// The folder to archive into, or nil when archiving is off.
    static func effectiveArchiveDirectory() -> URL? {
        guard let value = confValue() else { return defaultArchiveDirectory }
        if value.isEmpty { return nil }
        return URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
    }

    static func saveConf(value: String) {
        try? "ARCHIVE_DIR=\(value)\n".write(to: confURL, atomically: true, encoding: .utf8)
    }
}

class ApodService {

    enum State {
        case loading
        case loaded(ApodEntry)
        case error(String)
    }

    private(set) var state: State = .loading
    /// The picture to show for the current entry: the day's photo on
    /// image days, the video's first frame on video days.
    private(set) var displayImage: NSImage?

    /// Called on the main queue whenever the state or image changes.
    var onChange: (() -> Void)?

    private var timer: Timer?
    private var fetching = false
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
    private static let videoCapBytes = 100 * 1024 * 1024

    private var lastFetchedDate: String? {
        get { UserDefaults.standard.string(forKey: "LastFetchedApodDate") }
        set { UserDefaults.standard.set(newValue, forKey: "LastFetchedApodDate") }
    }

    var currentEntry: ApodEntry? {
        if case .loaded(let entry) = state { return entry }
        return nil
    }

    // MARK: - Lifecycle

    func start() {
        refreshIfNeeded()
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            self?.refreshIfNeeded()
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func workspaceDidWake() {
        refreshIfNeeded()
    }

    /// APOD days roll over at midnight in America/New_York; only
    /// fetch when the entry we hold is not that day's.
    func refreshIfNeeded() {
        if let entry = currentEntry, entry.date == Self.todayInNewYork() { return }
        refresh()
    }

    func refresh() {
        guard !fetching else { return }
        fetching = true
        Task { [weak self] in
            await self?.performFetch()
            self?.fetching = false
        }
    }

    static func todayInNewYork() -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Fetch & archive

    private func performFetch() async {
        let page: String
        do {
            let data = try await fetchData(from: URL(string: "https://apod.nasa.gov/apod/")!, timeout: 60)
            guard let text = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "ApodService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Page was not UTF-8"])
            }
            page = text
        } catch {
            ApodLog.write("page fetch failed: \(error.localizedDescription)")
            await setState(.error(error.localizedDescription))
            return
        }

        guard let hero = ApodParser.hero(in: page) else {
            ApodLog.write("hero extraction failed")
            await setState(.error(NSLocalizedString("Could not find today's picture on the APOD page.", comment: "Error state")))
            return
        }

        let date = ApodParser.pageDate(in: page) ?? Self.todayInNewYork()
        let title = ApodParser.title(in: page) ?? ""
        let (credit, explanation) = ApodParser.entryText(in: page)

        switch hero {
        case .video(let urlString):
            guard let videoURL = URL(string: urlString) else {
                ApodLog.write("hero extraction failed")
                await setState(.error(NSLocalizedString("Could not find today's picture on the APOD page.", comment: "Error state")))
                return
            }
            var entry = ApodEntry(date: date, title: title, credit: credit,
                                  explanation: explanation, kind: .video(url: videoURL))
            ApodLog.write("displaying APOD date \(date) (video)")
            await archiveVideoDay(entry: &entry)
            finishFetch(entry: entry)
            // First frame for the menu and the detail window: from
            // the archived file when there is one, else the stream.
            let frameSource = entry.localVideoURL ?? videoURL
            if let frame = await Self.firstFrame(for: frameSource) {
                await MainActor.run { [weak self] in
                    self?.displayImage = frame
                    self?.onChange?()
                }
            }

        case .image(let displayString, let originalString):
            guard let displayURL = URL(string: displayString), let originalURL = URL(string: originalString) else {
                ApodLog.write("hero extraction failed")
                await setState(.error(NSLocalizedString("Could not find today's picture on the APOD page.", comment: "Error state")))
                return
            }
            var entry = ApodEntry(date: date, title: title, credit: credit,
                                  explanation: explanation,
                                  kind: .image(displayURL: displayURL, originalURL: originalURL))
            ApodLog.write("displaying APOD date \(date)")
            let displayData = try? await fetchData(from: displayURL, timeout: 60)
            await archiveImageDay(entry: &entry, displayData: displayData)
            finishFetch(entry: entry)
            if let displayData, let image = NSImage(data: displayData) {
                await MainActor.run { [weak self] in
                    self?.displayImage = image
                    self?.onChange?()
                }
            }
        }
    }

    private func finishFetch(entry: ApodEntry) {
        lastFetchedDate = entry.date
        // The plugin keeps the same marker in ~/.nasa-apod.state for
        // its manual-refresh comparison; stay consistent with it.
        let stateURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".nasa-apod.state")
        try? (entry.date + "\n").write(to: stateURL, atomically: true, encoding: .utf8)
        Task { await setState(.loaded(entry)) }
    }

    private func setState(_ newState: State) async {
        await MainActor.run { [weak self] in
            self?.state = newState
            self?.onChange?()
        }
    }

    /// Image day: save the original (skipping an existing file),
    /// falling back to the display image when the original cannot be
    /// fetched; then the same-named .txt.
    private func archiveImageDay(entry: inout ApodEntry, displayData: Data?) async {
        guard let dir = ApodConfig.effectiveArchiveDirectory() else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let imageURL = dir.appendingPathComponent(entry.archiveBaseName + ".jpg")
        if fm.fileExists(atPath: imageURL.path) {
            entry.localImageURL = imageURL
        } else {
            var data: Data?
            if case .image(_, let originalURL) = entry.kind {
                data = try? await fetchData(from: originalURL, timeout: 60)
            }
            data = data ?? displayData
            if let data {
                do {
                    try data.write(to: imageURL, options: .withoutOverwriting)
                    entry.localImageURL = imageURL
                } catch {
                    logger.error("Failed to archive image: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        Self.writeEntryNote(entry: entry, in: dir, mediaLabel: "Image",
                            mediaURL: entry.kind.originalURLString)
    }

    /// Video day: the .txt always; the .mp4 itself when its size is
    /// known to be at most 100 MB (an unknown size still downloads,
    /// like the plugin).
    private func archiveVideoDay(entry: inout ApodEntry) async {
        guard let dir = ApodConfig.effectiveArchiveDirectory() else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        Self.writeEntryNote(entry: entry, in: dir, mediaLabel: "Video",
                            mediaURL: entry.videoURL?.absoluteString)
        guard let videoURL = entry.videoURL else { return }
        let fileURL = dir.appendingPathComponent(entry.archiveBaseName + ".mp4")
        if fm.fileExists(atPath: fileURL.path) {
            entry.localVideoURL = fileURL
            return
        }
        if let size = await headContentLength(of: videoURL), size > Self.videoCapBytes {
            entry.videoTooLarge = true
            ApodLog.write("video too large (\(size) bytes), link only")
            return
        }
        do {
            let data = try await fetchData(from: videoURL, timeout: 300)
            try data.write(to: fileURL, options: .withoutOverwriting)
            entry.localVideoURL = fileURL
            ApodLog.write("archived video \(fileURL.lastPathComponent) (\(data.count) bytes)")
        } catch {
            ApodLog.write("video archive failed: \(error.localizedDescription)")
        }
    }

    /// The day's note, in the exact format the plugin writes; an
    /// existing note is left untouched.
    static func writeEntryNote(entry: ApodEntry, in directory: URL, mediaLabel: String, mediaURL: String?) {
        let noteURL = directory.appendingPathComponent(entry.archiveBaseName + ".txt")
        if FileManager.default.fileExists(atPath: noteURL.path) { return }
        var lines: [String] = [entry.fileNameTitle, "Date: \(entry.date)"]
        if !entry.credit.isEmpty {
            lines.append(entry.credit)
        }
        lines.append("")
        lines.append("Explanation:")
        lines.append(entry.explanation.isEmpty ? "(extraction failed)" : entry.explanation)
        lines.append("")
        if let mediaURL, !mediaURL.isEmpty {
            lines.append("\(mediaLabel): \(mediaURL)")
        }
        lines.append("APOD: https://apod.nasa.gov/apod/")
        try? (lines.joined(separator: "\n") + "\n").write(to: noteURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Networking

    private func fetchData(from url: URL, timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 30
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NSError(domain: "ApodService", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        return data
    }

    private func headContentLength(of url: URL) async -> Int? {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "HEAD"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        return http.expectedContentLength > 0 ? Int(http.expectedContentLength) : nil
    }

    // MARK: - Video first frames & wallpaper files

    /// First frame of a video (local file or remote URL), generated
    /// with AVAssetImageGenerator — the app's answer to the site
    /// offering no poster frame.
    static func firstFrame(for url: URL) async -> NSImage? {
        return await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 960, height: 960)
            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }.value
    }

    /// A JPEG on disk for "Set as Wallpaper": the archived original
    /// when there is one; otherwise a download (image days) or the
    /// generated first frame (video days) in the caches folder.
    func wallpaperFile(for entry: ApodEntry) async -> URL? {
        if let local = entry.localImageURL {
            return local
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.otakun.NASAApod", isDirectory: true)
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        let target = caches.appendingPathComponent(entry.archiveBaseName + ".jpg")
        if FileManager.default.fileExists(atPath: target.path) {
            return target
        }
        switch entry.kind {
        case .image(_, let originalURL):
            guard let data = try? await fetchData(from: originalURL, timeout: 60) else { return nil }
            do {
                try data.write(to: target)
                return target
            } catch {
                return nil
            }
        case .video:
            let source = entry.localVideoURL ?? entry.videoURL
            guard let source, let frame = await Self.firstFrame(for: source),
                  let tiff = frame.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let jpeg = bitmap.representation(using: .jpeg, properties: [:]) else { return nil }
            do {
                try jpeg.write(to: target)
                return target
            } catch {
                return nil
            }
        }
    }
}

private extension ApodEntry.Kind {
    var originalURLString: String? {
        if case .image(_, let originalURL) = self { return originalURL.absoluteString }
        return nil
    }
}
