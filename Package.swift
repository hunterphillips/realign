// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RestoreLayout",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RestoreLayout", targets: ["RestoreLayout"]),
    ],
    targets: [
        .executableTarget(
            name: "RestoreLayout",
            path: "Sources/RestoreLayout",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "RestoreLayoutTests",
            dependencies: ["RestoreLayout"],
            path: "Tests/RestoreLayoutTests"
        ),
    ]
)

