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

    /// What to do once the display set has settled.
    enum Decision: Equatable, Sendable {
        /// Leave `previous` as is and do nothing.
        case ignore
        /// Record `current` as the new `previous`; no restore.
        case record
        /// Record `current` and restore.
        case restore
    }

    /// Pure decision for a settled display set.
    /// - An empty `current` (no displays at all) is transient, e.g. display
    ///   sleep; keep the last real set so waking does not count as a change.
    /// - An unchanged set, or a change while disabled, is only recorded, so
    ///   enabling later does not replay an old change.
    nonisolated static func decide(enabled: Bool, previous: String, current: String) -> Decision {
        guard !current.isEmpty else { return .ignore }
        // No previous set means the watcher started while no displays were
        // reported (e.g. launch at login during display sleep). The first
        // real set is a baseline, not a change.
        guard enabled && !previous.isEmpty && previous != current else { return .record }
        return .restore
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
        switch Self.decide(enabled: isEnabled(), previous: previous, current: current) {
        case .ignore:
            return
        case .record:
            previous = current
        case .restore:
            previous = current
            // `onChange` restores synchronously, so notifications posted
            // while windows move are delivered after it returns and simply
            // start a new settle timer, which then sees an unchanged set.
            onChange()
        }
    }
}
