import AppKit
import Darwin
import Foundation

private func printHelp() {
    print("""
    RestoreLayout — save and restore visible window layouts on the built-in display

    Usage:
      RestoreLayout                 Run the menu bar app
      RestoreLayout --save          Save the current visible-window layout
      RestoreLayout --restore       Restore the saved layout
      RestoreLayout --list          List visible standard windows and frames
      RestoreLayout --help          Show this help

    Global shortcuts: ⌃⌥⌘S saves, ⌃⌥⌘R restores.
    """)
}

private func requireAccessibility() {
    guard !AXPermission.isTrusted else { return }
    FileHandle.standardError.write(Data((AXPermission.instructions + "\n").utf8))
    exit(2)
}

let arguments = Array(CommandLine.arguments.dropFirst())
if let command = arguments.first {
    switch command {
    case "--help", "-h":
        printHelp()
        exit(0)

    case "--list":
        requireAccessibility()
        do {
            print(try CaptureEngine.listDescription())
            exit(0)
        } catch {
            FileHandle.standardError.write(
                Data("RestoreLayout list failed: \(error.localizedDescription)\n".utf8)
            )
            exit(1)
        }

    case "--save":
        requireAccessibility()
        do {
            let store = LayoutStore()
            let layout = try CaptureEngine.captureAndSave(store: store)
            print("Saved \(layout.windows.count) windows to \(store.fileURL.path)")
            exit(0)
        } catch {
            FileHandle.standardError.write(
                Data("RestoreLayout save failed: \(error.localizedDescription)\n".utf8)
            )
            exit(1)
        }

    case "--restore":
        requireAccessibility()
        let report = RestoreEngine.restore()
        print(report)
        exit(report.failed == 0 ? 0 : 1)

    default:
        FileHandle.standardError.write(
            Data("Unknown argument: \(command)\n".utf8)
        )
        printHelp()
        exit(1)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()

