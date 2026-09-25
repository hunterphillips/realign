import Foundation

enum LayoutStoreError: LocalizedError {
    case newerVersion(Int)

    var errorDescription: String? {
        switch self {
        case .newerVersion(let version):
            "layouts.json is version \(version), newer than this RestoreLayout " +
                "understands (\(LayoutLibrary.currentVersion)). Update RestoreLayout."
        }
    }
}

struct LayoutStore: Sendable {
    /// v2 library file (`layouts.json`).
    let fileURL: URL
    /// v1 single-layout file (`layout.json`) in the same directory. Read only
    /// for migration and left in place afterwards.
    let legacyFileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.homeDirectoryForCurrentUser
            self.fileURL = base
                .appendingPathComponent("RestoreLayout", isDirectory: true)
                .appendingPathComponent("layouts.json", isDirectory: false)
        }
        legacyFileURL = self.fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("layout.json", isDirectory: false)
    }

    func save(_ library: LayoutLibrary) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(library)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Loads the v2 library; if absent, migrates a v1 layout into the laptop
    /// slot without writing (the next save writes v2). `builtIn` is the live
    /// built-in display, or nil in clamshell mode, in which case migrated
    /// records anchor to a placeholder that still resolves to the built-in
    /// through the `isBuiltIn` fallback. Returns nil when neither file exists.
    /// Throws on a library newer than this binary so it is never rewritten
    /// in the older format.
    func load(builtIn: DisplayInfo?) throws -> LayoutLibrary? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            // Check the version before the full decode so a newer file with an
            // unknown shape reports `newerVersion`, not a decoding error.
            let header = try decoder.decode(VersionHeader.self, from: data)
            if let version = header.version, version > LayoutLibrary.currentVersion {
                throw LayoutStoreError.newerVersion(version)
            }
            return try decoder.decode(LayoutLibrary.self, from: data)
        }
        guard fileManager.fileExists(atPath: legacyFileURL.path) else {
            return nil
        }
        // A broken v1 file does not block saves: the never-overwrite rule
        // protects `layouts.json`, and writing it leaves `layout.json` alone.
        let legacy: LegacyLayoutV1
        do {
            legacy = try decoder.decode(
                LegacyLayoutV1.self,
                from: Data(contentsOf: legacyFileURL)
            )
        } catch {
            FileHandle.standardError.write(Data(
                "RestoreLayout: ignoring unreadable \(legacyFileURL.path): \(error.localizedDescription)\n".utf8
            ))
            return nil
        }
        let anchor = builtIn ?? DisplayInfo(
            uuid: "builtin",
            name: "Built-in Display",
            vendor: 0,
            model: 0,
            isBuiltIn: true,
            size: legacy.builtInSize
        )
        return LayoutLibrary(laptop: .migrated(fromV1: legacy, builtIn: anchor))
    }

    private struct VersionHeader: Decodable {
        var version: Int?
    }
}
