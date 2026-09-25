import CoreGraphics
import Foundation
import Testing
@testable import RestoreLayout

/// Routing table for restore targets, using the probed display fixtures.
@Suite("Restore selection")
struct RestoreSelectionTests {
    let laptopOnly = DisplayConfiguration(displays: [DisplaysTests.builtIn])
    let docked = DisplayConfiguration(
        displays: [DisplaysTests.builtIn, DisplaysTests.portrait, DisplaysTests.dell]
    )
    let laptopLayout = Self.layout([DisplaysTests.builtIn.info], savedAt: 1)
    var dockedLayout: Layout { Self.layout(docked.displays.map(\.info), savedAt: 2) }

    // MARK: - Laptop

    @Test func laptopTargetUsesLaptopLayout() {
        let library = LayoutLibrary(
            laptop: laptopLayout,
            multiDisplay: [docked.fingerprint: dockedLayout]
        )
        #expect(select(.laptop, library, docked) == .laptop(laptopLayout))
    }

    @Test func laptopTargetWithoutLaptopLayout() {
        let library = LayoutLibrary(multiDisplay: [docked.fingerprint: dockedLayout])
        #expect(select(.laptop, library, docked) == .noLaptopLayout)
    }

    // MARK: - Multi-display

    @Test func multiTargetWhenLaptopOnly() {
        let library = LayoutLibrary(
            laptop: laptopLayout,
            multiDisplay: [docked.fingerprint: dockedLayout]
        )
        #expect(select(.multiDisplay, library, laptopOnly) == .noExternalDisplays)
    }

    @Test func multiTargetWithNoMatchingKey() {
        let other = Self.layout([DisplaysTests.builtIn.info, DisplaysTests.dell.info], savedAt: 3)
        let library = LayoutLibrary(
            laptop: laptopLayout,
            multiDisplay: [DisplayConfiguration.fingerprint(of: other.displays): other]
        )
        #expect(select(.multiDisplay, library, docked) == .noMatchingLayout)
    }

    @Test func multiTargetWithExactKey() {
        let library = LayoutLibrary(multiDisplay: [docked.fingerprint: dockedLayout])
        #expect(
            select(.multiDisplay, library, docked)
                == .multiDisplay(key: docked.fingerprint, layout: dockedLayout)
        )
    }

    @Test func multiTargetWithSignatureFallbackKey() {
        var renamedDell = DisplaysTests.dell.info
        renamedDell.uuid = "11111111-1111-1111-1111-111111111111"
        let saved = Self.layout(
            [DisplaysTests.builtIn.info, DisplaysTests.portrait.info, renamedDell],
            savedAt: 4
        )
        let savedKey = DisplayConfiguration.fingerprint(of: saved.displays)
        let library = LayoutLibrary(multiDisplay: [savedKey: saved])
        #expect(
            select(.multiDisplay, library, docked)
                == .multiDisplay(key: savedKey, layout: saved)
        )
    }

    // MARK: - Connected displays

    @Test func connectedDisplaysPrefersMatchingMultiLayout() {
        let library = LayoutLibrary(
            laptop: laptopLayout,
            multiDisplay: [docked.fingerprint: dockedLayout]
        )
        #expect(
            select(.connectedDisplays, library, docked)
                == .multiDisplay(key: docked.fingerprint, layout: dockedLayout)
        )
    }

    @Test func connectedDisplaysFallsThroughToLaptopWhenNoMatch() {
        let library = LayoutLibrary(laptop: laptopLayout)
        #expect(select(.connectedDisplays, library, docked) == .laptop(laptopLayout))
    }

    @Test func connectedDisplaysUsesLaptopWhenLaptopOnly() {
        let library = LayoutLibrary(
            laptop: laptopLayout,
            multiDisplay: [docked.fingerprint: dockedLayout]
        )
        #expect(select(.connectedDisplays, library, laptopOnly) == .laptop(laptopLayout))
        #expect(select(.connectedDisplays, LayoutLibrary(), laptopOnly) == .noLaptopLayout)
    }

    @Test func shortcutTargetMapsToRestoreTarget() {
        #expect(RestoreTarget(.connectedDisplays) == .connectedDisplays)
        #expect(RestoreTarget(.laptop) == .laptop)
        #expect(RestoreTarget(.multiDisplay) == .multiDisplay)
    }

    // MARK: - Size warnings and report

    @Test func sizeWarningOncePerMismatchedResolvedDisplay() {
        var smallerDell = DisplaysTests.dell.info
        smallerDell.size = CGSize(width: 1680, height: 1050)
        let saved = [DisplaysTests.builtIn.info, DisplaysTests.portrait.info, smallerDell]
        let warnings = RestoreEngine.sizeWarnings(
            saved: saved,
            resolved: docked.resolveAll(saved)
        )
        #expect(warnings.count == 1)
    }

    @Test func noSizeWarningForUnresolvedDisplay() {
        let clamshell = DisplayConfiguration(displays: [DisplaysTests.portrait])
        let saved = [DisplaysTests.dell.info]
        #expect(RestoreEngine.sizeWarnings(saved: saved, resolved: clamshell.resolveAll(saved)).isEmpty)
    }

    @Test func summaryNamesTargetWhenSet() {
        var report = RestoreReport(restored: 5, skipped: 1, failed: 0)
        #expect(report.summary == "Restored 5, skipped 1, failed 0")
        report.target = "multi-display layout"
        #expect(report.summary == "Restored 5, skipped 1, failed 0 (multi-display layout)")
    }

    // MARK: - Helpers

    private func select(
        _ target: RestoreTarget,
        _ library: LayoutLibrary,
        _ configuration: DisplayConfiguration
    ) -> RestoreSelection {
        RestoreEngine.select(target: target, library: library, configuration: configuration)
    }

    private static func layout(_ displays: [DisplayInfo], savedAt: TimeInterval) -> Layout {
        Layout(savedAt: Date(timeIntervalSince1970: savedAt), displays: displays, windows: [])
    }
}
