import AppKit
import ApplicationServices

enum WindowEnumerator {
    @MainActor
    static func visibleStandardWindows()
        -> [(app: NSRunningApplication, windows: [AXWindow])]
    {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular,
                  !app.isTerminated,
                  app.processIdentifier != ownPID else {
                return nil
            }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var rawValue: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &rawValue
            )
            guard status == .success,
                  let elements = rawValue as? [AXUIElement] else {
                return nil
            }

            let windows = elements.compactMap { element -> AXWindow? in
                let window = AXWindow(element: element, appElement: appElement)
                guard window.role == kAXWindowRole,
                      window.subrole == kAXStandardWindowSubrole,
                      !window.isMinimized,
                      window.isSettable(kAXPositionAttribute as CFString),
                      window.isSettable(kAXSizeAttribute as CFString),
                      let frame = window.frame,
                      frame.width > 0,
                      frame.height > 0 else {
                    return nil
                }
                return window
            }
            return windows.isEmpty ? nil : (app: app, windows: windows)
        }
    }
}

