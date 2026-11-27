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

import Foundation
import PackageDescription

// A version tag resolves to the prebuilt XCFrameworks from that tag's GitHub release;
// `main` always builds from source. The release workflow fills this in on the tagged
// commit only, so it stays `nil` on every branch.
// Set PV_BUILD_FROM_SOURCE=1 to build a tagged version from source instead.
let binaryRelease: (version: String, checksums: [String: String])? = ("0.10.0", ["SkinCatalogKit": "f87cb8999c006f89e8814352454281a05f6294098a081f7e830f5e112fb3bc85", "SkinKit2Bake": "e0da817586850442e3f4df4e48366a402fb7e362186fdadd03802f39b1dae5e9", "SkinKit2Core": "b0d8579fc027ac39e0773c2a62f0a5587b9f2321ca92d7f71a06920834bab208", "SkinKit2Render": "58db9564e3af1baa4624e4eb5c8be523b484b7aea433abbba35fcc4df21779a6", "SkinKitBezels": "a0cb4cf84f0e743d66e540f07ef69a98e73d58024103838bbeff6785eb21240a", "SkinKitBezelsUI": "c711c3cea562437f8bcf887e18fe5a32a6f577a03609b3d61a6a2fec8df7979f", "SkinKitCore": "8bba4833490c2e8b3933e385a97a103edea652b64a0fadbdbae550c924e8a0c4", "SkinKitManager": "e912d0fbe9cc22c3b018d1f762efdb1392e17e236868ea06441c46859c95a86c", "SkinKitRetroArch": "fd70cc4f9e5aeb1be8c80f11fa94d870e97a856ea9a472e6a999b2ec15d910bd", "SkinKitUI": "5d42fe1da853b44ba7f9a6982aa7532e314cc7c65932a561d1926dc439dfbc39"])

let environment = ProcessInfo.processInfo.environment
let buildFromSource = binaryRelease == nil || environment["PV_BUILD_FROM_SOURCE"] != nil
// The release workflow builds the frameworks it publishes from dynamic products, one
// module at a time, and names the ones already built so later modules link them
// instead of compiling them in again.
let buildingRelease = environment["PV_XCFRAMEWORK_BUILD"] != nil
let libraryType: Product.Library.LibraryType? = buildingRelease ? .dynamic : nil
let prebuilt = Set((environment["PV_XCFRAMEWORK_PREBUILT"] ?? "").split(separator: " ").map(String.init))

let module: (Target) -> Target = { source in
    prebuilt.contains(source.name)
        ? .binaryTarget(name: source.name, path: ".xcframework-build/\(source.name).xcframework")
        : source
}
// A product made only of a prebuilt framework cannot ask for a linkage type.
let libraryTypeFor: (String) -> Product.Library.LibraryType? = { module in
    prebuilt.contains(module) ? nil : libraryType
}

// The released modules, in the order the release workflow builds them: each after the
// modules it imports.
let releasedModules = [
    "SkinKitCore", "SkinCatalogKit", "SkinKit2Core", "SkinKitRetroArch", "SkinKitManager", "SkinKit2Render",
    "SkinKit2Bake", "SkinKitBezels", "SkinKitBezelsUI", "SkinKitUI",
]

let zip: Target.Dependency = .product(name: "ZIPFoundation", package: "PVDependencies")

let sourceProducts: [Product] = [
    .library(name: "SkinKitCore", type: libraryTypeFor("SkinKitCore"), targets: ["SkinKitCore"]),
    .library(name: "SkinCatalogKit", type: libraryTypeFor("SkinCatalogKit"), targets: ["SkinCatalogKit"]),
    .library(name: "SkinKitManager", type: libraryTypeFor("SkinKitManager"), targets: ["SkinKitManager"]),
    .library(name: "SkinKitUI", type: libraryTypeFor("SkinKitUI"), targets: ["SkinKitUI"]),
    .library(name: "SkinKitRetroArch", type: libraryTypeFor("SkinKitRetroArch"), targets: ["SkinKitRetroArch"]),
    .library(name: "SkinKit2Core", type: libraryTypeFor("SkinKit2Core"), targets: ["SkinKit2Core"]),
    .library(name: "SkinKit2Render", type: libraryTypeFor("SkinKit2Render"), targets: ["SkinKit2Render"]),
    .library(name: "SkinKit2Bake", type: libraryTypeFor("SkinKit2Bake"), targets: ["SkinKit2Bake"]),
    .library(name: "SkinKitBezels", type: libraryTypeFor("SkinKitBezels"), targets: ["SkinKitBezels"]),
    .library(name: "SkinKitBezelsUI", type: libraryTypeFor("SkinKitBezelsUI"), targets: ["SkinKitBezelsUI"]),
    .executable(name: "skinkit-bake", targets: ["skinkit-bake"]),
]

let sourceTargets: [Target] = [
    module(.target(
        name: "SkinKitCore",
        dependencies: [zip],
        resources: [.copy("Resources/system-native-resolutions.json")]
    )),
    module(.target(name: "SkinCatalogKit", resources: [.copy("Resources/badges.json")])),
    module(.target(
        name: "SkinKitManager",
        dependencies: ["SkinKitCore", "SkinCatalogKit", zip]
    )),
    // ZIPFoundation is named here too: SkinKitCore's interface imports it, and a prebuilt
    // framework does not pass its own dependencies on.
    module(.target(name: "SkinKitUI", dependencies: ["SkinKitCore", "SkinCatalogKit", "SkinKitManager", "SkinKitRetroArch", "SkinKit2Core", "SkinKit2Render", "SkinKit2Bake", zip])),
    module(.target(
        name: "SkinKitRetroArch",
        dependencies: ["SkinKitCore", zip],
        resources: [.copy("Resources/retroarch-input-map.json")]
    )),
    // The standard parts library (parts.std@2.0) is JSON; the TypeScript port vendors the same files.
    module(.target(name: "SkinKit2Core", resources: [.copy("Resources/parts")])),
    // The bundled default font (Outfit, OFL) is a resource; the TypeScript renderer ships the same files.
    module(.target(name: "SkinKit2Render", dependencies: ["SkinKit2Core"], resources: [.copy("Resources/Fonts")])),

    .testTarget(
        name: "SkinKitCoreTests",
        dependencies: ["SkinKitCore", zip],
        resources: [.copy("Fixtures")]
    ),
    .testTarget(name: "SkinCatalogKitTests", dependencies: ["SkinCatalogKit"], resources: [.copy("Fixtures")]),
    .testTarget(
        name: "SkinKitManagerTests",
        dependencies: [
            "SkinKitManager", "SkinKitCore", "SkinCatalogKit",
            zip,
        ],
        resources: [.copy("Fixtures")]
    ),
    .testTarget(
        name: "SkinKitRetroArchTests",
        dependencies: ["SkinKitRetroArch", "SkinKitCore", zip],
        resources: [.copy("Fixtures")]
    ),
    .testTarget(
        name: "SkinKitUITests",
        dependencies: [
            "SkinKitUI", "SkinKitCore", "SkinKitManager", "SkinCatalogKit",
            zip,
        ],
        resources: [.copy("Fixtures")]
    ),
    // Reads Tests/Format2Fixtures and docs/schema through #filePath (shared with the TypeScript port).
    .testTarget(name: "SkinKit2CoreTests", dependencies: ["SkinKit2Core"]),
    // Renders Tests/Format2Fixtures and compares with the committed expected/*@2x.png references.
    .testTarget(name: "SkinKit2RenderTests", dependencies: ["SkinKit2Render", "SkinKit2Core"]),
    module(.target(name: "SkinKit2Bake", dependencies: ["SkinKit2Core", "SkinKitCore", "SkinKit2Render", zip])),
    .executableTarget(name: "skinkit-bake", dependencies: ["SkinKit2Bake", "SkinKit2Core"]),
    .testTarget(name: "SkinKit2BakeTests", dependencies: ["SkinKit2Bake", "SkinKit2Core", "SkinKitCore"]),

    // The bundled TVs are format 2 skin documents drawn by SkinKit2Render. Nothing from The Bezel Project
    // is bundled or used as a fixture.
    module(.target(
        name: "SkinKitBezels",
        dependencies: ["SkinKit2Core", "SkinKit2Render"],
        resources: [.copy("Resources/TVBezels")]
    )),
    module(.target(name: "SkinKitBezelsUI", dependencies: ["SkinKitBezels", "SkinKit2Core", "SkinKit2Render"])),
    .testTarget(name: "SkinKitBezelsTests", dependencies: ["SkinKitBezels"]),
    .testTarget(name: "SkinKitBezelsUITests", dependencies: ["SkinKitBezelsUI", "SkinKitBezels"]),
]

let binaryTargets: [Target] = binaryRelease.map { release in
    release.checksums.sorted { $0.key < $1.key }.map { module, checksum in
        .binaryTarget(
            name: module,
            url: "https://github.com/Provenance-Emu/SkinKit/releases/download/\(release.version)/\(module).xcframework.zip",
            checksum: checksum
        )
    } + [
        // What the prebuilt frameworks link against.
        .target(name: "SkinKitDependencies", dependencies: [zip], path: "Sources/BinaryDependencies"),
    ]
} ?? []

// Every product carries all ten frameworks: they link each other. The `skinkit-bake`
// tool is built from source only.
let binaryProducts: [Product] = releasedModules.map {
    .library(name: $0, targets: releasedModules + ["SkinKitDependencies"])
}

let package = Package(
    name: "SkinKit",
    platforms: [
        .iOS(.v17),
        .tvOS(.v17),
        .macOS(.v14),
        // Its own slice in the released XCFrameworks: a Catalyst app cannot link the macOS one.
        .macCatalyst(.v17),
    ],
    products: buildFromSource ? sourceProducts : binaryProducts,
    dependencies: [
        // Prebuilt ZIPFoundation, shared with the apps and the other shared packages. A graph
        // cannot hold this and the upstream ZIPFoundation package at once.
        .package(url: "https://github.com/Provenance-Emu/PVDependencies.git", .upToNextMajor(from: "1.0.0")),
    ],
    targets: buildFromSource ? sourceTargets : binaryTargets,
    swiftLanguageModes: [.v5]
)
