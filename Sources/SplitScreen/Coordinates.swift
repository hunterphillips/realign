import AppKit
import CoreGraphics

/// The canonical stored coordinate system is built-in-display-relative:
/// a frame origin is the offset from the built-in display's top-left corner,
/// measured in points, with x increasing rightward and y increasing downward.
/// AX global coordinates use the same axis directions. AppKit screen coordinates
/// are flipped here, and nowhere else, against `NSScreen.screens[0]`.
enum Coordinates {
    static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let displayID = displayID(of: screen) else { return false }
            return CGDisplayIsBuiltin(displayID) != 0
        }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    static func axGlobalOrigin(of screen: NSScreen) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        return axGlobalOrigin(
            appKitFrame: screen.frame,
            primaryScreenHeight: primaryHeight
        )
    }

    static func axGlobalOrigin(
        appKitFrame: CGRect,
        primaryScreenHeight: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: appKitFrame.minX,
            y: primaryScreenHeight - appKitFrame.maxY
        )
    }

    static func builtInRelative(
        fromAXGlobal frame: CGRect,
        builtInAXOrigin: CGPoint
    ) -> CGRect {
        CGRect(
            origin: CGPoint(
                x: frame.origin.x - builtInAXOrigin.x,
                y: frame.origin.y - builtInAXOrigin.y
            ),
            size: frame.size
        )
    }

    static func axGlobal(
        fromBuiltInRelative frame: CGRect,
        builtInAXOrigin: CGPoint
    ) -> CGRect {
        CGRect(
            origin: CGPoint(
                x: frame.origin.x + builtInAXOrigin.x,
                y: frame.origin.y + builtInAXOrigin.y
            ),
            size: frame.size
        )
    }

    static func builtInRelative(
        fromAXGlobal frame: CGRect,
        builtInScreen: NSScreen
    ) -> CGRect {
        builtInRelative(
            fromAXGlobal: frame,
            builtInAXOrigin: axGlobalOrigin(of: builtInScreen)
        )
    }

    static func axGlobal(
        fromBuiltInRelative frame: CGRect,
        builtInScreen: NSScreen
    ) -> CGRect {
        axGlobal(
            fromBuiltInRelative: frame,
            builtInAXOrigin: axGlobalOrigin(of: builtInScreen)
        )
    }
}

