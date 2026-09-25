import Foundation

/// Identity and size of one display, as recorded in a saved layout.
struct DisplayInfo: Codable, Equatable, Hashable, Sendable {
    /// `CGDisplayCreateUUIDFromDisplayID`, string form.
    var uuid: String
    /// `NSScreen.localizedName`; display only, never used for matching.
    var name: String
    var vendor: UInt32
    var model: UInt32
    var isBuiltIn: Bool
    /// Points.
    var size: CGSize
}

struct WindowRecord: Codable, Equatable, Sendable {
    var bundleID: String
    var appName: String
    var title: String
    var indexInApp: Int
    /// Anchor display: a `DisplayInfo.uuid` in the owning `Layout.displays`.
    var displayUUID: String
    /// Anchor-display-relative, top-left-origin coordinates in points.
    var frame: CGRect
}

struct Layout: Codable, Equatable, Sendable {
    var savedAt: Date
    var displays: [DisplayInfo]
    var windows: [WindowRecord]
}

enum ShortcutTarget: String, Codable, Sendable {
    /// Multi-display layout for the current display set, else laptop.
    case connectedDisplays
    case laptop
    case multiDisplay
}

struct LayoutLibrary: Codable, Equatable, Sendable {
    /// The newest library format this binary reads and writes.
    static let currentVersion = 2

    var version: Int = currentVersion
    var shortcutTarget: ShortcutTarget = .connectedDisplays
    var laptop: Layout?
    /// Keyed by `DisplayConfiguration.fingerprint`.
    var multiDisplay: [String: Layout] = [:]
}

/// Where a save landed in the library.
enum SaveSlot: Equatable, Sendable {
    case laptop
    case multiDisplay(externalCount: Int)
}

extension LayoutLibrary {
    /// Stores `layout` in the laptop slot when only the built-in is connected,
    /// else under the live fingerprint. Other entries with the same hardware
    /// signature (e.g. a different dock with the same monitor model) are left
    /// alone: `DisplayConfiguration.matchingKey`'s newest-`savedAt` fallback
    /// already keeps a stale entry from shadowing this one.
    mutating func store(_ layout: Layout, for configuration: DisplayConfiguration) -> SaveSlot {
        if configuration.isLaptopOnly {
            laptop = layout
            return .laptop
        }
        multiDisplay[configuration.fingerprint] = layout
        return .multiDisplay(externalCount: configuration.externalCount)
    }
}

extension LayoutLibrary {
    /// Missing keys take their defaults; an unknown `shortcutTarget` falls
    /// back to `.connectedDisplays` instead of failing the whole library.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version)
            ?? Self.currentVersion
        shortcutTarget = try container
            .decodeIfPresent(String.self, forKey: .shortcutTarget)
            .flatMap(ShortcutTarget.init(rawValue:)) ?? .connectedDisplays
        laptop = try container.decodeIfPresent(Layout.self, forKey: .laptop)
        multiDisplay = try container.decodeIfPresent(
            [String: Layout].self,
            forKey: .multiDisplay
        ) ?? [:]
    }
}

/// The v1 `layout.json` shape: one layout, frames relative to the built-in
/// display, no per-window anchor. Decoded only for migration.
struct LegacyLayoutV1: Decodable {
    struct Window: Decodable {
        var bundleID: String
        var appName: String
        var title: String
        var indexInApp: Int
        var frame: CGRect
    }

    var savedAt: Date
    var builtInSize: CGSize
    var windows: [Window]
}

extension Layout {
    /// Anchors every v1 record to the built-in display. v1 frames were already
    /// built-in-relative, so they carry over untouched. The stored anchor keeps
    /// the v1 `builtInSize`, since that is the size the frames were saved at.
    static func migrated(fromV1 legacy: LegacyLayoutV1, builtIn: DisplayInfo) -> Layout {
        var anchor = builtIn
        anchor.size = legacy.builtInSize
        return Layout(
            savedAt: legacy.savedAt,
            displays: [anchor],
            windows: legacy.windows.map { window in
                WindowRecord(
                    bundleID: window.bundleID,
                    appName: window.appName,
                    title: window.title,
                    indexInApp: window.indexInApp,
                    displayUUID: builtIn.uuid,
                    frame: window.frame
                )
            }
        )
    }
}
