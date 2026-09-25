import AppKit
import Foundation

struct LiveWindowDescriptor: Equatable, Hashable, Sendable {
    var bundleID: String
    var appName: String
    var indexInApp: Int
}

struct WindowMatch: Equatable, Sendable {
    var saved: WindowRecord
    var live: LiveWindowDescriptor
}

struct MatchingResult: Equatable, Sendable {
    var matches: [WindowMatch]
    var unmatchedSaved: [WindowRecord]
    var unmatchedLive: [LiveWindowDescriptor]
}

struct RestoreReport: Equatable, Sendable, CustomStringConvertible {
    var restored = 0
    var skipped = 0
    var failed = 0
    var reasons: [String] = []
    /// Which layout was applied ("laptop layout" / "multi-display layout");
    /// empty when none was.
    var target: String = ""

    var summary: String {
        let counts = "Restored \(restored), skipped \(skipped), failed \(failed)"
        return target.isEmpty ? counts : "\(counts) (\(target))"
    }

    var description: String {
        ([summary] + reasons.map { "- \($0)" }).joined(separator: "\n")
    }
}

enum RestoreTarget: Equatable, Sendable {
    case laptop
    case multiDisplay
    /// Multi-display layout for the connected displays, else laptop.
    case connectedDisplays
}

extension RestoreTarget {
    init(_ shortcut: ShortcutTarget) {
        switch shortcut {
        case .connectedDisplays: self = .connectedDisplays
        case .laptop: self = .laptop
        case .multiDisplay: self = .multiDisplay
        }
    }
}

/// Outcome of choosing a layout for a restore target. Pure; no AX or NSScreen.
enum RestoreSelection: Equatable, Sendable {
    case laptop(Layout)
    case multiDisplay(key: String, layout: Layout)
    case noLaptopLayout
    case noExternalDisplays
    case noMatchingLayout
}

enum RestoreEngine {
    static func select(
        target: RestoreTarget,
        library: LayoutLibrary,
        configuration: DisplayConfiguration
    ) -> RestoreSelection {
        let laptop: RestoreSelection = library.laptop.map { .laptop($0) } ?? .noLaptopLayout
        guard target != .laptop else { return laptop }

        guard !configuration.isLaptopOnly else {
            return target == .multiDisplay ? .noExternalDisplays : laptop
        }
        if let key = DisplayConfiguration.matchingKey(
            for: configuration,
            in: library.multiDisplay
        ), let layout = library.multiDisplay[key] {
            return .multiDisplay(key: key, layout: layout)
        }
        return target == .multiDisplay ? .noMatchingLayout : laptop
    }

    /// The target the global shortcut and bare `--restore` use.
    @MainActor
    static func shortcutTarget(store: LayoutStore = LayoutStore()) throws -> RestoreTarget {
        let builtIn = DisplayConfiguration.current().builtIn?.info
        let library = try store.load(builtIn: builtIn) ?? LayoutLibrary()
        return RestoreTarget(library.shortcutTarget)
    }

    /// One warning per saved display whose resolved live display has a
    /// different size. Frames are applied as-is either way.
    static func sizeWarnings(
        saved: [DisplayInfo],
        resolved: [String: DisplayGeometry]
    ) -> [String] {
        saved.compactMap { info in
            guard let live = resolved[info.uuid],
                  !sizesMatch(info.size, live.info.size) else {
                return nil
            }
            let onto = live.info.uuid == info.uuid ? "" : " (using \(live.info.name))"
            return "\(info.name) size changed from \(format(info.size)) " +
                "to \(format(live.info.size))\(onto); applying saved points without scaling."
        }
    }

    /// Pairs nth-saved to nth-live within each bundle ID. Titles are
    /// intentionally absent from this algorithm because they are unstable.
    static func match(
        saved: [WindowRecord],
        live: [LiveWindowDescriptor]
    ) -> MatchingResult {
        let savedIDs = orderedUnique(saved.map(\.bundleID))
        var matches: [WindowMatch] = []
        var unmatchedSaved: [WindowRecord] = []
        var unmatchedLive: [LiveWindowDescriptor] = []

        for bundleID in savedIDs {
            let savedForApp = saved
                .filter { $0.bundleID == bundleID }
                .sorted { $0.indexInApp < $1.indexInApp }
            let liveForApp = live
                .filter { $0.bundleID == bundleID }
                .sorted { $0.indexInApp < $1.indexInApp }
            let pairCount = min(savedForApp.count, liveForApp.count)
            for index in 0..<pairCount {
                matches.append(WindowMatch(
                    saved: savedForApp[index],
                    live: liveForApp[index]
                ))
            }
            unmatchedSaved.append(contentsOf: savedForApp.dropFirst(pairCount))
            unmatchedLive.append(contentsOf: liveForApp.dropFirst(pairCount))
        }

        let savedIDSet = Set(savedIDs)
        unmatchedLive.append(contentsOf: live.filter {
            !savedIDSet.contains($0.bundleID)
        })
        return MatchingResult(
            matches: matches,
            unmatchedSaved: unmatchedSaved,
            unmatchedLive: unmatchedLive
        )
    }

    @MainActor
    static func restore(
        target: RestoreTarget,
        store: LayoutStore = LayoutStore()
    ) -> RestoreReport {
        var report = RestoreReport()
        let configuration = DisplayConfiguration.current()
        let library: LayoutLibrary
        do {
            library = try store.load(builtIn: configuration.builtIn?.info) ?? LayoutLibrary()
        } catch {
            report.failed += 1
            report.reasons.append("Could not load layouts: \(error.localizedDescription)")
            return report
        }

        let layout: Layout
        switch select(target: target, library: library, configuration: configuration) {
        case .laptop(let selected):
            layout = selected
            report.target = "laptop layout"
        case .multiDisplay(_, let selected):
            layout = selected
            report.target = "multi-display layout"
        case .noLaptopLayout:
            report.reasons.append("No laptop layout saved.")
            return report
        case .noExternalDisplays:
            report.reasons.append("No external displays connected.")
            return report
        case .noMatchingLayout:
            report.reasons.append("No layout saved for the connected displays.")
            return report
        }

        let anchors = configuration.resolveAll(layout.displays)
        report.reasons.append(contentsOf: sizeWarnings(saved: layout.displays, resolved: anchors))

        let groups = WindowEnumerator.visibleStandardWindows()
        var liveDescriptors: [LiveWindowDescriptor] = []
        var liveWindows: [LiveWindowDescriptor: AXWindow] = [:]
        for group in groups {
            guard let bundleID = group.app.bundleIdentifier else { continue }
            let appName = group.app.localizedName ?? bundleID
            for (index, window) in group.windows.enumerated() {
                let descriptor = LiveWindowDescriptor(
                    bundleID: bundleID,
                    appName: appName,
                    indexInApp: index
                )
                liveDescriptors.append(descriptor)
                liveWindows[descriptor] = window
            }
        }

        // Match before dropping unresolved records so nth-saved still pairs
        // with nth-live when one of an app's displays is missing.
        let matching = match(saved: layout.windows, live: liveDescriptors)
        report.skipped += matching.unmatchedSaved.count
        for record in matching.unmatchedSaved {
            report.reasons.append(
                "Skipped \(record.appName) window \(record.indexInApp): no matching live window."
            )
        }

        var anchored: [AnchoredMatch] = []
        for match in matching.matches {
            if let anchor = anchors[match.saved.displayUUID] {
                anchored.append(AnchoredMatch(match: match, anchor: anchor))
            } else {
                let name = layout.displays
                    .first { $0.uuid == match.saved.displayUUID }?
                    .name ?? match.saved.displayUUID
                report.skipped += 1
                report.reasons.append(
                    "Skipped \(match.saved.appName) window \(match.saved.indexInApp): " +
                    "display \(name) not connected."
                )
            }
        }

        let bundleIDs = orderedUnique(anchored.map { $0.match.saved.bundleID })
        for bundleID in bundleIDs {
            apply(
                appMatches: anchored.filter { $0.match.saved.bundleID == bundleID },
                liveWindows: liveWindows,
                report: &report
            )
        }
        return report
    }

    private struct AnchoredMatch {
        var match: WindowMatch
        var anchor: DisplayGeometry
    }

    @MainActor
    private static func apply(
        appMatches: [AnchoredMatch],
        liveWindows: [LiveWindowDescriptor: AXWindow],
        report: inout RestoreReport
    ) {
        guard let firstMatch = appMatches.first,
              let firstWindow = liveWindows[firstMatch.match.live] else {
            return
        }
        let enhancedWasEnabled = firstWindow.enhancedUserInterface == true
        if enhancedWasEnabled {
            firstWindow.enhancedUserInterface = false
        }
        defer {
            if enhancedWasEnabled {
                firstWindow.enhancedUserInterface = true
            }
        }

        for anchoredMatch in appMatches {
            let match = anchoredMatch.match
            guard let window = liveWindows[match.live] else {
                report.skipped += 1
                report.reasons.append(
                    "Skipped \(match.saved.appName) window \(match.saved.indexInApp): disappeared."
                )
                continue
            }
            if window.isFullscreen {
                report.skipped += 1
                report.reasons.append(
                    "Skipped \(match.saved.appName) window \(match.saved.indexInApp): fullscreen."
                )
                continue
            }
            let target = Coordinates.axGlobal(
                fromDisplayRelative: match.saved.frame,
                displayAXOrigin: anchoredMatch.anchor.axFrame.origin
            )
            if applyAndVerify(window: window, target: target) {
                report.restored += 1
            } else {
                report.failed += 1
                report.reasons.append(
                    "Failed \(match.saved.appName) window \(match.saved.indexInApp): " +
                    "frame did not match after bounded retries."
                )
            }
        }
    }

    private static func applyAndVerify(window: AXWindow, target: CGRect) -> Bool {
        let retryDelays: [TimeInterval] = [0, 0.025, 0.100]
        for delay in retryDelays {
            if delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
            // This order is intentional. macOS clamps a large window while it is
            // still associated with its old display.
            window.setSize(target.size)
            window.setPosition(target.origin)
            window.setSize(target.size)

            if let actual = window.frame, framesMatch(actual, target, tolerance: 2) {
                return true
            }
        }
        return false
    }

    static func framesMatch(
        _ lhs: CGRect,
        _ rhs: CGRect,
        tolerance: CGFloat
    ) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance
            && abs(lhs.origin.y - rhs.origin.y) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    private static func sizesMatch(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    }

    private static func format(_ size: CGSize) -> String {
        String(format: "%.0f×%.0f", size.width, size.height)
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

