// swift-tools-version: 6.0
//
// SkinKit: controller-skin code shared by Provenance, iFly and iCube.
//
// Modules, in dependency order:
//   SkinKitCore     info.json model, decoding, layout/trait resolution (no UI)
//   SkinCatalogKit  catalog models, catalog service, store sections/policy (no UI)
//   SkinKitManager  import, install, storage, per-game/per-system selection (no UI)
//   SkinKitRetroArch  Delta skin to RetroArch overlay preset (.cfg) conversion, and the logic behind "Send to RetroArch"; depends on SkinKitCore only (no UI)
//   SkinKitUI       SwiftUI skin rendering and store/picker views (iOS/tvOS); uses SkinKitRetroArch for Send to RetroArch (iOS only)
//   SkinKit2Core    skin format 2.0: model, preprocessor, validator, layout resolver, JSON Schema (no UI, no deps)
//   SkinKit2Render  skin format 2.0: Core Graphics drawer and hit testing for resolved layouts (no UIKit/SwiftUI)
//   SkinKitBezels   the TV drawn around the game picture: selection rules, bundled TVs (format 2 documents),
//                   image bezels, The Bezel Project, settings behind a protocol (no UI, runs no shader)
//   SkinKitBezelsUI the pause-menu TV switcher, the TV picker and the plain (shader-free) TV view (iOS/tvOS)
//
// macOS is listed only so the non-UI modules can run `swift test` on the host
// without a simulator. The apps ship on iOS and tvOS.

import PackageDescription

let package = Package(
    name: "SkinKit",
    platforms: [
        .iOS(.v17),
        .tvOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "SkinKitCore", targets: ["SkinKitCore"]),
        .library(name: "SkinCatalogKit", targets: ["SkinCatalogKit"]),
        .library(name: "SkinKitManager", targets: ["SkinKitManager"]),
        .library(name: "SkinKitUI", targets: ["SkinKitUI"]),
        .library(name: "SkinKitRetroArch", targets: ["SkinKitRetroArch"]),
        .library(name: "SkinKit2Core", targets: ["SkinKit2Core"]),
        .library(name: "SkinKit2Render", targets: ["SkinKit2Render"]),
        .library(name: "SkinKit2Bake", targets: ["SkinKit2Bake"]),
        .library(name: "SkinKitBezels", targets: ["SkinKitBezels"]),
        .library(name: "SkinKitBezelsUI", targets: ["SkinKitBezelsUI"]),
        .executable(name: "skinkit-bake", targets: ["skinkit-bake"]),
    ],
    dependencies: [
        // Same range Provenance resolves (via PVLookup).
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMajor(from: "0.9.18")),
    ],
    targets: [
        .target(
            name: "SkinKitCore",
            dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")],
            resources: [.copy("Resources/system-native-resolutions.json")]
        ),
        .target(name: "SkinCatalogKit", resources: [.copy("Resources/badges.json")]),
        .target(
            name: "SkinKitManager",
            dependencies: ["SkinKitCore", "SkinCatalogKit", .product(name: "ZIPFoundation", package: "ZIPFoundation")]
        ),
        .target(name: "SkinKitUI", dependencies: ["SkinKitCore", "SkinCatalogKit", "SkinKitManager", "SkinKitRetroArch", "SkinKit2Core", "SkinKit2Render", "SkinKit2Bake"]),
        .target(
            name: "SkinKitRetroArch",
            dependencies: ["SkinKitCore", .product(name: "ZIPFoundation", package: "ZIPFoundation")],
            resources: [.copy("Resources/retroarch-input-map.json")]
        ),
        // The standard parts library (parts.std@2.0) is JSON; the TypeScript port vendors the same files.
        .target(name: "SkinKit2Core", resources: [.copy("Resources/parts")]),
        // The bundled default font (Outfit, OFL) is a resource; the TypeScript renderer ships the same files.
        .target(name: "SkinKit2Render", dependencies: ["SkinKit2Core"], resources: [.copy("Resources/Fonts")]),

        .testTarget(
            name: "SkinKitCoreTests",
            dependencies: ["SkinKitCore", .product(name: "ZIPFoundation", package: "ZIPFoundation")],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "SkinCatalogKitTests", dependencies: ["SkinCatalogKit"], resources: [.copy("Fixtures")]),
        .testTarget(
            name: "SkinKitManagerTests",
            dependencies: [
                "SkinKitManager", "SkinKitCore", "SkinCatalogKit",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SkinKitRetroArchTests",
            dependencies: ["SkinKitRetroArch", "SkinKitCore", .product(name: "ZIPFoundation", package: "ZIPFoundation")],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SkinKitUITests",
            dependencies: [
                "SkinKitUI", "SkinKitCore", "SkinKitManager", "SkinCatalogKit",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            resources: [.copy("Fixtures")]
        ),
        // Reads Tests/Format2Fixtures and docs/schema through #filePath (shared with the TypeScript port).
        .testTarget(name: "SkinKit2CoreTests", dependencies: ["SkinKit2Core"]),
        // Renders Tests/Format2Fixtures and compares with the committed expected/*@2x.png references.
        .testTarget(name: "SkinKit2RenderTests", dependencies: ["SkinKit2Render", "SkinKit2Core"]),
        .target(name: "SkinKit2Bake", dependencies: ["SkinKit2Core", "SkinKitCore", "SkinKit2Render", .product(name: "ZIPFoundation", package: "ZIPFoundation")]),
        .executableTarget(name: "skinkit-bake", dependencies: ["SkinKit2Bake", "SkinKit2Core"]),
        .testTarget(name: "SkinKit2BakeTests", dependencies: ["SkinKit2Bake", "SkinKit2Core", "SkinKitCore"]),

        // The bundled TVs are format 2 skin documents drawn by SkinKit2Render. Nothing from The Bezel Project
        // is bundled or used as a fixture.
        .target(
            name: "SkinKitBezels",
            dependencies: ["SkinKit2Core", "SkinKit2Render"],
            resources: [.copy("Resources/TVBezels")]
        ),
        .target(name: "SkinKitBezelsUI", dependencies: ["SkinKitBezels"]),
        .testTarget(name: "SkinKitBezelsTests", dependencies: ["SkinKitBezels"]),
        .testTarget(name: "SkinKitBezelsUITests", dependencies: ["SkinKitBezelsUI", "SkinKitBezels"]),
    ],
    swiftLanguageModes: [.v5]
)
