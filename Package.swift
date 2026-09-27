// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Realign",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Realign", targets: ["Realign"]),
    ],
    targets: [
        .executableTarget(
            name: "Realign",
            path: "Sources/Realign",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "RealignTests",
            dependencies: ["Realign"],
            path: "Tests/RealignTests"
        ),
    ]
)

