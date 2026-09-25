import CoreGraphics
import Foundation
import Testing
@testable import RestoreLayout

@Suite("Window matching and persistence")
struct MatchingTests {
    @Test func equalCountsPairInIndexOrderAndIgnoreTitles() {
        let saved = [
            record(bundleID: "com.example.Browser", title: "Old tab", index: 1),
            record(bundleID: "com.example.Browser", title: "Another old tab", index: 0),
        ]
        let live = [
            liveWindow(bundleID: "com.example.Browser", index: 0),
            liveWindow(bundleID: "com.example.Browser", index: 1),
        ]

        let result = RestoreEngine.match(saved: saved, live: live)

        #expect(result.matches.map(\.saved.indexInApp) == [0, 1])
        #expect(result.matches.map(\.live.indexInApp) == [0, 1])
        #expect(result.unmatchedSaved.isEmpty)
        #expect(result.unmatchedLive.isEmpty)
    }

    @Test func moreSavedThanLiveSkipsOnlyExtraSaved() {
        let result = RestoreEngine.match(
            saved: [
                record(bundleID: "app", index: 0),
                record(bundleID: "app", index: 1),
            ],
            live: [liveWindow(bundleID: "app", index: 0)]
        )

        #expect(result.matches.count == 1)
        #expect(result.unmatchedSaved.map(\.indexInApp) == [1])
        #expect(result.unmatchedLive.isEmpty)
    }

    @Test func moreLiveThanSavedLeavesExtraLiveUntouched() {
        let result = RestoreEngine.match(
            saved: [record(bundleID: "app", index: 0)],
            live: [
                liveWindow(bundleID: "app", index: 0),
                liveWindow(bundleID: "app", index: 1),
            ]
        )

        #expect(result.matches.count == 1)
        #expect(result.unmatchedSaved.isEmpty)
        #expect(result.unmatchedLive.map(\.indexInApp) == [1])
    }

    @Test func absentAppLeavesSavedRecordsUnmatched() {
        let result = RestoreEngine.match(
            saved: [record(bundleID: "missing", index: 0)],
            live: [liveWindow(bundleID: "other", index: 0)]
        )

        #expect(result.matches.isEmpty)
        #expect(result.unmatchedSaved.map(\.bundleID) == ["missing"])
        #expect(result.unmatchedLive.map(\.bundleID) == ["other"])
    }

    @Test func preservesAppAndWindowOrder() {
        let saved = [
            record(bundleID: "first", index: 1),
            record(bundleID: "first", index: 0),
            record(bundleID: "second", index: 0),
        ]
        let live = [
            liveWindow(bundleID: "second", index: 0),
            liveWindow(bundleID: "first", index: 1),
            liveWindow(bundleID: "first", index: 0),
        ]

        let result = RestoreEngine.match(saved: saved, live: live)

        #expect(
            result.matches.map { "\($0.saved.bundleID):\($0.saved.indexInApp)" }
                == ["first:0", "first:1", "second:0"]
        )
    }

    @Test func layoutJSONRoundTrip() throws {
        let laptop = Layout(
            savedAt: Date(timeIntervalSince1970: 1_786_000_000),
            displays: [Self.builtIn],
            windows: [record(bundleID: "com.example.App", title: "Window", index: 0)]
        )
        let docked = Layout(
            savedAt: Date(timeIntervalSince1970: 1_786_000_100),
            displays: [Self.builtIn, Self.dell],
            windows: [
                record(bundleID: "com.example.App", index: 0),
                record(bundleID: "com.example.App", index: 1, displayUUID: Self.dell.uuid),
            ]
        )
        let dockedKey = DisplayConfiguration.fingerprint(of: docked.displays)
        let library = LayoutLibrary(
            shortcutTarget: .multiDisplay,
            laptop: laptop,
            multiDisplay: [dockedKey: docked]
        )
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.save(library)

        #expect(try store.load(builtIn: Self.builtIn) == library)
    }

    @Test func migratesV1LayoutIntoLaptopSlot() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data(Self.v1LayoutJSON.utf8).write(to: store.legacyFileURL)
        // The live built-in has a different size than the v1 file recorded.
        var liveBuiltIn = Self.builtIn
        liveBuiltIn.size = CGSize(width: 1512, height: 982)

        let library = try #require(try store.load(builtIn: liveBuiltIn))
        let laptop = try #require(library.laptop)
        var expectedAnchor = liveBuiltIn
        expectedAnchor.size = CGSize(width: 1728, height: 1117)

        #expect(library.multiDisplay.isEmpty)
        #expect(laptop.displays == [expectedAnchor])
        #expect(laptop.savedAt == ISO8601DateFormatter().date(from: "2026-09-02T02:00:43Z"))
        #expect(laptop.windows.map(\.displayUUID) == [Self.builtIn.uuid, Self.builtIn.uuid])
        #expect(laptop.windows.map(\.bundleID) == ["com.google.Chrome", "com.mitchellh.ghostty"])
        #expect(laptop.windows.map(\.frame) == [
            CGRect(x: 571, y: 33, width: 1157, height: 1041),
            CGRect(x: 0, y: 34, width: 570, height: 1042),
        ])
        // Migration is read-only: v2 is written on the next save.
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: store.legacyFileURL.path))
    }

    @Test func migrationInClamshellAnchorsToBuiltInPlaceholder() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data(Self.v1LayoutJSON.utf8).write(to: store.legacyFileURL)

        let laptop = try #require(try store.load(builtIn: nil)?.laptop)
        let placeholder = try #require(laptop.displays.first)

        #expect(laptop.displays.count == 1)
        #expect(placeholder.isBuiltIn)
        #expect(placeholder.size == CGSize(width: 1728, height: 1117))
        #expect(laptop.windows.allSatisfy { $0.displayUUID == placeholder.uuid })
    }

    @Test func loadThrowsOnInvalidLibraryJSON() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data("{ not json".utf8).write(to: store.fileURL)

        #expect(throws: (any Error).self) {
            try store.load(builtIn: Self.builtIn)
        }
    }

    @Test func loadThrowsOnNewerLibraryVersion() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.save(LayoutLibrary(version: LayoutLibrary.currentVersion + 1))

        #expect(throws: LayoutStoreError.self) {
            try store.load(builtIn: Self.builtIn)
        }
    }

    @Test func loadPrefersV2LibraryOverV1File() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = LayoutLibrary(
            shortcutTarget: .laptop,
            laptop: Layout(
                savedAt: Date(timeIntervalSince1970: 1_786_000_000),
                displays: [Self.builtIn],
                windows: [record(bundleID: "com.example.V2", index: 0)]
            )
        )
        try store.save(library)
        try Data(Self.v1LayoutJSON.utf8).write(to: store.legacyFileURL)

        #expect(try store.load(builtIn: Self.builtIn) == library)
    }

    @Test func libraryDecodingIsTolerant() throws {
        let decoder = JSONDecoder()
        #expect(
            try decoder.decode(LayoutLibrary.self, from: Data(#"{"laptop": null}"#.utf8))
                == LayoutLibrary()
        )
        #expect(
            try decoder.decode(
                LayoutLibrary.self,
                from: Data(#"{"shortcutTarget": "bogus"}"#.utf8)
            ).shortcutTarget == .connectedDisplays
        )
    }

    @Test func loadReturnsNilWhenNoFileExists() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(try store.load(builtIn: Self.builtIn) == nil)
    }

    private static let builtIn = DisplayInfo(
        uuid: "37D8832A-2D66-02CA-B9F7-8F30A301B230",
        name: "Built-in Retina Display",
        vendor: 1552,
        model: 41053,
        isBuiltIn: true,
        size: CGSize(width: 1728, height: 1117)
    )

    private static let dell = DisplayInfo(
        uuid: "DA3DD560-1F03-4878-B206-5C6BBC3BEF60",
        name: "DELL U2415",
        vendor: 4268,
        model: 41146,
        isBuiltIn: false,
        size: CGSize(width: 1920, height: 1200)
    )

    /// Shape of the real v1 `layout.json`.
    private static let v1LayoutJSON = """
    {
      "builtInSize" : [ 1728, 1117 ],
      "savedAt" : "2026-09-02T02:00:43Z",
      "windows" : [
        {
          "appName" : "Google Chrome",
          "bundleID" : "com.google.Chrome",
          "frame" : [ [ 571, 33 ], [ 1157, 1041 ] ],
          "indexInApp" : 0,
          "title" : "Focus - Google Chrome - Hunter"
        },
        {
          "appName" : "Ghostty",
          "bundleID" : "com.mitchellh.ghostty",
          "frame" : [ [ 0, 34 ], [ 570, 1042 ] ],
          "indexInApp" : 0,
          "title" : "second-brain"
        }
      ]
    }
    """

    private func makeStore() -> (LayoutStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RestoreLayoutTests-\(UUID().uuidString)")
        let store = LayoutStore(fileURL: directory.appendingPathComponent("layouts.json"))
        return (store, directory)
    }

    private func record(
        bundleID: String,
        title: String = "",
        index: Int,
        displayUUID: String = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
    ) -> WindowRecord {
        WindowRecord(
            bundleID: bundleID,
            appName: bundleID,
            title: title,
            indexInApp: index,
            displayUUID: displayUUID,
            frame: CGRect(x: index * 10, y: index * 20, width: 500, height: 400)
        )
    }

    private func liveWindow(
        bundleID: String,
        index: Int
    ) -> LiveWindowDescriptor {
        LiveWindowDescriptor(
            bundleID: bundleID,
            appName: bundleID,
            indexInApp: index
        )
    }
}
