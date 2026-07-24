import AppKit
import Foundation

enum CaptureError: LocalizedError {
    case builtInDisplayNotFound

    var errorDescription: String? {
        switch self {
        case .builtInDisplayNotFound:
            "No built-in display was found."
        }
    }
}

enum CaptureEngine {
    @MainActor
    static func capture() throws -> Layout {
        guard let builtIn = Coordinates.builtInScreen() else {
            throw CaptureError.builtInDisplayNotFound
        }
        let groups = WindowEnumerator.visibleStandardWindows()
        var records: [WindowRecord] = []

        for group in groups {
            guard let bundleID = group.app.bundleIdentifier else { continue }
            let appName = group.app.localizedName ?? bundleID
            for (index, window) in group.windows.enumerated() {
                guard let globalFrame = window.frame else { continue }
                records.append(WindowRecord(
                    bundleID: bundleID,
                    appName: appName,
                    title: window.title,
                    indexInApp: index,
                    frame: Coordinates.builtInRelative(
                        fromAXGlobal: globalFrame,
                        builtInScreen: builtIn
                    )
                ))
            }
        }

        return Layout(
            savedAt: Date(),
            builtInSize: builtIn.frame.size,
            windows: records
        )
    }

    @MainActor
    @discardableResult
    static func captureAndSave(store: LayoutStore = LayoutStore()) throws -> Layout {
        let layout = try capture()
        try store.save(layout)
        return layout
    }

    @MainActor
    static func listDescription() throws -> String {
        guard let builtIn = Coordinates.builtInScreen() else {
            throw CaptureError.builtInDisplayNotFound
        }
        let groups = WindowEnumerator.visibleStandardWindows()
        var lines: [String] = []
        for group in groups {
            let bundleID = group.app.bundleIdentifier ?? "(no bundle id)"
            let appName = group.app.localizedName ?? bundleID
            lines.append("\(appName) [\(bundleID)]")
            for (index, window) in group.windows.enumerated() {
                guard let globalFrame = window.frame else { continue }
                let relative = Coordinates.builtInRelative(
                    fromAXGlobal: globalFrame,
                    builtInScreen: builtIn
                )
                lines.append(
                    "  [\(index)] \(window.title.debugDescription) " +
                    "AX \(format(globalFrame)) built-in \(format(relative))"
                )
            }
        }
        return lines.isEmpty ? "No visible standard windows found." : lines.joined(separator: "\n")
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
}

