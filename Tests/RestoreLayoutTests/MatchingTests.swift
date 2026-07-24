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
        let layout = Layout(
            savedAt: Date(timeIntervalSince1970: 1_786_000_000),
            builtInSize: CGSize(width: 1512, height: 982),
            windows: [
                record(
                    bundleID: "com.example.App",
                    title: "Window",
                    index: 0
                ),
            ]
        )
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RestoreLayoutTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: testDirectory) }
        let store = LayoutStore(
            fileURL: testDirectory.appendingPathComponent("layout.json")
        )

        try store.save(layout)

        #expect(try store.load() == layout)
    }

    private func record(
        bundleID: String,
        title: String = "",
        index: Int
    ) -> WindowRecord {
        WindowRecord(
            bundleID: bundleID,
            appName: bundleID,
            title: title,
            indexInApp: index,
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
