import Foundation

struct WindowRecord: Codable, Equatable, Sendable {
    var bundleID: String
    var appName: String
    var title: String
    var indexInApp: Int
    /// Built-in-display-relative, top-left-origin coordinates in points.
    var frame: CGRect
}

struct Layout: Codable, Equatable, Sendable {
    var savedAt: Date
    var builtInSize: CGSize
    var windows: [WindowRecord]
}

