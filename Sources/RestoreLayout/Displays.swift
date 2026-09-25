import AppKit
import CoreGraphics

/// One live display with its AX-global frame. Built from NSScreen in exactly
/// one place (`DisplayConfiguration.current()`); everything else is pure.
struct DisplayGeometry: Equatable, Sendable {
    var info: DisplayInfo
    /// AX-global, top-left origin, points.
    var axFrame: CGRect
}

/// The set of displays connected right now.
struct DisplayConfiguration: Equatable, Sendable {
    var displays: [DisplayGeometry]

    /// Display UUIDs sorted and joined by `+`. Includes the built-in when it
    /// is present, so lid-open docked and clamshell are different keys.
    var fingerprint: String {
        Self.fingerprint(of: displays.map(\.info))
    }

    /// The only display is the built-in one.
    var isLaptopOnly: Bool {
        displays.count == 1 && displays[0].info.isBuiltIn
    }

    var builtIn: DisplayGeometry? {
        displays.first { $0.info.isBuiltIn }
    }

    var externalCount: Int {
        displays.filter { !$0.info.isBuiltIn }.count
    }

    static func fingerprint(of infos: [DisplayInfo]) -> String {
        infos.map(\.uuid).sorted().joined(separator: "+")
    }

    /// Largest-intersection assignment; ties → earlier display; no overlap →
    /// built-in, else displays[0]. nil only when there are no displays.
    func anchor(for axFrame: CGRect) -> DisplayGeometry? {
        var best: DisplayGeometry?
        var bestArea: CGFloat = 0
        for display in displays {
            let overlap = display.axFrame.intersection(axFrame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                best = display
                bestArea = area
            }
        }
        return best ?? builtIn ?? displays.first
    }

    /// Resolves every saved display at once. Exact UUID matches are claimed
    /// first; the signature fallback then only considers live displays that
    /// no exact match has claimed. Built-in fallback is shared (not claimed).
    /// Keyed by saved UUID; an absent key means unresolved (the caller skips
    /// that display's windows).
    func resolveAll(_ saved: [DisplayInfo]) -> [String: DisplayGeometry] {
        var resolved: [String: DisplayGeometry] = [:]
        var claimed = Set<String>()

        for info in saved where resolved[info.uuid] == nil {
            if let exact = displays.first(where: { $0.info.uuid == info.uuid }) {
                resolved[info.uuid] = exact
                claimed.insert(exact.info.uuid)
            }
        }
        for info in saved where resolved[info.uuid] == nil {
            let signature = Signature(info)
            if let similar = displays.first(where: {
                !claimed.contains($0.info.uuid) && Signature($0.info) == signature
            }) {
                resolved[info.uuid] = similar
                claimed.insert(similar.info.uuid)
            }
        }
        if let builtIn {
            for info in saved where resolved[info.uuid] == nil {
                resolved[info.uuid] = builtIn
            }
        }
        return resolved
    }

    /// Exact fingerprint key, else the key of the newest layout (greatest
    /// `savedAt`; ties → sorted key order) whose display multiset matches the
    /// live one on (vendor, model, size).
    static func matchingKey(
        for config: DisplayConfiguration,
        in library: [String: Layout]
    ) -> String? {
        let fingerprint = config.fingerprint
        if library[fingerprint] != nil {
            return fingerprint
        }
        let live = config.displays.map(\.info)
        return library
            .filter { signaturesMatch($0.value.displays, live) }
            .sorted {
                $0.value.savedAt != $1.value.savedAt
                    ? $0.value.savedAt > $1.value.savedAt
                    : $0.key < $1.key
            }
            .first?
            .key
    }

    /// True when both display lists have the same (vendor, model, size)
    /// multiset, i.e. they describe the same hardware regardless of UUIDs.
    static func signaturesMatch(_ lhs: [DisplayInfo], _ rhs: [DisplayInfo]) -> Bool {
        signatureCounts(lhs) == signatureCounts(rhs)
    }

    @MainActor
    static func current() -> DisplayConfiguration {
        let displays = NSScreen.screens.compactMap { screen -> DisplayGeometry? in
            guard let displayID = Coordinates.displayID(of: screen) else {
                return nil
            }
            let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)
                .map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
                // CGDirectDisplayIDs are not stable across reboots, so a
                // fingerprint containing this key may never match again. It
                // exists only so capture never throws.
                ?? "display-\(displayID)"
            let info = DisplayInfo(
                uuid: uuid,
                name: screen.localizedName,
                vendor: CGDisplayVendorNumber(displayID),
                model: CGDisplayModelNumber(displayID),
                isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
                size: screen.frame.size
            )
            return DisplayGeometry(
                info: info,
                axFrame: CGRect(
                    origin: Coordinates.axGlobalOrigin(of: screen),
                    size: screen.frame.size
                )
            )
        }
        return DisplayConfiguration(displays: displays)
    }

    /// Hardware identity used when a UUID no longer matches.
    private struct Signature: Hashable {
        var vendor: UInt32
        var model: UInt32
        var size: CGSize

        init(_ info: DisplayInfo) {
            vendor = info.vendor
            model = info.model
            size = info.size
        }
    }

    private static func signatureCounts(_ infos: [DisplayInfo]) -> [Signature: Int] {
        infos.reduce(into: [:]) { counts, info in
            counts[Signature(info), default: 0] += 1
        }
    }
}
