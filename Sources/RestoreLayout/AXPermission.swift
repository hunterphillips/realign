import ApplicationServices
import Foundation

enum AXPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func ensureTrusted() -> Bool {
        // The literal is the public value of kAXTrustedCheckOptionPrompt. Using
        // it avoids Swift 6 treating the imported C global as mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static let instructions = """
    RestoreLayout needs Accessibility access to inspect and move windows.
    Open System Settings → Privacy & Security → Accessibility, enable RestoreLayout
    (or the terminal running this CLI), then run the command again.
    """
}
