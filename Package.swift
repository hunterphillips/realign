// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SplitScreen",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SplitScreen", targets: ["SplitScreen"]),
    ],
    targets: [
        .executableTarget(
            name: "SplitScreen",
            path: "Sources/SplitScreen",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "SplitScreenTests",
            dependencies: ["SplitScreen"],
            path: "Tests/SplitScreenTests"
        ),
    ]
)

