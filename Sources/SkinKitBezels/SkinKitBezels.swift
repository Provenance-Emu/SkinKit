// SkinKitBezels: the TV or monitor drawn around the game picture, shared by Provenance, iFly and iCube.
//
// What is here (no UIKit or SwiftUI, so it builds and is tested on the macOS host):
//   Rules        which TV shows for a game, whether the device may show one, the pause-menu switcher's model,
//                and the parameter values that place a tube inside the `bezel/uborder` slang presets
//   Catalog      the bundled TVs (format 2 skin documents), their artwork, built scenes and the scene cache,
//                the player's own image bezels, the room-light default and the GPU failure classifier
//   Import       reading an image bezel: its see-through screen, RetroArch overlay files, ROM name matching
//   BezelProject The Bezel Project's lists and downloads (nothing of theirs ships with the package)
//   Settings     where the player's choices are stored, behind a protocol
//
// The package draws nothing on the GPU. A built-in TV is described as a `TVBezelScene`: a preset path, its
// parameter values and the cabinet as a PNG. An app with a slang shader runtime feeds that to its own filter
// chain; an app without one shows the cabinet as a plain image with the picture in the tube (`TVBezelLayout`,
// `TVBezelPlainArtwork`, and `TVBezelArtworkView` in SkinKitBezelsUI).
//
// An app sets `BezelEnvironment.current` once at launch, before anything else here is used.

import Foundation

/// What the package needs from the app it runs in.
public struct BezelEnvironment: Sendable {

    /// A system as the pickers name it.
    public struct System: Equatable, Sendable, Identifiable {
        /// The identifier bezels and games are matched by (a `SystemIdentifier` raw value in the three apps).
        public let id: String
        public let name: String
        /// A shorter name for a title; the full one when the system has none.
        public let shortName: String

        public init(id: String, name: String, shortName: String? = nil) {
            self.id = id
            self.name = name
            self.shortName = shortName ?? name
        }
    }

    /// The player's bezels folder (`Bezels/` in the app's library).
    public var libraryRootURL: URL
    /// Where The Bezel Project's lists are kept between launches.
    public var cacheURL: URL
    /// Sent to GitHub with list requests. An app's name, never anything about the player.
    public var userAgent: String
    /// Where the player's choices are stored.
    public var settings: any BezelSettingsStore
    /// Every system a bezel can be said to belong to, for the pickers.
    public var systems: @Sendable () -> [System]
    /// Whether the app's shader library can run the preset with this id (`slang:<library path>`).
    /// An app with no slang runtime leaves the default, which offers no shader-only TVs.
    public var hasShaderPreset: @Sendable (String) -> Bool

    public init(libraryRootURL: URL = BezelEnvironment.defaultLibraryRootURL,
                cacheURL: URL = BezelEnvironment.defaultCacheURL,
                userAgent: String = "SkinKitBezels",
                settings: any BezelSettingsStore = UserDefaultsBezelSettings(),
                systems: @escaping @Sendable () -> [System] = { [] },
                hasShaderPreset: @escaping @Sendable (String) -> Bool = { _ in false }) {
        self.libraryRootURL = libraryRootURL
        self.cacheURL = cacheURL
        self.userAgent = userAgent
        self.settings = settings
        self.systems = systems
        self.hasShaderPreset = hasShaderPreset
    }

    /// `Bezels/` in the app's Documents folder.
    public static var defaultLibraryRootURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent(TVBezelLibrary.folderName, isDirectory: true)
    }

    /// `BezelProject/` in the app's Caches folder.
    public static var defaultCacheURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent(BezelProjectService.cacheFolder, isDirectory: true)
    }

    public func systemName(_ id: String) -> String? {
        systems().first { $0.id == id }?.name
    }

    public func shortSystemName(_ id: String) -> String? {
        systems().first { $0.id == id }?.shortName
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored = BezelEnvironment()

    /// The app's environment. Set it once at launch: `TVBezelLibrary.shared` and
    /// `BezelProjectService.shared` read their folders from it the first time they are used.
    public static var current: BezelEnvironment {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// The package's log. Silent until the app sets `handler`.
@frozen public enum BezelLog {

    @frozen public enum Level: Int, Sendable, Comparable {
        case info, warning, error

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored: (@Sendable (Level, String) -> Void)?

    /// Receives every message. May be called from any thread.
    public static var handler: (@Sendable (Level, String) -> Void)? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    static func info(_ message: @autoclosure () -> String) { send(.info, message) }
    static func warning(_ message: @autoclosure () -> String) { send(.warning, message) }
    static func error(_ message: @autoclosure () -> String) { send(.error, message) }

    private static func send(_ level: Level, _ message: () -> String) {
        guard let handler else { return }
        handler(level, message())
    }
}
