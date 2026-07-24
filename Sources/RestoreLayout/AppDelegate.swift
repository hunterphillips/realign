import AppKit
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var restoreHotKey: GlobalHotKey?
    private var saveHotKey: GlobalHotKey?
    private var permissionTimer: Timer?
    private let store = LayoutStore()

    private let restoreHotKeyDisplay = "⌃⌥⌘R"
    private let saveHotKeyDisplay = "⌃⌥⌘S"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configureHotKeys()
        if AXPermission.isTrusted {
            showBaseIcon()
        } else {
            promptForPermission()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        showBaseIcon()
    }

    private func configureHotKeys() {
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        restoreHotKey = GlobalHotKey(
            identifier: 1,
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: modifiers
        ) { [weak self] in
            Task { @MainActor in self?.restoreLayout() }
        }
        saveHotKey = GlobalHotKey(
            identifier: 2,
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: modifiers
        ) { [weak self] in
            Task { @MainActor in self?.saveLayout() }
        }
    }

    // MARK: - Actions

    @objc private func restoreLayout() {
        guard AXPermission.isTrusted else {
            promptForPermission()
            return
        }
        showIcon(
            symbol: "arrow.triangle.2.circlepath",
            description: "Restoring layout"
        )
        let report = RestoreEngine.restore(store: store)
        let isPartial = report.skipped > 0 || report.failed > 0
        statusItem.button?.toolTip = isPartial
            ? "RestoreLayout — \(report.summary)"
            : "RestoreLayout — layout restored"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.showBaseIcon(preserveTooltip: isPartial)
        }
    }

    @objc private func saveLayout() {
        guard AXPermission.isTrusted else {
            promptForPermission()
            return
        }
        do {
            let layout = try CaptureEngine.captureAndSave(store: store)
            showIcon(
                symbol: "checkmark.rectangle",
                description: "Layout saved"
            )
            statusItem.button?.toolTip =
                "RestoreLayout — saved \(layout.windows.count) windows"
        } catch {
            showIcon(
                symbol: "exclamationmark.triangle",
                description: "Could not save layout"
            )
            statusItem.button?.toolTip =
                "RestoreLayout — save failed: \(error.localizedDescription)"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.showBaseIcon()
        }
    }

    @objc private func toggleLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func grantAccessibility() {
        promptForPermission()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let trusted = AXPermission.isTrusted

        if !trusted {
            let grant = NSMenuItem(
                title: "Grant Accessibility Access…",
                action: #selector(grantAccessibility),
                keyEquivalent: ""
            )
            grant.target = self
            menu.addItem(grant)
            menu.addItem(.separator())
        }

        let restore = NSMenuItem(
            title: "Restore Layout",
            action: #selector(restoreLayout),
            keyEquivalent: "r"
        )
        restore.target = self
        restore.keyEquivalentModifierMask = [.control, .option, .command]
        restore.isEnabled = trusted
        menu.addItem(restore)

        let save = NSMenuItem(
            title: "Save Current Layout",
            action: #selector(saveLayout),
            keyEquivalent: "s"
        )
        save.target = self
        save.keyEquivalentModifierMask = [.control, .option, .command]
        save.isEnabled = trusted
        menu.addItem(save)

        menu.addItem(.separator())
        let savedInfo = NSMenuItem(
            title: savedAtDescription(),
            action: nil,
            keyEquivalent: ""
        )
        savedInfo.isEnabled = false
        menu.addItem(savedInfo)

        let login = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLogin),
            keyEquivalent: ""
        )
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit RestoreLayout",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
    }

    private func savedAtDescription() -> String {
        do {
            guard let layout = try store.load() else {
                return "No layout saved"
            }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "Saved: \(formatter.string(from: layout.savedAt))"
        } catch {
            return "Saved layout unreadable"
        }
    }

    // MARK: - Permission onboarding

    private func promptForPermission() {
        _ = AXPermission.ensureTrusted()
        guard !AXPermission.isTrusted else {
            permissionGranted()
            return
        }
        statusItem.button?.toolTip =
            "RestoreLayout needs Accessibility access"
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] timer in
            guard AXPermission.isTrusted else { return }
            timer.invalidate()
            Task { @MainActor in self?.permissionGranted() }
        }
    }

    private func permissionGranted() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        showBaseIcon()
    }

    // MARK: - Icon feedback

    private func showBaseIcon(preserveTooltip: Bool = false) {
        showIcon(
            symbol: "rectangle.split.2x1",
            description: "RestoreLayout"
        )
        if !preserveTooltip {
            statusItem.button?.toolTip =
                "RestoreLayout — restore \(restoreHotKeyDisplay), " +
                "save \(saveHotKeyDisplay)"
        }
    }

    private func showIcon(symbol: String, description: String) {
        let image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: description
        )
        image?.isTemplate = true
        statusItem.button?.image = image
    }
}

