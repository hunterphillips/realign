import CoreGraphics
import Foundation
import Testing
@testable import RestoreLayout

/// Fixtures are the three displays probed on the development machine.
@Suite("Display configuration")
struct DisplaysTests {
    static let builtIn = DisplayGeometry(
        info: DisplayInfo(
            uuid: "37D8832A-2D66-02CA-B9F7-8F30A301B230",
            name: "Built-in Retina Display",
            vendor: 1552,
            model: 41053,
            isBuiltIn: true,
            size: CGSize(width: 1728, height: 1117)
        ),
        axFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117)
    )
    static let portrait = DisplayGeometry(
        info: DisplayInfo(
            uuid: "EA6B215A-88A6-44D9-964D-8AA3FA4F5E45",
            name: "USB C2",
            vendor: 19083,
            model: 53653,
            isBuiltIn: false,
            size: CGSize(width: 1050, height: 1680)
        ),
        axFrame: CGRect(x: -1050, y: 0, width: 1050, height: 1680)
    )
    static let dell = DisplayGeometry(
        info: DisplayInfo(
            uuid: "DA3DD560-1F03-4878-B206-5C6BBC3BEF60",
            name: "DELL U2415",
            vendor: 4268,
            model: 41146,
            isBuiltIn: false,
            size: CGSize(width: 1920, height: 1200)
        ),
        axFrame: CGRect(x: 1728, y: 0, width: 1920, height: 1200)
    )

    let docked = DisplayConfiguration(displays: [builtIn, portrait, dell])

    // MARK: - Fingerprint

    @Test func fingerprintIsOrderIndependent() {
        let reordered = DisplayConfiguration(
            displays: [Self.dell, Self.builtIn, Self.portrait]
        )
        #expect(reordered.fingerprint == docked.fingerprint)
        #expect(
            DisplayConfiguration.fingerprint(of: [Self.dell.info, Self.builtIn.info])
                == DisplayConfiguration.fingerprint(of: [Self.builtIn.info, Self.dell.info])
        )
    }

    @Test func laptopOnlyDockedAndClamshellDiffer() {
        let laptop = DisplayConfiguration(displays: [Self.builtIn])
        let clamshell = DisplayConfiguration(displays: [Self.portrait, Self.dell])

        #expect(Set([laptop.fingerprint, docked.fingerprint, clamshell.fingerprint]).count == 3)
        #expect(laptop.isLaptopOnly)
        #expect(!docked.isLaptopOnly)
        #expect(!clamshell.isLaptopOnly)
        #expect(docked.externalCount == 2)
        #expect(clamshell.builtIn == nil)
    }

    // MARK: - Anchor

    @Test func windowFullyOnDellAnchorsToDell() {
        let window = CGRect(x: 1828, y: 50, width: 900, height: 700)
        #expect(docked.anchor(for: window) == Self.dell)
    }

    @Test func straddlingWindowAnchorsToLargerOverlap() {
        // 200pt wide on the built-in, 600pt wide on the DELL.
        let window = CGRect(x: 1528, y: 100, width: 800, height: 500)
        #expect(docked.anchor(for: window) == Self.dell)
    }

    @Test func windowOffEveryDisplayAnchorsToBuiltIn() {
        let window = CGRect(x: 10_000, y: 10_000, width: 400, height: 300)
        #expect(docked.anchor(for: window) == Self.builtIn)
    }

    // MARK: - Resolve

    @Test func resolvesExactUUID() {
        #expect(docked.resolve(Self.portrait.info) == Self.portrait)
    }

    @Test func resolvesChangedUUIDBySameVendorModelAndSize() {
        var saved = Self.dell.info
        saved.uuid = "00000000-0000-0000-0000-000000000000"
        #expect(docked.resolve(saved) == Self.dell)
    }

    @Test func absentDisplayFallsBackToBuiltIn() {
        let laptop = DisplayConfiguration(displays: [Self.builtIn])
        #expect(laptop.resolve(Self.dell.info) == Self.builtIn)
    }

    @Test func absentDisplayWithoutBuiltInResolvesToNil() {
        let clamshell = DisplayConfiguration(displays: [Self.portrait])
        #expect(clamshell.resolve(Self.dell.info) == nil)
    }

    // MARK: - Library matching

    @Test func matchingKeyPrefersExactFingerprint() {
        let library = [
            docked.fingerprint: layout(displays: docked.displays.map(\.info)),
            "other": layout(displays: docked.displays.map(\.info)),
        ]
        #expect(
            DisplayConfiguration.matchingKey(for: docked, in: library)
                == docked.fingerprint
        )
    }

    @Test func matchingKeyFallsBackToVendorModelSizeMultiset() {
        var renamedDell = Self.dell.info
        renamedDell.uuid = "11111111-1111-1111-1111-111111111111"
        let savedInfos = [Self.builtIn.info, Self.portrait.info, renamedDell]
        let savedKey = DisplayConfiguration.fingerprint(of: savedInfos)
        let library = [
            "unrelated": layout(displays: [Self.builtIn.info]),
            savedKey: layout(displays: savedInfos),
        ]
        #expect(DisplayConfiguration.matchingKey(for: docked, in: library) == savedKey)
    }

    @Test func matchingKeyReturnsNilWhenNothingMatches() {
        let library = [
            "laptop+dell": layout(displays: [Self.builtIn.info, Self.dell.info]),
        ]
        #expect(DisplayConfiguration.matchingKey(for: docked, in: library) == nil)
    }

    private func layout(displays: [DisplayInfo]) -> Layout {
        Layout(savedAt: Date(timeIntervalSince1970: 0), displays: displays, windows: [])
    }
}
