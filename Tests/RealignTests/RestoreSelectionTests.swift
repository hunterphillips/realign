import CoreGraphics
import Foundation
import Testing
@testable import Realign

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

    // MARK: - Display change

    @Test func displayChangeUsesLaptopLayoutWhenLaptopOnly() {
        let library = LayoutLibrary(
            laptop: laptopLayout,
            multiDisplay: [docked.fingerprint: dockedLayout]
        )
        #expect(select(.displayChange, library, laptopOnly) == .laptop(laptopLayout))
    }

    @Test func displayChangeWithoutLaptopLayoutWhenLaptopOnly() {
        let library = LayoutLibrary(multiDisplay: [docked.fingerprint: dockedLayout])
        #expect(select(.displayChange, library, laptopOnly) == .noLaptopLayout)
    }

    @Test func displayChangeUsesMatchingMultiLayoutWhenDocked() {
        let library = LayoutLibrary(
            laptop: laptopLayout,
            multiDisplay: [docked.fingerprint: dockedLayout]
        )
        #expect(
            select(.displayChange, library, docked)
                == .multiDisplay(key: docked.fingerprint, layout: dockedLayout)
        )
    }

    @Test func displayChangeNeverFallsThroughToLaptopWhenDocked() {
        let library = LayoutLibrary(laptop: laptopLayout)
        #expect(select(.displayChange, library, docked) == .noMatchingLayout)
    }

    @Test func displayChangeUsesSignatureFallbackKeyWhenDocked() {
        var renamedDell = DisplaysTests.dell.info
        renamedDell.uuid = "11111111-1111-1111-1111-111111111111"
        let saved = Self.layout(
            [DisplaysTests.builtIn.info, DisplaysTests.portrait.info, renamedDell],
            savedAt: 5
        )
        let savedKey = DisplayConfiguration.fingerprint(of: saved.displays)
        #expect(savedKey != docked.fingerprint)
        let library = LayoutLibrary(laptop: laptopLayout, multiDisplay: [savedKey: saved])
        #expect(
            select(.displayChange, library, docked)
                == .multiDisplay(key: savedKey, layout: saved)
        )
    }

    @Test func hasLayoutForDisplayChange() {
        let full = LayoutLibrary(
            laptop: laptopLayout,
            multiDisplay: [docked.fingerprint: dockedLayout]
        )
        let laptopOnlyLibrary = LayoutLibrary(laptop: laptopLayout)
        let multiOnlyLibrary = LayoutLibrary(multiDisplay: [docked.fingerprint: dockedLayout])

        // Laptop only: needs a laptop layout.
        #expect(hasLayout(.displayChange, full, laptopOnly))
        #expect(!hasLayout(.displayChange, multiOnlyLibrary, laptopOnly))
        #expect(!hasLayout(.displayChange, LayoutLibrary(), laptopOnly))

        // Docked: needs a matching multi-display layout; laptop never counts.
        #expect(hasLayout(.displayChange, full, docked))
        #expect(hasLayout(.displayChange, multiOnlyLibrary, docked))
        #expect(!hasLayout(.displayChange, laptopOnlyLibrary, docked))
        #expect(!hasLayout(.displayChange, LayoutLibrary(), docked))
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
        #expect(!report.applied)
        report.target = .multiDisplay
        #expect(report.applied)
        #expect(report.summary == "Restored 5, skipped 1, failed 0 (multi-display layout)")
        report.target = .laptop
        #expect(report.summary == "Restored 5, skipped 1, failed 0 (laptop layout)")
    }

    @Test func builtInFallbackWarnsOncePerDisplay() {
        // Docked layout restored with only the built-in: the two externals
        // fall back to it (different kind), the built-in matches exactly.
        let saved = docked.displays.map(\.info)
        let warnings = RestoreEngine.sizeWarnings(
            saved: saved,
            resolved: laptopOnly.resolveAll(saved)
        )
        #expect(warnings.count == 2)
    }

    @Test func builtInFallbackWarnsEvenWhenSizesMatch() {
        var sameSizeExternal = DisplaysTests.dell.info
        sameSizeExternal.size = DisplaysTests.builtIn.info.size
        let saved = [sameSizeExternal]
        let warnings = RestoreEngine.sizeWarnings(
            saved: saved,
            resolved: laptopOnly.resolveAll(saved)
        )
        #expect(warnings.count == 1)
    }

    @Test func migratedBuiltInPlaceholderIsSameKindAsRealBuiltIn() {
        // The v1-migration placeholder (vendor 0, model 0, uuid "builtin")
        // restoring onto the real built-in should read as the same kind of
        // display, not a "not connected" fallback.
        let placeholder = DisplayInfo(
            uuid: "builtin",
            name: "Built-in Display",
            vendor: 0,
            model: 0,
            isBuiltIn: true,
            size: DisplaysTests.builtIn.info.size
        )
        let saved = [placeholder]
        let warnings = RestoreEngine.sizeWarnings(
            saved: saved,
            resolved: laptopOnly.resolveAll(saved)
        )
        #expect(warnings.isEmpty)
    }

    // MARK: - Save routing

    @Test func laptopOnlySaveRoutesToLaptop() {
        var library = LayoutLibrary(multiDisplay: [docked.fingerprint: dockedLayout])
        let slot = library.store(laptopLayout, for: laptopOnly)
        #expect(slot == .laptop)
        #expect(library.laptop == laptopLayout)
        #expect(library.multiDisplay == [docked.fingerprint: dockedLayout])
    }

    @Test func dockedSaveRoutesToFingerprint() {
        var library = LayoutLibrary(laptop: laptopLayout)
        let slot = library.store(dockedLayout, for: docked)
        #expect(slot == .multiDisplay(externalCount: 2))
        #expect(library.laptop == laptopLayout)
        #expect(library.multiDisplay == [docked.fingerprint: dockedLayout])
    }

    @Test func dockedSaveKeepsOtherKeysWithSameSignature() {
        // Two docks with the same monitor model (e.g. home and office) but
        // different UUIDs must keep separate layouts under their own keys.
        var renamedDell = DisplaysTests.dell.info
        renamedDell.uuid = "11111111-1111-1111-1111-111111111111"
        let stale = Self.layout(
            [DisplaysTests.builtIn.info, DisplaysTests.portrait.info, renamedDell],
            savedAt: 1
        )
        let staleKey = DisplayConfiguration.fingerprint(of: stale.displays)
        let other = Self.layout([DisplaysTests.builtIn.info, DisplaysTests.dell.info], savedAt: 1)
        let otherKey = DisplayConfiguration.fingerprint(of: other.displays)
        var library = LayoutLibrary(multiDisplay: [staleKey: stale, otherKey: other])

        _ = library.store(dockedLayout, for: docked)

        #expect(library.multiDisplay == [
            docked.fingerprint: dockedLayout,
            staleKey: stale,
            otherKey: other,
        ])
    }

    // MARK: - Migration

    @Test func migratedV1LayoutResolvesToBuiltInWhenDocked() {
        let legacy = LegacyLayoutV1(
            savedAt: Date(timeIntervalSince1970: 0),
            builtInSize: DisplaysTests.builtIn.info.size,
            windows: [
                .init(bundleID: "com.google.Chrome", appName: "Google Chrome",
                      title: "", indexInApp: 0,
                      frame: CGRect(x: 571, y: 33, width: 1157, height: 1041)),
                .init(bundleID: "com.mitchellh.ghostty", appName: "Ghostty",
                      title: "", indexInApp: 0,
                      frame: CGRect(x: 0, y: 34, width: 570, height: 1042)),
            ]
        )
        let migrated = Layout.migrated(fromV1: legacy, builtIn: DisplaysTests.builtIn.info)
        let library = LayoutLibrary(laptop: migrated)

        guard case .laptop(let selected) = select(.connectedDisplays, library, docked) else {
            Issue.record("expected the migrated laptop layout")
            return
        }
        let resolved = docked.resolveAll(selected.displays)
        #expect(!selected.windows.isEmpty)
        for record in selected.windows {
            #expect(resolved[record.displayUUID] == DisplaysTests.builtIn)
        }
    }

    // MARK: - Helpers

    private func select(
        _ target: RestoreTarget,
        _ library: LayoutLibrary,
        _ configuration: DisplayConfiguration
    ) -> RestoreSelection {
        RestoreEngine.select(target: target, library: library, configuration: configuration)
    }

    private func hasLayout(
        _ target: RestoreTarget,
        _ library: LayoutLibrary,
        _ configuration: DisplayConfiguration
    ) -> Bool {
        RestoreEngine.hasLayout(for: target, library: library, configuration: configuration)
    }

    private static func layout(_ displays: [DisplayInfo], savedAt: TimeInterval) -> Layout {
        Layout(savedAt: Date(timeIntervalSince1970: savedAt), displays: displays, windows: [])
    }
}
