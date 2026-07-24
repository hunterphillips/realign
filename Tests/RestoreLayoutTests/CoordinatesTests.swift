import CoreGraphics
import Testing
@testable import RestoreLayout

@Suite("Coordinate conversion")
struct CoordinatesTests {
    @Test func singleDisplayOriginAndConversion() {
        let origin = Coordinates.axGlobalOrigin(
            appKitFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            primaryScreenHeight: 982
        )
        #expect(origin == .zero)

        let global = CGRect(x: 12, y: 34, width: 700, height: 800)
        #expect(
            Coordinates.builtInRelative(
                fromAXGlobal: global,
                builtInAXOrigin: origin
            ) == global
        )
    }

    @Test func externalAboveProducesNegativeRelativeY() {
        let externalOrigin = Coordinates.axGlobalOrigin(
            appKitFrame: CGRect(x: 0, y: 982, width: 1920, height: 900),
            primaryScreenHeight: 982
        )
        #expect(externalOrigin == CGPoint(x: 0, y: -900))

        let builtInOrigin = CGPoint(x: 0, y: 0)
        let externalWindow = CGRect(
            x: externalOrigin.x + 100,
            y: externalOrigin.y + 200,
            width: 900,
            height: 600
        )
        let relative = Coordinates.builtInRelative(
            fromAXGlobal: externalWindow,
            builtInAXOrigin: builtInOrigin
        )
        #expect(relative.origin.y == -700)
    }

    @Test func externalLeftProducesNegativeRelativeX() {
        let builtInOrigin = CGPoint(x: 1920, y: 98)
        let externalWindow = CGRect(x: 200, y: 150, width: 800, height: 700)
        let relative = Coordinates.builtInRelative(
            fromAXGlobal: externalWindow,
            builtInAXOrigin: builtInOrigin
        )
        #expect(relative.origin.x == -1720)
        #expect(relative.origin.y == 52)
    }

    @Test func builtInCanBeNonPrimary() {
        let origin = Coordinates.axGlobalOrigin(
            appKitFrame: CGRect(x: -1512, y: 0, width: 1512, height: 982),
            primaryScreenHeight: 1080
        )
        #expect(origin == CGPoint(x: -1512, y: 98))
    }

    @Test func roundTripAcrossRepresentativeOrigins() {
        let frames = [
            CGRect(x: -500, y: -300, width: 400, height: 250),
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: 2050, y: 200, width: 1000, height: 700),
        ]
        let origins = [
            CGPoint.zero,
            CGPoint(x: -1512, y: 98),
            CGPoint(x: 1920, y: -900),
        ]

        for frame in frames {
            for origin in origins {
                let relative = Coordinates.builtInRelative(
                    fromAXGlobal: frame,
                    builtInAXOrigin: origin
                )
                let roundTrip = Coordinates.axGlobal(
                    fromBuiltInRelative: relative,
                    builtInAXOrigin: origin
                )
                #expect(roundTrip == frame)
            }
        }
    }
}
