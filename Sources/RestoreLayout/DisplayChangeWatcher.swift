import AppKit

/// Watches for display-set changes and calls `onChange` once per real change.
/// A single plug or unplug posts `didChangeScreenParametersNotification`
/// several times while macOS re-lays-out windows, so every notification
/// restarts a settle timer and only the last one acts.
@MainActor
final class DisplayChangeWatcher: NSObject {
    private let settleDelay: TimeInterval
    private let isEnabled: @MainActor () -> Bool
    private let onChange: @MainActor () -> Void
    private var previous = ""
    private var settleTimer: Timer?
    private var isObserving = false
    private var isHandlingChange = false

    /// Pure decision: restore only when enabled and the display set really changed.
    nonisolated static func shouldRestore(enabled: Bool, previous: String, current: String) -> Bool {
        enabled && previous != current
    }

    init(
        settleDelay: TimeInterval = 1.5,
        isEnabled: @escaping @MainActor () -> Bool,
        onChange: @escaping @MainActor () -> Void
    ) {
        self.settleDelay = settleDelay
        self.isEnabled = isEnabled
        self.onChange = onChange
    }

    // Selector-based observers are removed automatically on deallocation.

    func start() {
        guard !isObserving else { return }
        previous = DisplayConfiguration.current().fingerprint
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        isObserving = true
    }

    func stop() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        isObserving = false
        settleTimer?.invalidate()
        settleTimer = nil
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        // Restoring moves windows; ignore anything that arrives meanwhile.
        guard !isHandlingChange else { return }
        settleTimer?.invalidate()
        let timer = Timer(timeInterval: settleDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.settle() }
        }
        // Common modes so the timer still fires while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        settleTimer = timer
    }

    private func settle() {
        settleTimer = nil
        let current = DisplayConfiguration.current().fingerprint
        // No displays at all is a transient state (e.g. display sleep); keep
        // the last real set so waking does not count as a change.
        guard !current.isEmpty else { return }
        let restore = Self.shouldRestore(
            enabled: isEnabled(),
            previous: previous,
            current: current
        )
        // Record the new set even when disabled, so enabling later does not
        // replay an old change.
        previous = current
        guard restore else { return }
        isHandlingChange = true
        defer { isHandlingChange = false }
        onChange()
    }
}
