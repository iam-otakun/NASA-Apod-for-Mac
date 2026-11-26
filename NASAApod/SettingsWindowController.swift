//
//  SettingsWindowController.swift
//  NASA APOD
//
//  A programmatic settings window (no storyboard): launch at login
//  and the archive folder. The folder is written straight back to
//  ~/.nasa-apod.conf — the file that is the single source of truth
//  shared with the plugin and the Windows app — and a
//  security-scoped bookmark is kept alongside it, so a future
//  sandboxed build can pick the same folder up.
//

import Cocoa
import OSLog

private let logger = Logger(
    subsystem: Logging.subsystem,
    category: Logging.Category.Settings.rawValue
)

class SettingsWindowController: NSWindowController {
    private let settings = Settings()
    private let loginCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let approvalNote = NSTextField(labelWithString: "")
    private let openLoginItemsButton = NSButton(title: "", target: nil, action: nil)
    private let archiveCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let pathField = NSTextField(string: "")
    private let chooseButton = NSButton(title: "", target: nil, action: nil)
    private let defaultButton = NSButton(title: "", target: nil, action: nil)

    /// Called after the archive settings changed, so the service can
    /// archive today into the (possibly new) folder right away.
    var onArchiveSettingsChanged: (() -> Void)?

    private static let bookmarkKey = "ArchiveFolderBookmark"

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = NSLocalizedString("NASA APOD Settings", comment: "Settings window title")
        self.init(window: window)
        buildUI()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        loginCheckbox.title = NSLocalizedString("Launch at login", comment: "Settings checkbox")
        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin)
        stack.addArrangedSubview(loginCheckbox)

        approvalNote.font = NSFont.systemFont(ofSize: 11)
        approvalNote.textColor = .secondaryLabelColor
        approvalNote.stringValue = NSLocalizedString("Approve NASA APOD in Login Items", comment: "Settings note")
        stack.addArrangedSubview(approvalNote)

        openLoginItemsButton.title = NSLocalizedString("Open Login Items", comment: "Button")
        openLoginItemsButton.bezelStyle = .rounded
        openLoginItemsButton.target = self
        openLoginItemsButton.action = #selector(openLoginItems)
        stack.addArrangedSubview(openLoginItemsButton)

        let separator = NSBox()
        separator.boxType = .separator
        stack.addArrangedSubview(separator)

        archiveCheckbox.title = NSLocalizedString("Archive each day's picture and notes", comment: "Settings checkbox")
        archiveCheckbox.target = self
        archiveCheckbox.action = #selector(toggleArchive)
        stack.addArrangedSubview(archiveCheckbox)

        let pathRow = NSStackView()
        pathRow.orientation = .horizontal
        pathRow.spacing = 8
        pathField.translatesAutoresizingMaskIntoConstraints = false
        pathField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        pathField.target = self
        pathField.action = #selector(pathEdited)
        chooseButton.title = NSLocalizedString("Choose…", comment: "Button")
        chooseButton.bezelStyle = .rounded
        chooseButton.target = self
        chooseButton.action = #selector(chooseFolder)
        defaultButton.title = NSLocalizedString("Use Default", comment: "Button")
        defaultButton.bezelStyle = .rounded
        defaultButton.target = self
        defaultButton.action = #selector(useDefault)
        pathRow.addArrangedSubview(pathField)
        pathRow.addArrangedSubview(chooseButton)
        pathRow.addArrangedSubview(defaultButton)
        stack.addArrangedSubview(pathRow)

        let hint = NSTextField(labelWithString: NSLocalizedString("Stored in ~/.nasa-apod.conf, shared with the SwiftBar plugin and the Windows app.", comment: "Settings hint"))
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hint)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        refreshUI()
    }

    override func showWindow(_ sender: Any?) {
        refreshUI()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshUI() {
        loginCheckbox.state = settings.launchAtLogin ? .on : .off
        let needsApproval = settings.launchAtLoginRequiresApproval
        approvalNote.isHidden = !needsApproval
        openLoginItemsButton.isHidden = !needsApproval

        if let dir = ApodConfig.effectiveArchiveDirectory() {
            archiveCheckbox.state = .on
            pathField.stringValue = dir.path
            pathField.isEnabled = true
            chooseButton.isEnabled = true
        } else {
            archiveCheckbox.state = .off
            pathField.stringValue = ApodConfig.confValue() ?? ""
            pathField.isEnabled = false
            chooseButton.isEnabled = false
        }
    }

    // MARK: - Launch at login

    @objc private func toggleLogin() {
        let newValue = loginCheckbox.state == .on
        do {
            try settings.setLaunchAtLogin(newValue)
        } catch {
            logger.error("Failed to set launch at login: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Couldn't update Launch at Login", comment: "Alert title")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: NSLocalizedString("Ok", comment: "Button"))
            alert.runModal()
        }
        refreshUI()
    }

    @objc private func openLoginItems() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Archive folder

    @objc private func toggleArchive() {
        // Same no-change guard as pathEdited: a delivered action
        // whose state already matches the conf is not a change.
        let isOn = archiveCheckbox.state == .on
        let currentlyOn = ApodConfig.effectiveArchiveDirectory() != nil
        guard isOn != currentlyOn else { refreshUI(); return }
        if archiveCheckbox.state == .on {
            let path = pathField.stringValue.isEmpty
                ? ApodConfig.defaultArchiveDirectory.path
                : pathField.stringValue
            ApodConfig.saveConf(value: path)
        } else {
            ApodConfig.saveConf(value: "")
        }
        refreshUI()
        onArchiveSettingsChanged?()
    }

    @objc private func pathEdited() {
        let path = pathField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return }
        // AppKit can deliver this action without a real edit (the
        // field editor ending as the window settles); only a genuine
        // change may rewrite the conf and trigger a re-fetch.
        guard ApodConfig.effectiveArchiveDirectory()?.path != path else { return }
        ApodConfig.saveConf(value: path)
        refreshUI()
        onArchiveSettingsChanged?()
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = NSLocalizedString("Choose", comment: "Button")
        panel.message = NSLocalizedString("Choose a folder for archiving the NASA picture of the day", comment: "Panel message")
        if let dir = ApodConfig.effectiveArchiveDirectory() {
            panel.directoryURL = dir
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Keep a security-scoped bookmark for a future sandboxed
        // build; the conf file stays the source of truth today.
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                                 includingResourceValuesForKeys: nil,
                                                 relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        }
        ApodConfig.saveConf(value: url.path)
        refreshUI()
        onArchiveSettingsChanged?()
    }

    @objc private func useDefault() {
        // Mirrors the plugin's "Restore Default Folder": removing
        // the conf file restores the default directory.
        try? FileManager.default.removeItem(at: ApodConfig.confURL)
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        refreshUI()
        onArchiveSettingsChanged?()
    }
}
