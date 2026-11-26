//
//  MenuController.swift
//  NASA APOD
//
//  The menu-bar front end. The status item is the app's only entry
//  point, so it is always created and there is deliberately no
//  "hide icon" option anywhere. The menu is rebuilt on every open
//  from ApodService's current state.
//

import Cocoa
import OSLog

private let logger = Logger(
    subsystem: Logging.subsystem,
    category: Logging.Category.Menu.rawValue
)

class MenuController: NSObject {
    private let service: ApodService
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?

    var onShowSettings: (() -> Void)?
    var onShowDetail: ((ApodEntry) -> Void)?

    init(service: ApodService) {
        self.service = service
        super.init()
    }

    @MainActor
    func setup() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let symbol = NSImage(systemSymbolName: "moon.stars", accessibilityDescription: "NASA APOD") {
                button.image = symbol
            } else {
                button.title = "🔭"
            }
            button.toolTip = "NASA APOD"
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        self.statusItem = item
        self.menu = menu

        service.onChange = { [weak self] in
            // State changed under a closed menu; the next open
            // rebuilds anyway (menuNeedsUpdate), nothing to do here.
            _ = self
        }
    }

    // MARK: - Menu construction

    @MainActor
    private func rebuildMenu() {
        guard let menu else { return }
        menu.removeAllItems()

        switch service.state {
        case .loading:
            menu.addItem(disabledItem(NSLocalizedString("Loading…", comment: "Menu header while fetching")))
        case .error(let message):
            let header = disabledItem(NSLocalizedString("Couldn't load today's picture", comment: "Menu header on error"))
            menu.addItem(header)
            let detail = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            detail.isEnabled = false
            menu.addItem(detail)
        case .loaded(let entry):
            let header = NSMenuItem(title: "\(entry.date)  \(entry.title)", action: nil, keyEquivalent: "")
            header.attributedTitle = NSAttributedString(
                string: "\(entry.date)  \(entry.title)",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
            header.isEnabled = false
            menu.addItem(header)

            if let image = service.displayImage {
                menu.addItem(thumbnailItem(image: image))
            }

            if entry.isVideo {
                menu.addItem(disabledItem(NSLocalizedString("Today's entry is a video", comment: "Menu note on video days")))
                let watch = actionItem(NSLocalizedString("Watch Video", comment: "Menu item"), #selector(watchVideo))
                menu.addItem(watch)
                if let localVideo = entry.localVideoURL {
                    let archived = NSMenuItem(
                        title: String(format: NSLocalizedString("Video archived: %@", comment: "Menu item"), localVideo.lastPathComponent),
                        action: #selector(revealArchivedVideo), keyEquivalent: "")
                    archived.target = self
                    archived.representedObject = localVideo
                    menu.addItem(archived)
                } else if entry.videoTooLarge {
                    menu.addItem(disabledItem(NSLocalizedString("Video is large (over 100 MB) — link only", comment: "Menu note")))
                }
            }

            menu.addItem(actionItem(NSLocalizedString("View Explanation…", comment: "Menu item"), #selector(viewExplanation)))
            menu.addItem(actionItem(NSLocalizedString("Set as Wallpaper", comment: "Menu item"), #selector(setAsWallpaper)))
        }

        menu.addItem(actionItem(NSLocalizedString("Open Archive Folder", comment: "Menu item"), #selector(openArchiveFolder),
                                enabled: ApodConfig.effectiveArchiveDirectory() != nil))
        menu.addItem(actionItem(NSLocalizedString("Refresh", comment: "Menu item"), #selector(refresh)))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(actionItem(NSLocalizedString("Settings…", comment: "Menu item"), #selector(showSettings)))
        menu.addItem(actionItem(NSLocalizedString("Check for Updates...", comment: "Menu item"), #selector(checkForAppUpdate)))
        menu.addItem(actionItem(NSLocalizedString("About…", comment: "Menu item"), #selector(showAbout)))
        let quit = NSMenuItem(title: NSLocalizedString("Quit", comment: "Menu item"),
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ action: Selector, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    private func thumbnailItem(image: NSImage) -> NSMenuItem {
        let width: CGFloat = 320
        let ratio = image.size.height > 0 ? image.size.width / image.size.height : 16.0 / 9.0
        var height = width / max(ratio, 0.1)
        height = min(max(height, 100), 240)
        let imageView = NSImageView(frame: NSRect(x: 10, y: 4, width: width, height: height))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width + 20, height: height + 8))
        container.addSubview(imageView)
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.view = container
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func refresh() {
        service.refresh()
    }

    @objc private func viewExplanation() {
        guard let entry = service.currentEntry else { return }
        onShowDetail?(entry)
    }

    @objc private func watchVideo() {
        guard let entry = service.currentEntry else { return }
        if let local = entry.localVideoURL {
            NSWorkspace.shared.open(local)
        } else if let url = entry.videoURL {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func revealArchivedVideo(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func setAsWallpaper() {
        guard let entry = service.currentEntry else { return }
        Task { [weak self] in
            guard let file = await self?.service.wallpaperFile(for: entry) else { return }
            await MainActor.run {
                do {
                    for screen in NSScreen.screens {
                        try NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: [:])
                    }
                } catch {
                    logger.error("Failed to set desktop image: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    @objc private func openArchiveFolder() {
        guard let dir = ApodConfig.effectiveArchiveDirectory() else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc private func showSettings() {
        onShowSettings?()
    }

    @objc private func checkForAppUpdate() {
        Task {
            await AppUpdateManager.checkForUpdate(notifyUserAboutNoNewVersion: true)
        }
    }

    // The house About, same as our other programs: the standard
    // panel shows name and version from the bundle; the credits
    // carry Idea: Otakun, Coding: Dash and a link labelled
    // "GitHub Repository" (never the raw URL as the link text).
    @objc private func showAbout() {
        let credits = NSMutableAttributedString()
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor
        ]
        credits.append(NSAttributedString(string: "Idea: Otakun\nCoding: Dash\n", attributes: textAttrs))
        let linkAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .link: URL(string: "https://github.com/iam-otakun/NASA-Apod-for-Mac")!
        ]
        credits.append(NSAttributedString(string: "GitHub Repository", attributes: linkAttrs))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        credits.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: credits.length))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}

extension MenuController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }
}
