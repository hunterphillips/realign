import AppKit
import Foundation

enum CaptureError: LocalizedError {
    case noDisplays

    var errorDescription: String? {
        switch self {
        case .noDisplays:
            "No displays were found."
        }
    }
}

/// Where a save landed in the library.
enum SaveSlot: Equatable, Sendable {
    case laptop
    case multiDisplay(externalCount: Int)
}

enum CaptureEngine {
    /// Anchors each window to the display it overlaps most and stores its
    /// frame relative to that display.
    @MainActor
    static func capture(configuration: DisplayConfiguration) throws -> Layout {
        guard !configuration.displays.isEmpty else {
            throw CaptureError.noDisplays
        }
        let groups = WindowEnumerator.visibleStandardWindows()
        var records: [WindowRecord] = []

        for group in groups {
            guard let bundleID = group.app.bundleIdentifier else { continue }
            let appName = group.app.localizedName ?? bundleID
            for (index, window) in group.windows.enumerated() {
                guard let globalFrame = window.frame,
                      let anchor = configuration.anchor(for: globalFrame) else {
                    continue
                }
                records.append(WindowRecord(
                    bundleID: bundleID,
                    appName: appName,
                    title: window.title,
                    indexInApp: index,
                    displayUUID: anchor.info.uuid,
                    frame: Coordinates.displayRelative(
                        fromAXGlobal: globalFrame,
                        displayAXOrigin: anchor.axFrame.origin
                    )
                ))
            }
        }

        return Layout(
            savedAt: Date(),
            displays: configuration.displays.map(\.info),
            windows: records
        )
    }

    /// Saves to the laptop slot when only the built-in is connected, else to
    /// the multi-display slot keyed by the live fingerprint. An unreadable
    /// library aborts the save rather than being overwritten.
    @MainActor
    @discardableResult
    static func captureAndSave(
        store: LayoutStore = LayoutStore()
    ) throws -> (layout: Layout, slot: SaveSlot) {
        let configuration = DisplayConfiguration.current()
        let layout = try capture(configuration: configuration)
        var library = try store.load(builtIn: configuration.builtIn?.info) ?? LayoutLibrary()
        let slot: SaveSlot
        if configuration.isLaptopOnly {
            library.laptop = layout
            slot = .laptop
        } else {
            library.multiDisplay[configuration.fingerprint] = layout
            slot = .multiDisplay(externalCount: configuration.externalCount)
        }
        try store.save(library)
        return (layout, slot)
    }

    @MainActor
    static func listDescription() throws -> String {
        let configuration = DisplayConfiguration.current()
        guard !configuration.displays.isEmpty else {
            throw CaptureError.noDisplays
        }
        var lines = ["Displays:"]
        for (index, display) in configuration.displays.enumerated() {
            let tag = display.info.isBuiltIn ? " built-in" : ""
            lines.append(
                "  [\(index)] \(display.info.name)\(tag) " +
                "\(format(display.info.size)) at \(format(display.axFrame.origin)) " +
                "\(display.info.uuid)"
            )
        }
        lines.append("")

        let groups = WindowEnumerator.visibleStandardWindows()
        var windowLines: [String] = []
        for group in groups {
            let bundleID = group.app.bundleIdentifier ?? "(no bundle id)"
            let appName = group.app.localizedName ?? bundleID
            windowLines.append("\(appName) [\(bundleID)]")
            for (index, window) in group.windows.enumerated() {
                guard let globalFrame = window.frame,
                      let anchor = configuration.anchor(for: globalFrame) else {
                    continue
                }
                let relative = Coordinates.displayRelative(
                    fromAXGlobal: globalFrame,
                    displayAXOrigin: anchor.axFrame.origin
                )
                windowLines.append(
                    "  [\(index)] \(window.title.debugDescription) " +
                    "AX \(format(globalFrame)) \(anchor.info.name) \(format(relative))"
                )
            }
        }
        lines.append(contentsOf: windowLines.isEmpty
            ? ["No visible standard windows found."]
            : windowLines)
        return lines.joined(separator: "\n")
    }

    private static func format(_ frame: CGRect) -> String {
        String(
            format: "(x:%.1f y:%.1f w:%.1f h:%.1f)",
            frame.origin.x,
            frame.origin.y,
            frame.width,
            frame.height
        )
    }

    private static func format(_ size: CGSize) -> String {
        String(format: "%.0f×%.0f", size.width, size.height)
    }

    private static func format(_ point: CGPoint) -> String {
        String(format: "(%.0f, %.0f)", point.x, point.y)
    }
}
