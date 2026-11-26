//
//  ApodEntry.swift
//  NASA APOD
//
//  The day's entry as parsed from the APOD page, plus the reader for
//  the on-disk archive (the same-named .txt files the archiver — this
//  app, the SwiftBar plugin and the Windows app — writes next to each
//  day's media).
//

import Foundation

struct ApodEntry {
    enum Kind {
        case image(displayURL: URL, originalURL: URL)
        case video(url: URL)
    }

    /// APOD date, `yyyy-MM-dd` (the byline date on the entry's page).
    var date: String
    var title: String
    var credit: String
    var explanation: String
    var kind: Kind

    /// The archived original picture (image days), when archiving is on.
    var localImageURL: URL?
    /// The archived video file (video days, at or under the size cap).
    var localVideoURL: URL?
    /// Video day whose file was over the cap: text and link only.
    var videoTooLarge: Bool = false

    var isVideo: Bool {
        if case .video = kind { return true }
        return false
    }

    var videoURL: URL? {
        if case .video(let url) = kind { return url }
        return nil
    }

    /// Title made safe for a file name, same rule as the plugin:
    /// `/`, `:` and `\` become `-`, then trimmed.
    var fileNameTitle: String {
        return title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespaces)
    }

    /// `YYYY-MM-DD Title` — the shared base name of the day's files.
    var archiveBaseName: String {
        let t = fileNameTitle
        return t.isEmpty ? date : "\(date) \(t)"
    }
}

/// One day read back from the archive folder (its .txt note, with the
/// media file it belongs to when present).
struct ArchivedEntry {
    var date: String
    var title: String
    var credit: String
    var explanation: String
    /// "Image" or "Video" — the media label recorded in the note.
    var mediaLabel: String?
    var mediaURL: URL?
    var imageFile: URL?
    var videoFile: URL?

    var isVideo: Bool { return mediaLabel == "Video" || (videoFile != nil && imageFile == nil) }
}

enum ArchiveLibrary {
    /// All archived days in `directory`, oldest first. A day counts as
    /// archived when its .txt note exists; the media file joins it
    /// when present.
    static func load(from directory: URL) -> [ArchivedEntry] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        var entries: [ArchivedEntry] = []
        for name in names where name.hasSuffix(".txt") {
            let txtURL = directory.appendingPathComponent(name)
            guard let text = try? String(contentsOf: txtURL, encoding: .utf8) else { continue }
            if var entry = parse(note: text) {
                let base = (name as NSString).deletingPathExtension
                let jpg = directory.appendingPathComponent(base + ".jpg")
                let mp4 = directory.appendingPathComponent(base + ".mp4")
                if fm.fileExists(atPath: jpg.path) { entry.imageFile = jpg }
                if fm.fileExists(atPath: mp4.path) { entry.videoFile = mp4 }
                entries.append(entry)
            }
        }
        return entries.sorted { $0.date < $1.date }
    }

    /// Parse the note format shared by all three APOD programs:
    ///
    ///     <title>
    ///     Date: yyyy-MM-dd
    ///     <credit, optional>
    ///
    ///     Explanation:
    ///     <full text>
    ///
    ///     Image: <url>        (or Video: <url>)
    ///     APOD: https://apod.nasa.gov/apod/
    static func parse(note text: String) -> ArchivedEntry? {
        let lines = text.components(separatedBy: "\n")
        guard lines.count >= 2, lines[1].hasPrefix("Date: ") else { return nil }
        let title = lines[0]
        let date = String(lines[1].dropFirst("Date: ".count)).trimmingCharacters(in: .whitespaces)
        var credit = ""
        if lines.count > 3, !lines[2].isEmpty {
            credit = lines[2]
        }
        var explanation = ""
        var mediaLabel: String?
        var mediaURL: URL?
        if let explIndex = lines.firstIndex(of: "Explanation:") {
            var body: [String] = []
            for line in lines[(explIndex + 1)...] {
                if line.hasPrefix("Image: ") || line.hasPrefix("Video: ") || line.hasPrefix("APOD: ") {
                    break
                }
                body.append(line)
            }
            explanation = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for line in lines {
            if line.hasPrefix("Image: ") {
                mediaLabel = "Image"
                mediaURL = URL(string: String(line.dropFirst("Image: ".count)))
            } else if line.hasPrefix("Video: ") {
                mediaLabel = "Video"
                mediaURL = URL(string: String(line.dropFirst("Video: ".count)))
            }
        }
        return ArchivedEntry(date: date, title: title, credit: credit,
                             explanation: explanation, mediaLabel: mediaLabel,
                             mediaURL: mediaURL, imageFile: nil, videoFile: nil)
    }
}
