// swift-tools-version: 6.0
//
// SkinKit: controller-skin code shared by Provenance, iFly and iCube.
//
// Modules, in dependency order:
//   SkinKitCore     info.json model, decoding, layout/trait resolution (no UI)
//   SkinCatalogKit  catalog models, catalog service, store sections/policy (no UI)
//   SkinKitManager  import, install, storage, per-game/per-system selection (no UI)
//   SkinKitUI       SwiftUI skin rendering and store/picker views (iOS/tvOS)
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
        .target(name: "SkinCatalogKit"),
        .target(name: "SkinKitManager", dependencies: ["SkinKitCore", "SkinCatalogKit"]),
        .target(name: "SkinKitUI", dependencies: ["SkinKitCore", "SkinKitManager"]),

        .testTarget(
            name: "SkinKitCoreTests",
            dependencies: ["SkinKitCore", .product(name: "ZIPFoundation", package: "ZIPFoundation")],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "SkinCatalogKitTests", dependencies: ["SkinCatalogKit"]),
        .testTarget(name: "SkinKitManagerTests", dependencies: ["SkinKitManager"]),
        .testTarget(name: "SkinKitUITests", dependencies: ["SkinKitUI"]),
    ],
    swiftLanguageModes: [.v5]
)
