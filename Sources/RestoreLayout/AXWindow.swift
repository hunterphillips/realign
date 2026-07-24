import ApplicationServices
import Foundation

/// Thin AX wrapper. Enumeration owns policy; this type only reads and writes
/// attributes on one window and its parent application element.
final class AXWindow {
    let element: AXUIElement
    let appElement: AXUIElement

    init(element: AXUIElement, appElement: AXUIElement) {
        self.element = element
        self.appElement = appElement
    }

    var frame: CGRect? {
        guard let position = pointAttribute(kAXPositionAttribute as CFString),
              let size = sizeAttribute(kAXSizeAttribute as CFString) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    var title: String {
        stringAttribute(kAXTitleAttribute as CFString) ?? ""
    }

    var role: String? {
        stringAttribute(kAXRoleAttribute as CFString)
    }

    var subrole: String? {
        stringAttribute(kAXSubroleAttribute as CFString)
    }

    var isMinimized: Bool {
        boolAttribute(kAXMinimizedAttribute as CFString) ?? false
    }

    var isFullscreen: Bool {
        boolAttribute("AXFullScreen" as CFString) ?? false
    }

    func isSettable(_ attribute: CFString) -> Bool {
        var settable = DarwinBoolean(false)
        let status = AXUIElementIsAttributeSettable(element, attribute, &settable)
        return status == .success && settable.boolValue
    }

    @discardableResult
    func setPosition(_ position: CGPoint) -> AXError {
        var mutablePosition = position
        guard let value = AXValueCreate(.cgPoint, &mutablePosition) else {
            return .illegalArgument
        }
        return AXUIElementSetAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            value
        )
    }

    @discardableResult
    func setSize(_ size: CGSize) -> AXError {
        var mutableSize = size
        guard let value = AXValueCreate(.cgSize, &mutableSize) else {
            return .illegalArgument
        }
        return AXUIElementSetAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            value
        )
    }

    var enhancedUserInterface: Bool? {
        get { appBoolAttribute("AXEnhancedUserInterface" as CFString) }
        set {
            guard let newValue else { return }
            AXUIElementSetAttributeValue(
                appElement,
                "AXEnhancedUserInterface" as CFString,
                NSNumber(value: newValue)
            )
        }
    }

    private func copyAttribute(
        _ attribute: CFString,
        from target: AXUIElement? = nil
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            target ?? element,
            attribute,
            &value
        )
        return status == .success ? value : nil
    }

    private func pointAttribute(_ attribute: CFString) -> CGPoint? {
        guard let value = copyAttribute(attribute),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func sizeAttribute(_ attribute: CFString) -> CGSize? {
        guard let value = copyAttribute(attribute),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func stringAttribute(_ attribute: CFString) -> String? {
        copyAttribute(attribute) as? String
    }

    private func boolAttribute(_ attribute: CFString) -> Bool? {
        (copyAttribute(attribute) as? NSNumber)?.boolValue
    }

    private func appBoolAttribute(_ attribute: CFString) -> Bool? {
        (copyAttribute(attribute, from: appElement) as? NSNumber)?.boolValue
    }
}
