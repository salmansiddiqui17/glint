// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Glint",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Glint", targets: ["Glint"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0"),
    ],
    targets: [
        // Pure, AppKit-free logic: geometry, layout, naming, encoding. Fully unit-tested.
        .target(name: "GlintCore"),
        // AppKit/SwiftUI/ScreenCaptureKit: windows, menus, capture, export.
        .target(
            name: "GlintApp",
            dependencies: [
                "GlintCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
        ),
        // Tiny entry point that starts NSApplication.
        .executableTarget(name: "Glint", dependencies: ["GlintApp"]),
        .testTarget(name: "GlintCoreTests", dependencies: ["GlintCore"]),
    ]
)
