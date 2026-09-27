import AppKit
import Darwin
import Foundation

private func printHelp() {
    print("""
    Realign — save and restore visible window layouts across displays

    Usage:
      Realign                     Run the menu bar app
      Realign --save              Save the layout for the connected displays
                                        (laptop layout when only the built-in is on)
      Realign --restore           Restore per the shortcut target setting
      Realign --restore laptop    Restore the laptop layout
      Realign --restore multi     Restore the layout for the connected displays
      Realign --list              List displays, visible standard windows and frames
      Realign --help              Show this help

    Global shortcuts: ⌃⌥⌘S saves, ⌃⌥⌘R restores (per the shortcut target).
    """)
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
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
            fail("Realign list failed: \(error.localizedDescription)")
        }

    case "--save":
        requireAccessibility()
        do {
            let store = LayoutStore()
            let (layout, slot) = try CaptureEngine.captureAndSave(store: store)
            let destination = switch slot {
            case .laptop:
                "the laptop layout"
            case .multiDisplay(let count):
                "the multi-display layout (\(count) external display\(count == 1 ? "" : "s"))"
            }
            let count = layout.windows.count
            print("Saved \(count) window\(count == 1 ? "" : "s") to \(destination)")
            print(store.fileURL.path)
            exit(0)
        } catch {
            fail("Realign save failed: \(error.localizedDescription)")
        }

    case "--restore":
        requireAccessibility()
        let target: RestoreTarget
        switch arguments.dropFirst().first {
        case nil:
            do {
                target = try RestoreEngine.shortcutTarget()
            } catch {
                fail("Realign restore failed: \(error.localizedDescription)")
            }
        case "laptop":
            target = .laptop
        case "multi":
            target = .multiDisplay
        case let other?:
            FileHandle.standardError.write(Data("Unknown restore target: \(other)\n".utf8))
            printHelp()
            exit(1)
        }
        let report = RestoreEngine.restore(target: target)
        print(report)
        exit(report.applied && report.failed == 0 ? 0 : 1)

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

