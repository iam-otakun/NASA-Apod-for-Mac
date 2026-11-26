//
//  DetailWindowController.swift
//  NASA APOD
//
//  The explanation window: the day's picture (or a video's first
//  frame) large, with title, date, credit and the full explanation,
//  and Previous / Next buttons that walk the local archive by date.
//

import Cocoa
import OSLog

private let logger = Logger(
    subsystem: Logging.subsystem,
    category: Logging.Category.Menu.rawValue
)

class DetailWindowController: NSWindowController {
    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subLabel = NSTextField(labelWithString: "")
    private let explanationView = NSTextView()
    private let positionLabel = NSTextField(labelWithString: "")
    private let prevButton = NSButton(title: "", target: nil, action: nil)
    private let nextButton = NSButton(title: "", target: nil, action: nil)
    private let watchButton = NSButton(title: "", target: nil, action: nil)
    private let wallpaperButton = NSButton(title: "", target: nil, action: nil)

    private var entries: [ArchivedEntry] = []
    private var index: Int = 0
    /// Picture for the entry the window was opened with, when the
    /// service already has it (saves a second download / frame pass).
    private var preloadedImages: [String: NSImage] = [:]

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "NASA APOD"
        window.minSize = NSSize(width: 560, height: 480)
        self.init(window: window)
        buildUI()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(imageView)

        titleLabel.font = NSFont.boldSystemFont(ofSize: 16)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(titleLabel)

        subLabel.font = NSFont.systemFont(ofSize: 12)
        subLabel.textColor = .secondaryLabelColor
        subLabel.lineBreakMode = .byTruncatingTail
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(subLabel)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        explanationView.isEditable = false
        explanationView.isSelectable = true
        explanationView.font = NSFont.systemFont(ofSize: 13)
        explanationView.textContainerInset = NSSize(width: 8, height: 8)
        explanationView.minSize = NSSize(width: 0, height: 0)
        explanationView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        explanationView.isVerticallyResizable = true
        explanationView.isHorizontallyResizable = false
        explanationView.autoresizingMask = [.width]
        explanationView.textContainer?.widthTracksTextView = true
        scroll.documentView = explanationView
        content.addSubview(scroll)

        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bar)

        prevButton.title = NSLocalizedString("Previous", comment: "Button")
        prevButton.bezelStyle = .rounded
        prevButton.target = self
        prevButton.action = #selector(goPrevious)
        nextButton.title = NSLocalizedString("Next", comment: "Button")
        nextButton.bezelStyle = .rounded
        nextButton.target = self
        nextButton.action = #selector(goNext)
        watchButton.title = NSLocalizedString("Watch Video", comment: "Button")
        watchButton.bezelStyle = .rounded
        watchButton.target = self
        watchButton.action = #selector(watchVideo)
        wallpaperButton.title = NSLocalizedString("Set as Wallpaper", comment: "Button")
        wallpaperButton.bezelStyle = .rounded
        wallpaperButton.target = self
        wallpaperButton.action = #selector(setAsWallpaper)
        positionLabel.font = NSFont.systemFont(ofSize: 12)
        positionLabel.textColor = .secondaryLabelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(prevButton)
        bar.addArrangedSubview(nextButton)
        bar.addArrangedSubview(positionLabel)
        bar.addArrangedSubview(spacer)
        bar.addArrangedSubview(watchButton)
        bar.addArrangedSubview(wallpaperButton)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            imageView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            imageView.heightAnchor.constraint(equalToConstant: 320),

            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            subLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            subLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            scroll.topAnchor.constraint(equalTo: subLabel.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            bar.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            bar.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    // MARK: - Presentation

    /// Open on `entry` (converted from the service's current day),
    /// with the rest of the local archive around it for browsing.
    func present(entry: ApodEntry, preloadedImage: NSImage?) {
        let archived = ArchivedEntry(
            date: entry.date, title: entry.title, credit: entry.credit,
            explanation: entry.explanation,
            mediaLabel: entry.isVideo ? "Video" : "Image",
            mediaURL: entry.isVideo ? entry.videoURL : entry.originalURL,
            imageFile: entry.localImageURL, videoFile: entry.localVideoURL)
        if let preloadedImage {
            preloadedImages[entry.date] = preloadedImage
        }

        var all: [ArchivedEntry] = []
        if let dir = ApodConfig.effectiveArchiveDirectory() {
            all = ArchiveLibrary.load(from: dir)
        }
        if let existing = all.firstIndex(where: { $0.date == archived.date }) {
            // The archive copy wins: it knows its media files.
            var merged = all[existing]
            if merged.explanation.isEmpty { merged.explanation = archived.explanation }
            if merged.credit.isEmpty { merged.credit = archived.credit }
            all[existing] = merged
            entries = all
            index = existing
        } else {
            all.append(archived)
            entries = all.sorted { $0.date < $1.date }
            index = entries.firstIndex(where: { $0.date == archived.date }) ?? 0
        }

        updateUI()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var current: ArchivedEntry? {
        return entries.indices.contains(index) ? entries[index] : nil
    }

    private func updateUI() {
        guard let entry = current else { return }
        window?.title = "NASA APOD — \(entry.date)"
        titleLabel.stringValue = entry.title
        var sub = entry.date
        if !entry.credit.isEmpty {
            sub += "   ·   " + entry.credit.replacingOccurrences(of: "Credit: ", with: "")
        }
        subLabel.stringValue = sub
        explanationView.string = entry.explanation
        explanationView.scrollToBeginningOfDocument(nil)
        positionLabel.stringValue = "\(index + 1) / \(entries.count)"
        prevButton.isEnabled = index > 0
        nextButton.isEnabled = index < entries.count - 1
        watchButton.isHidden = !entry.isVideo
        imageView.image = nil

        if let preloaded = preloadedImages[entry.date] {
            imageView.image = preloaded
            return
        }
        if let file = entry.imageFile, let image = NSImage(contentsOf: file) {
            imageView.image = image
            return
        }
        if entry.isVideo {
            let source = entry.videoFile ?? entry.mediaURL
            if let source {
                Task { [weak self] in
                    let frame = await ApodService.firstFrame(for: source)
                    await MainActor.run {
                        guard let self, self.current?.date == entry.date else { return }
                        self.imageView.image = frame
                        if let frame { self.preloadedImages[entry.date] = frame }
                    }
                }
            }
            return
        }
        if let url = entry.mediaURL {
            Task { [weak self] in
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = NSImage(data: data) {
                    await MainActor.run {
                        guard let self, self.current?.date == entry.date else { return }
                        self.imageView.image = image
                        self.preloadedImages[entry.date] = image
                    }
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func goPrevious() {
        guard index > 0 else { return }
        index -= 1
        updateUI()
    }

    @objc private func goNext() {
        guard index < entries.count - 1 else { return }
        index += 1
        updateUI()
    }

    @objc private func watchVideo() {
        guard let entry = current else { return }
        if let file = entry.videoFile {
            NSWorkspace.shared.open(file)
        } else if let url = entry.mediaURL {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func setAsWallpaper() {
        guard let entry = current else { return }
        Task { [weak self] in
            let file = await Self.wallpaperFile(for: entry)
            guard let file else { return }
            await MainActor.run {
                do {
                    for screen in NSScreen.screens {
                        try NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: [:])
                    }
                } catch {
                    logger.error("Failed to set desktop image: \(error.localizedDescription, privacy: .public)")
                }
            }
            _ = self
        }
    }

    /// A JPEG on disk for the wallpaper: the archived picture, a
    /// downloaded original, or a video's first frame — the same
    /// fallbacks as ApodService.wallpaperFile, for archive entries.
    private static func wallpaperFile(for entry: ArchivedEntry) async -> URL? {
        if let file = entry.imageFile {
            return file
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.otakun.NASAApod", isDirectory: true)
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        let base = entry.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespaces)
        let target = caches.appendingPathComponent("\(entry.date) \(base).jpg")
        if FileManager.default.fileExists(atPath: target.path) {
            return target
        }
        if entry.isVideo {
            let source = entry.videoFile ?? entry.mediaURL
            guard let source, let frame = await ApodService.firstFrame(for: source),
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
        guard let url = entry.mediaURL,
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        do {
            try data.write(to: target)
            return target
        } catch {
            return nil
        }
    }
}

private extension ApodEntry {
    var originalURL: URL? {
        if case .image(_, let originalURL) = kind { return originalURL }
        return nil
    }
}
