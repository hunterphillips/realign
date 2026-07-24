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

    var summary: String {
        "Restored \(restored), skipped \(skipped), failed \(failed)"
    }

    var description: String {
        ([summary] + reasons.map { "- \($0)" }).joined(separator: "\n")
    }
}

enum RestoreEngine {
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
    static func restore(store: LayoutStore = LayoutStore()) -> RestoreReport {
        var report = RestoreReport()
        let layout: Layout
        do {
            guard let loaded = try store.load() else {
                report.reasons.append("No saved layout. Save a layout first.")
                return report
            }
            layout = loaded
        } catch {
            report.failed += 1
            report.reasons.append("Could not load layout: \(error.localizedDescription)")
            return report
        }

        guard let builtIn = Coordinates.builtInScreen() else {
            report.failed += layout.windows.count
            report.reasons.append("No built-in display was found.")
            return report
        }
        if !sizesMatch(layout.builtInSize, builtIn.frame.size) {
            report.reasons.append(
                "Built-in display size changed from \(format(layout.builtInSize)) " +
                "to \(format(builtIn.frame.size)); applying saved points without scaling."
            )
        }

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

        let matching = match(saved: layout.windows, live: liveDescriptors)
        report.skipped += matching.unmatchedSaved.count
        for record in matching.unmatchedSaved {
            report.reasons.append(
                "Skipped \(record.appName) window \(record.indexInApp): no matching live window."
            )
        }

        let bundleIDs = orderedUnique(matching.matches.map { $0.saved.bundleID })
        for bundleID in bundleIDs {
            let appMatches = matching.matches.filter { $0.saved.bundleID == bundleID }
            apply(
                appMatches: appMatches,
                liveWindows: liveWindows,
                builtIn: builtIn,
                report: &report
            )
        }
        return report
    }

    @MainActor
    private static func apply(
        appMatches: [WindowMatch],
        liveWindows: [LiveWindowDescriptor: AXWindow],
        builtIn: NSScreen,
        report: inout RestoreReport
    ) {
        guard let firstMatch = appMatches.first,
              let firstWindow = liveWindows[firstMatch.live] else {
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

        for match in appMatches {
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
                fromBuiltInRelative: match.saved.frame,
                builtInScreen: builtIn
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

