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
            Task { @MainActor in self?.restoreShortcutTarget() }
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

    @objc private func restoreLaptop() {
        restore(target: .laptop)
    }

    @objc private func restoreMultiDisplay() {
        restore(target: .multiDisplay)
    }

    private func restoreShortcutTarget() {
        let target = (try? RestoreEngine.shortcutTarget(store: store)) ?? .connectedDisplays
        restore(target: target)
    }

    private func restore(target: RestoreTarget) {
        guard AXPermission.isTrusted else {
            promptForPermission()
            return
        }
        showIcon(
            symbol: "arrow.triangle.2.circlepath",
            description: "Restoring layout"
        )
        let report = RestoreEngine.restore(target: target, store: store)
        let isPartial = !report.applied || report.skipped > 0 || report.failed > 0
        let tooltip: String
        if !report.applied {
            // Nothing was applied: name the reason rather than zero counts.
            tooltip = report.reasons.first ?? report.summary
        } else if isPartial {
            tooltip = report.summary
        } else {
            tooltip = report.target.map { "\($0) restored" } ?? report.summary
        }
        statusItem.button?.toolTip = "RestoreLayout — \(tooltip)"
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
            let (layout, slot) = try CaptureEngine.captureAndSave(store: store)
            showIcon(
                symbol: "checkmark.rectangle",
                description: "Layout saved"
            )
            statusItem.button?.toolTip =
                "RestoreLayout — saved \(layout.windows.count) " +
                "window\(layout.windows.count == 1 ? "" : "s") " +
                "(\(slot.feedbackDescription))"
        } catch {
            showFailure(
                description: "Could not save layout",
                tooltip: "save failed: \(error.localizedDescription)"
            )
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.showBaseIcon()
        }
    }

    @objc private func setShortcutTarget(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let target = ShortcutTarget(rawValue: raw) else { return }
        do {
            let builtIn = DisplayConfiguration.current().builtIn?.info
            var library = try store.load(builtIn: builtIn) ?? LayoutLibrary()
            library.shortcutTarget = target
            try store.save(library)
        } catch {
            showFailure(
                description: "Could not change shortcut target",
                tooltip: "shortcut change failed: \(error.localizedDescription)"
            )
        }
    }

    @objc private func toggleLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func grantAccessibility() {
        promptForPermission()
    }

    // MARK: - Menu

    /// Everything the menu shows, derived from one display read and one
    /// library load. `library` is nil when `layouts.json` is unreadable.
    private struct MenuState {
        var trusted: Bool
        var configuration: DisplayConfiguration
        var library: LayoutLibrary?

        var multiDisplayLayout: Layout? {
            guard let library else { return nil }
            if case .multiDisplay(_, let layout) = RestoreEngine.select(
                target: .multiDisplay,
                library: library,
                configuration: configuration
            ) {
                return layout
            }
            return nil
        }

        var canRestoreLaptop: Bool { trusted && library?.laptop != nil }
        var canRestoreMultiDisplay: Bool { trusted && multiDisplayLayout != nil }

        /// Which restore item carries the ⌃⌥⌘R badge.
        var shortcutRestoresMultiDisplay: Bool {
            switch library?.shortcutTarget ?? .connectedDisplays {
            case .laptop: return false
            case .multiDisplay: return true
            case .connectedDisplays: return multiDisplayLayout != nil
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let configuration = DisplayConfiguration.current()
        let state = MenuState(
            trusted: AXPermission.isTrusted,
            configuration: configuration,
            library: try? (
                store.load(builtIn: configuration.builtIn?.info) ?? LayoutLibrary()
            )
        )

        if !state.trusted {
            menu.addItem(actionItem(
                "Grant Accessibility Access…",
                #selector(grantAccessibility)
            ))
            menu.addItem(.separator())
        }

        addActionItems(to: menu, state: state)
        menu.addItem(.separator())
        menu.addItem(shortcutTargetItem(state: state))
        menu.addItem(.separator())
        for line in statusLines(state: state) {
            let info = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }

        let login = actionItem("Launch at Login", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit RestoreLayout",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
    }

    private func addActionItems(to menu: NSMenu, state: MenuState) {
        let laptop = actionItem("Restore Laptop Layout", #selector(restoreLaptop))
        laptop.isEnabled = state.canRestoreLaptop
        let multi = actionItem(
            "Restore Multi-Display Layout",
            #selector(restoreMultiDisplay)
        )
        multi.isEnabled = state.canRestoreMultiDisplay
        setHotKeyBadge(on: state.shortcutRestoresMultiDisplay ? multi : laptop, key: "r")

        let save = actionItem("Save Current Layout", #selector(saveLayout))
        setHotKeyBadge(on: save, key: "s")
        save.isEnabled = state.trusted

        [laptop, multi, save].forEach(menu.addItem)
    }

    private func shortcutTargetItem(state: MenuState) -> NSMenuItem {
        let current = state.library?.shortcutTarget ?? .connectedDisplays
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for target in [ShortcutTarget.connectedDisplays, .laptop, .multiDisplay] {
            let item = actionItem(target.menuTitle, #selector(setShortcutTarget(_:)))
            item.representedObject = target.rawValue
            item.state = target == current ? .on : .off
            submenu.addItem(item)
        }
        let parent = NSMenuItem(title: "Shortcut Restores", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    private func statusLines(state: MenuState) -> [String] {
        guard let library = state.library else {
            return ["Layout file unreadable"]
        }
        let laptopLine = library.laptop.map {
            "Laptop layout: saved \(formattedDate($0.savedAt))"
        } ?? "Laptop layout: not saved"

        let count = state.configuration.externalCount
        let connectedLine: String
        if state.configuration.isLaptopOnly {
            connectedLine = "Connected displays: none external"
        } else {
            let prefix = "Connected displays (\(count) external)"
            connectedLine = state.multiDisplayLayout.map {
                "\(prefix): saved \(formattedDate($0.savedAt))"
            } ?? "\(prefix): not saved"
        }
        return [laptopLine, connectedLine]
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// Display-only: the Carbon hotkey does the real work.
    private func setHotKeyBadge(on item: NSMenuItem, key: String) {
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = [.control, .option, .command]
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private func formattedDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
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

    /// Warning icon now; the icon resets to base after 0.8s but the tooltip
    /// stays until the next feedback change.
    private func showFailure(description: String, tooltip: String) {
        showIcon(symbol: "exclamationmark.triangle", description: description)
        statusItem.button?.toolTip = "RestoreLayout — \(tooltip)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.showBaseIcon(preserveTooltip: true)
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

// MARK: - Display strings

private extension ShortcutTarget {
    var menuTitle: String {
        switch self {
        case .connectedDisplays: return "Layout for Connected Displays"
        case .laptop: return "Laptop Layout"
        case .multiDisplay: return "Multi-Display Layout"
        }
    }
}

private extension SaveSlot {
    var feedbackDescription: String {
        switch self {
        case .laptop:
            return "laptop"
        case .multiDisplay(let count):
            return count == 1 ? "1 external display" : "\(count) external displays"
        }
    }
}
