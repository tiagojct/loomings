// swift-tools-version: 6.0
// Native macOS app. The web app stays untouched.

import PackageDescription

let package = Package(
    name: "LoomingsMac",
    platforms: [
        .macOS("15.0"),
    ],
    products: [
        .executable(name: "LoomingsApp", targets: ["LoomingsApp"]),
        .executable(name: "LoomingsBench", targets: ["LoomingsBench"]),
        .library(name: "LoomingsEditor", targets: ["LoomingsEditor"]),
        .library(name: "LoomingsMarkdown", targets: ["LoomingsMarkdown"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-cmark.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "LoomingsMarkdown",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ]
        ),
        .target(
            name: "LoomingsDocuments",
            dependencies: []
        ),
        .target(
            name: "CZlib",
            linkerSettings: [.linkedLibrary("z")]
        ),
        .target(
            name: "LoomingsTheme",
            dependencies: []
        ),
        .target(
            name: "LoomingsShare",
            dependencies: ["CZlib"]
        ),
        .target(
            name: "LoomingsEditor",
            dependencies: ["LoomingsMarkdown", "LoomingsTheme"]
        ),
        .target(
            name: "LoomingsPreview",
            dependencies: ["LoomingsMarkdown", "LoomingsTheme"]
        ),
        .executableTarget(
            name: "LoomingsApp",
            dependencies: ["LoomingsDocuments", "LoomingsEditor", "LoomingsMarkdown", "LoomingsPreview", "LoomingsTheme", "LoomingsShare"]
        ),
        .executableTarget(
            name: "LoomingsBench",
            dependencies: ["LoomingsEditor", "LoomingsMarkdown", "LoomingsPreview"]
        ),
        .testTarget(
            name: "LoomingsMarkdownTests",
            dependencies: ["LoomingsMarkdown"]
        ),
        .testTarget(
            name: "LoomingsEditorTests",
            dependencies: ["LoomingsEditor"]
        ),
        .testTarget(
            name: "LoomingsDocumentsTests",
            dependencies: ["LoomingsDocuments"]
        ),
        .testTarget(
            name: "LoomingsShareTests",
            dependencies: ["LoomingsShare"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "LoomingsThemeTests",
            dependencies: ["LoomingsTheme"]
        ),
        .testTarget(
            name: "LoomingsPreviewTests",
            dependencies: ["LoomingsPreview"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
