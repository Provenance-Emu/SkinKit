import Combine
import Foundation
import SkinKitCore
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// Manages loading and caching of DeltaSkins
///
/// Moved from Provenance's `DeltaSkinManager` (import, scan, delete, the persisted path index and the
/// session/effective selection pass-throughs). Where skins live is `Configuration`; everything else is
/// unchanged. Preview-image caching (`previewImage(for:)` and friends) needs `UIImage` and stays for
/// SkinKitUI.
public final class DeltaSkinManager: ObservableObject, DeltaSkinManagerProtocol {

    // MARK: - Configuration

    /// What differs between apps: where skins live and what counts as a skin file.
    public struct Configuration: Sendable {
        /// Where imported skins are copied. Also scanned, and holds the path index.
        /// Created on first use.
        public var skinsDirectory: URL

        /// Skin packages that ship inside the app, scanned before `skinsDirectory`.
        /// Provenance adds its `DefaultSkins` here; the default is the main bundle's top-level
        /// `.deltaskin` / `.manicskin` files.
        public var bundledSkinLocations: @Sendable () -> [URL]

        /// Lowercased extensions a scan treats as a skin: a `.deltaskin` directory or file at a
        /// scan location, and the files inside `skinsDirectory`.
        public var skinExtensions: Set<String>

        /// Extensions picked up inside a scanned directory. Provenance also reads `.zip` there,
        /// since people rename skin archives.
        public var directoryScanExtensions: Set<String>

        /// Name of the identifier → path JSON, inside `skinsDirectory`.
        public var pathIndexFileName: String

        /// Whether a skin identifier may be chosen automatically (default skin, restored
        /// selection). Provenance returns `CaseControllerDetector.isAllowedInAutomaticSkinSelection`
        /// here so a case-companion skin is only auto-loaded while its case is connected. The default
        /// allows everything.
        public var isAllowedInAutomaticSelection: @Sendable (_ skinIdentifier: String) -> Bool

        /// Whether `availableSkins()` reads the skin folders again on every call instead of scanning
        /// once and serving the cached list. Default `false` (Provenance's behavior: one scan, then
        /// `reloadSkins()` or `forceRescan` when something changed). iFly's manager rescanned on every
        /// call, so a file dropped into the folder was always seen by the next read; `.iFly()` sets this.
        /// Costs a directory listing and an `info.json` read per skin per call.
        public var rescansOnEveryRead: Bool

        public init(
            skinsDirectory: URL,
            bundledSkinLocations: @escaping @Sendable () -> [URL] = Configuration.mainBundleSkins,
            skinExtensions: Set<String> = Configuration.defaultSkinExtensions,
            directoryScanExtensions: Set<String> = Configuration.defaultSkinExtensions.union(["zip"]),
            pathIndexFileName: String = "skin_path_index.json",
            isAllowedInAutomaticSelection: @escaping @Sendable (String) -> Bool = { _ in true },
            rescansOnEveryRead: Bool = false
        ) {
            self.skinsDirectory = skinsDirectory
            self.bundledSkinLocations = bundledSkinLocations
            self.skinExtensions = Set(skinExtensions.map { $0.lowercased() })
            self.directoryScanExtensions = Set(directoryScanExtensions.map { $0.lowercased() })
            self.pathIndexFileName = pathIndexFileName
            self.isAllowedInAutomaticSelection = isAllowedInAutomaticSelection
            self.rescansOnEveryRead = rescansOnEveryRead
        }

        public static let defaultSkinExtensions: Set<String> = ["deltaskin", "manicskin"]

        /// The app's Documents directory, or Caches on tvOS (tvOS apps can't write to Documents).
        /// The same mapping as Provenance's `URL.documentsPath`.
        public static var defaultDocumentsURL: URL {
            #if os(tvOS)
            return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            #else
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            #endif
        }

        /// The main bundle's top-level `.deltaskin` and `.manicskin` files.
        public static let mainBundleSkins: @Sendable () -> [URL] = {
            let deltaSkins = Bundle.main.urls(forResourcesWithExtension: "deltaskin", subdirectory: nil) ?? []
            let manicSkins = Bundle.main.urls(forResourcesWithExtension: "manicskin", subdirectory: nil) ?? []
            return deltaSkins + manicSkins
        }

        /// Provenance: `<documents>/DeltaSkins`, plus whatever bundled skins the app lists.
        ///
        /// - Parameter documents: the base directory. Pass Provenance's `URL.documentsPath` so tvOS
        ///   keeps using its Caches mapping.
        public static func provenance(
            documents: URL = Configuration.defaultDocumentsURL,
            bundledSkinLocations: @escaping @Sendable () -> [URL] = Configuration.mainBundleSkins
        ) -> Configuration {
            Configuration(
                skinsDirectory: documents.appendingPathComponent("DeltaSkins", isDirectory: true),
                bundledSkinLocations: bundledSkinLocations
            )
        }

        /// iFly: `<documents>/Skins`, and the bundle's `Skins/` folder. Its scan reads
        /// `.deltaskin` and `.manicskin` only, not `.zip`, and every `availableSkins()` rescans
        /// (`rescansOnEveryRead`).
        public static func iFly(
            documents: URL = Configuration.defaultDocumentsURL,
            bundle: Bundle = .main
        ) -> Configuration {
            Configuration(
                skinsDirectory: documents.appendingPathComponent("Skins", isDirectory: true),
                bundledSkinLocations: { [bundle] in
                    let deltaSkins = bundle.urls(forResourcesWithExtension: "deltaskin", subdirectory: "Skins") ?? []
                    let manicSkins = bundle.urls(forResourcesWithExtension: "manicskin", subdirectory: "Skins") ?? []
                    return deltaSkins + manicSkins
                },
                directoryScanExtensions: defaultSkinExtensions,
                rescansOnEveryRead: true
            )
        }
    }

    /// Singleton instance. Assign a configured manager before first use to change where skins live;
    /// the default is Provenance's layout.
    public static var shared = DeltaSkinManager()

    public let configuration: Configuration

    /// Where picks are stored and read back for the `sessionSkinIdentifier`/`effectiveSkinIdentifier` pass-throughs.
    public let selectionManager: DeltaSkinSelectionManager

    /// Currently loaded skins — `@Published` so SwiftUI observes changes.
    /// Intended for UI/MainActor reads; background callers should prefer
    /// `availableSkins(forceRescan:)` / `skin(withIdentifier:)` which are
    /// safe to use off the MainActor.
    @Published public private(set) var loadedSkins: [any DeltaSkinProtocol] = []

    /// Set to true on MainActor *after* loadedSkins is populated for the first time.
    /// Callers that read `loadedSkins` directly should gate on this property rather
    /// than `hasScanned`, which is queue-confined and becomes true before the
    /// MainActor update of `loadedSkins` has executed.
    @Published public private(set) var skinsAreLoaded: Bool = false

    /// Flag to track if skins have been scanned at least once (queue-confined).
    /// Controls the caching fast-path in `availableSkins(forceRescan:)`.
    private var hasScanned: Bool = false

    /// The most recent scan results, accessible from the background queue
    /// without waiting for MainActor.  `loadedSkins` is @Published and can
    /// only be safely written on MainActor, but callers on the background
    /// queue need immediate access to the scan results.
    private var lastScannedSkins: [any DeltaSkinProtocol] = []

    /// Monotonically increasing counter incremented after each scan completes.
    /// The captured generation value is passed into the MainActor update task so
    /// it can be compared against `lastAppliedGeneration` (MainActor-confined) to
    /// skip stale updates when scans are triggered in quick succession.
    private var scanGeneration: Int = 0

    /// Tracks the generation of the last scan result applied to `loadedSkins`.
    /// MainActor-confined to avoid cross-thread reads of the queue-confined `scanGeneration`.
    /// A MainActor task only applies its results when `generation > lastAppliedGeneration`.
    @MainActor private var lastAppliedGeneration: Int = 0

    /// Flag to track if scan is currently in progress (prevents concurrent scans)
    private var isScanning: Bool = false

    /// Queue for synchronizing skin operations
    private let queue = DispatchQueue(label: "com.provenance.deltaskin-manager")

    /// Persisted map of skin identifier → package path for fast ``skin(withIdentifier:)`` without scanning every bundle first.
    private var pathIndexByIdentifier: [String: String] = [:]
    private var pathIndexLoadedFromDisk = false

    /// - Parameters:
    ///   - configuration: where skins live. Defaults to Provenance's layout.
    ///   - selectionManager: the selection state the pass-throughs read. Defaults to `.shared`.
    public init(
        configuration: Configuration = .provenance(),
        selectionManager: DeltaSkinSelectionManager = .shared
    ) {
        self.configuration = configuration
        self.selectionManager = selectionManager
        // Scan is intentionally deferred — .deltaskin discovery can be I/O-heavy during app boot.
        // availableSkins() triggers the scan lazily on first use.
        ILOG("skins: Initializing DeltaSkinManager (scan deferred to first use)")
    }

    /// Get all available skins (protocol conformance)
    public func availableSkins() async throws -> [any DeltaSkinProtocol] {
        ILOG("skins: availableSkins() called - fetching skins")
        let skins = try await availableSkins(forceRescan: false)
        ILOG("skins: availableSkins() returning \(skins.count) skins")
        return skins
    }

    /// Get all available skins
    /// - Parameter forceRescan: If true, forces a rescan even if skins are already loaded. Defaults to false.
    public func availableSkins(forceRescan: Bool = false) async throws -> [any DeltaSkinProtocol] {
        ILOG("skins: availableSkins(forceRescan: \(forceRescan)) called")
        let skins = try await queue.asyncResult {
            // Only scan if we haven't scanned yet, or if forceRescan is true
            if !self.hasScanned || forceRescan || self.configuration.rescansOnEveryRead {
                ILOG("skins: Scanning for skins (hasScanned: \(self.hasScanned), forceRescan: \(forceRescan))")
                try self.scanForSkins()
            } else {
                ILOG("skins: Using cached skins, skipping scan")
            }
            // Return lastScannedSkins which is set synchronously on this queue,
            // rather than loadedSkins which is @Published and updated on MainActor
            // asynchronously (could still be empty when we read it here).
            ILOG("skins: Returning \(self.lastScannedSkins.count) scanned skins")
            return self.lastScannedSkins
        }
        ILOG("skins: availableSkins() completed with \(skins.count) skins")
        return skins
    }

    /// Get a skin by its identifier
    /// - Parameter identifier: The unique identifier of the skin
    /// - Returns: The skin if found, or nil if not found
    public func skin(withIdentifier identifier: String) async throws -> (any DeltaSkinProtocol)? {
        ILOG("skins: skin(withIdentifier: \(identifier)) called")
        let result: (any DeltaSkinProtocol)? = try await queue.asyncResult {
            if let skin = self.lastScannedSkins.first(where: { $0.identifier == identifier }) {
                ILOG("skins: Found skin '\(skin.name)' with identifier '\(identifier)' in cache")
                return skin as (any DeltaSkinProtocol)?
            }

            self.loadSkinPathIndexFromDiskIfNeeded()
            if let path = self.pathIndexByIdentifier[identifier], FileManager.default.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
                if let skin = try? self.loadSkinFromURLWithoutAdding(url), skin.identifier == identifier {
                    if !self.lastScannedSkins.contains(where: { $0.identifier == identifier }) {
                        self.lastScannedSkins.append(skin)
                    }
                    ILOG("skins: Loaded skin '\(skin.name)' via path index for '\(identifier)'")
                    return skin
                }
                self.pathIndexByIdentifier.removeValue(forKey: identifier)
                self.persistSkinPathIndexUnlocked()
            }

            ILOG("skins: Skin '\(identifier)' not in cache or index, scanning")
            try self.scanForSkins()
            if let skin = self.lastScannedSkins.first(where: { $0.identifier == identifier }) {
                ILOG("skins: Found skin '\(skin.name)' with identifier '\(identifier)' after scan")
                return skin as (any DeltaSkinProtocol)?
            }
            WLOG("skins: Skin with identifier '\(identifier)' not found after scan")
            return nil
        }
        if let skin = result {
            ILOG("skins: Returning skin '\(skin.name)' for identifier '\(identifier)'")
        } else {
            WLOG("skins: No skin found for identifier '\(identifier)'")
        }
        return result
    }

    /// Get the currently selected skin for a system in the current session
    /// - Parameters:
    ///   - systemId: The system identifier
    ///   - orientation: The current orientation
    /// - Returns: The session skin identifier if set, otherwise nil
    /// - Note: Delegates to centralized DeltaSkinSelectionManager
    public func sessionSkinIdentifier(for systemId: SkinSystemID, orientation: SkinOrientation) -> String? {
        // Synchronous access to centralized manager (it uses internal queue for thread safety)
        return selectionManager.effectiveSkinIdentifier(
            for: systemId,
            gameId: nil,
            orientation: orientation
        )
    }

    /// Set the session skin for a system
    /// - Parameters:
    ///   - skinIdentifier: The skin identifier to use for the session, or nil to clear
    ///   - systemId: The system identifier
    ///   - orientation: The current orientation
    /// - Note: Delegates to centralized DeltaSkinSelectionManager
    public func setSessionSkin(_ skinIdentifier: String?, for systemId: SkinSystemID, orientation: SkinOrientation) {
        let selectionManager = self.selectionManager
        Task { @MainActor in
            selectionManager.setSkin(
                skinIdentifier,
                for: systemId,
                gameId: nil,
                orientation: orientation,
                scope: .session
            )
        }
    }

    /// Get the selected skin for a system, checking session skins first, then preferences
    /// - Parameters:
    ///   - systemId: The system identifier
    ///   - gameId: The game identifier (optional)
    ///   - orientation: The current orientation
    /// - Returns: The effective skin identifier to use
    /// - Note: Delegates to centralized DeltaSkinSelectionManager
    public func effectiveSkinIdentifier(for systemId: SkinSystemID, gameId: String? = nil, orientation: SkinOrientation) -> String? {
        return selectionManager.effectiveSkinIdentifier(
            for: systemId,
            gameId: gameId,
            orientation: orientation
        )
    }

    /// Load a skin from a file URL
    public func loadSkin(from url: URL) async throws -> any DeltaSkinProtocol {
        try await queue.asyncResult {
            try self.loadSkinFromURL(url)
        }
    }

    /// Scan for available skins.
    /// Must always be called from within a `queue.async` / `queue.asyncResult` block.
    private func scanForSkins() throws {
        dispatchPrecondition(condition: .onQueue(queue))
        // A re-imported skin can keep its identifier and path with a new info.json.
        DeltaSkin.clearRepresentationCache()

        // Prevent concurrent scans
        guard !isScanning else {
            WLOG("skins: Scan already in progress, skipping")
            return
        }

        isScanning = true
        defer { isScanning = false }

        ILOG("skins: Starting skin scan...")
        let locations = skinLocations()
        ILOG("skins: Found \(locations.count) locations to scan")

        // Use Set for O(1) lookup instead of O(n) contains check
        var scannedSkinIdentifiers = Set<String>()
        var scannedSkins: [any DeltaSkinProtocol] = []

        for location in locations {
            ILOG("skins: Examining location: \(location.path)")

            do {
                let isDirectory = (try? location.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                ILOG("skins: Location '\(location.lastPathComponent)' is directory: \(isDirectory)")

                // Handle both directory formats:
                // 1. A .deltaskin directory
                // 2. A directory containing .deltaskin files/directories
                if isDirectory {
                    if hasSkinSuffix(location.lastPathComponent) {
                        // This is a .deltaskin directory, load it directly
                        ILOG("skins: Found skin directory: \(location.lastPathComponent)")
                        if let skin = try? loadSkinFromURLWithoutAdding(location) {
                            if !scannedSkinIdentifiers.contains(skin.identifier) {
                                scannedSkinIdentifiers.insert(skin.identifier)
                                scannedSkins.append(skin)
                                ILOG("skins: Loaded skin '\(skin.name)' (identifier: \(skin.identifier))")
                            } else {
                                ILOG("skins: Skipping duplicate skin '\(skin.name)' (identifier: \(skin.identifier))")
                            }
                        } else {
                            WLOG("skins: Failed to load skin from directory: \(location.lastPathComponent)")
                        }
                    } else {
                        // This is a directory that might contain skins, scan it
                        let contents = try FileManager.default.contentsOfDirectory(
                            at: location,
                            includingPropertiesForKeys: [.isDirectoryKey],
                            options: [.skipsHiddenFiles]
                        )

                        for url in contents where isProbableSkinPackageInDirectory(url) {
                            ILOG("skins: Found skin file in directory: \(url.lastPathComponent)")
                            if let skin = try? loadSkinFromURLWithoutAdding(url) {
                                if !scannedSkinIdentifiers.contains(skin.identifier) {
                                    scannedSkinIdentifiers.insert(skin.identifier)
                                    scannedSkins.append(skin)
                                    ILOG("skins: Loaded skin '\(skin.name)' (identifier: \(skin.identifier))")
                                } else {
                                    ILOG("skins: Skipping duplicate skin '\(skin.name)' (identifier: \(skin.identifier))")
                                }
                            } else {
                                WLOG("skins: Failed to load skin from file: \(url.lastPathComponent)")
                            }
                        }
                    }
                } else if configuration.skinExtensions.contains(location.pathExtension) {
                    // This is a .deltaskin or .manicskin file (archive)
                    ILOG("skins: Found skin archive file: \(location.lastPathComponent)")
                    if let skin = try? loadSkinFromURLWithoutAdding(location) {
                        if !scannedSkinIdentifiers.contains(skin.identifier) {
                            scannedSkinIdentifiers.insert(skin.identifier)
                            scannedSkins.append(skin)
                            ILOG("skins: Loaded skin '\(skin.name)' from archive (identifier: \(skin.identifier))")
                        } else {
                            ILOG("skins: Skipping duplicate skin '\(skin.name)' from archive (identifier: \(skin.identifier))")
                        }
                    } else {
                        WLOG("skins: Failed to load skin from archive: \(location.lastPathComponent)")
                    }
                }
            } catch {
                ELOG("skins: Error scanning location \(location.path): \(error)")
                // Continue scanning other locations
                continue
            }
        }

        // Log results
        ILOG("skins: Scan complete. Found \(scannedSkins.count) total skins. Available skins by type:")
        let groupedSkins = Dictionary(grouping: scannedSkins) { skin in
            // Prefer Delta-style identifier for logging; fallback to Manic; else case name
            skin.gameType.deltaIdentifierString ?? skin.gameType.manicIdentifierString ?? String(describing: skin.gameType)
        }
        for (type, skins) in groupedSkins.sorted(by: { $0.key < $1.key }) {
            ILOG("skins: - \(type): \(skins.count) skins")
            for skin in skins {
                ILOG("skins:   • \(skin.name) (id: \(skin.identifier))")
            }
        }

        // Store scanned results so queue-based callers can read them
        // immediately via lastScannedSkins (loadedSkins is @Published and
        // must be set on MainActor for SwiftUI).
        lastScannedSkins = scannedSkins
        hasScanned = true
        rebuildAndPersistSkinPathIndex(from: scannedSkins)
        ILOG("skins: Scan complete, hasScanned set to true")

        // Capture the current generation so the MainActor task can detect
        // whether a newer scan has already superseded these results.
        scanGeneration += 1
        let generation = scanGeneration

        // Batch update the @Published loadedSkins on the main thread for SwiftUI.
        // Guard against stale updates: if another scan completed while this
        // MainActor task was queued, skip applying these (older) results.
        // Compare against the MainActor-confined `lastAppliedGeneration` to avoid
        // reading queue-confined `scanGeneration` from a different actor context.
        Task { @MainActor in
            guard generation > self.lastAppliedGeneration else {
                ILOG("skins: Skipping stale MainActor update (generation \(generation) already superseded)")
                return
            }
            self.lastAppliedGeneration = generation
            ILOG("skins: Updating loadedSkins with \(scannedSkins.count) skins on main thread")
            self.loadedSkins = scannedSkins
            self.skinsAreLoaded = true
            ILOG("skins: loadedSkins updated on main thread")
        }
    }

    /// Load a skin from URL without adding to loadedSkins (for use during scan)
    private func loadSkinFromURLWithoutAdding(_ url: URL) throws -> any DeltaSkinProtocol {
        ILOG("skins: Loading skin from: \(url.lastPathComponent)")

        do {
            let skin = try DeltaSkin(fileURL: url)
            let typeLabel = skin.gameType.deltaIdentifierString ?? skin.gameType.manicIdentifierString ?? String(describing: skin.gameType)
            ILOG("skins: Successfully loaded skin '\(skin.name)' (type: \(typeLabel), identifier: \(skin.identifier))")
            return skin
        } catch {
            ELOG("skins: Failed to load skin from \(url.lastPathComponent): \(error)")
            if let deltaSkinError = error as? DeltaSkinError {
                ELOG("skins: DeltaSkin Error: \(deltaSkinError)")
            }
            throw error
        }
    }

    /// Load a skin from URL and add to loadedSkins (for manual loading).
    /// Must always be called from within a `queue.async` / `queue.asyncResult` block.
    private func loadSkinFromURL(_ url: URL) throws -> any DeltaSkinProtocol {
        dispatchPrecondition(condition: .onQueue(queue))
        let skin = try loadSkinFromURLWithoutAdding(url)
        // Update lastScannedSkins synchronously so callers see it immediately
        if !lastScannedSkins.contains(where: { $0.identifier == skin.identifier }) {
            lastScannedSkins.append(skin)
        }
        // Mark as having skins available so fast-path lookups work correctly.
        hasScanned = true
        scanGeneration += 1
        let generation = scanGeneration
        // Snapshot the full list now so the MainActor task publishes a complete
        // picture rather than appending only the single new skin.  A previous
        // scanForSkins() MainActor task may be queued with generation < N; by
        // using the full lastScannedSkins snapshot here we avoid leaving
        // loadedSkins in a partial state if that earlier task is skipped as stale.
        let snapshot = lastScannedSkins
        // Update @Published loadedSkins on MainActor for SwiftUI.
        // Use MainActor-confined `lastAppliedGeneration` for the stale-update guard
        // to avoid cross-thread reads of queue-confined `scanGeneration`.
        Task { @MainActor in
            guard generation > self.lastAppliedGeneration else { return }
            self.lastAppliedGeneration = generation
            self.loadedSkins = snapshot
            self.skinsAreLoaded = true
        }
        return skin
    }

    /// `true` for a `.deltaskin` / `.manicskin` name (the extensions in `Configuration.skinExtensions`).
    private func hasSkinSuffix(_ name: String) -> Bool {
        configuration.skinExtensions.contains { name.hasSuffix(".\($0)") }
    }

    /// Whether a URL under a scanned directory (e.g. `Documents/DeltaSkins`) should be opened as a skin archive or package.
    private func isProbableSkinPackageInDirectory(_ url: URL) -> Bool {
        configuration.directoryScanExtensions.contains(url.pathExtension.lowercased())
    }

    /// Get locations of skin files
    private func skinLocations() -> [URL] {
        var locations: [URL] = []

        // Add bundled skins (the app lists them in the configuration)
        let bundleSkins = configuration.bundledSkinLocations()

        if !bundleSkins.isEmpty {
            ILOG("skins: Found \(bundleSkins.count) bundle skins: \(bundleSkins.map { $0.lastPathComponent }.joined(separator: ", "))")
            locations.append(contentsOf: bundleSkins)
        } else {
            WLOG("skins: No skins found in any bundles")
        }

        // Add the imported-skins directory
        let skinsURL = configuration.skinsDirectory
        ILOG("skins: Adding skins directory: \(skinsURL.path)")
        locations.append(skinsURL)

        ILOG("skins: Total locations to scan: \(locations.count)")
        return locations
    }

    /// JSON file under the skins directory mapping skin identifiers to on-disk package paths.
    private func skinPathIndexFileURL() -> URL {
        configuration.skinsDirectory
            .appendingPathComponent(configuration.pathIndexFileName, isDirectory: false)
    }

    /// Loads the persisted path index once per process before the first full scan (hot path for ``skin(withIdentifier:)``).
    private func loadSkinPathIndexFromDiskIfNeeded() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !pathIndexLoadedFromDisk else { return }
        pathIndexLoadedFromDisk = true
        let url = skinPathIndexFileURL()
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        pathIndexByIdentifier = dict
        ILOG("skins: Loaded skin path index from disk (\(dict.count) entries)")
    }

    /// Replaces the in-memory index and persists it after a full scan or import.
    private func rebuildAndPersistSkinPathIndex(from skins: [any DeltaSkinProtocol]) {
        dispatchPrecondition(condition: .onQueue(queue))
        var map: [String: String] = [:]
        for skin in skins {
            map[skin.identifier] = skin.fileURL.path
        }
        pathIndexByIdentifier = map
        persistSkinPathIndexUnlocked()
    }

    private func persistSkinPathIndexUnlocked() {
        dispatchPrecondition(condition: .onQueue(queue))
        let url = skinPathIndexFileURL()
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        guard let data = try? JSONEncoder().encode(pathIndexByIdentifier) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    /// Directory for storing imported skins
    public var skinsDirectory: URL {
        get throws {
            let skinsURL = configuration.skinsDirectory

            // Create directory if it doesn't exist
            if !FileManager.default.fileExists(atPath: skinsURL.path) {
                try FileManager.default.createDirectory(at: skinsURL, withIntermediateDirectories: true)
            }

            return skinsURL
        }
    }

    /// Reload all skins from disk
    @MainActor
    public func reloadSkins() async {
        ILOG("skins: reloadSkins() called")
        do {
            let scannedSkins: [any DeltaSkinProtocol] = try await queue.asyncResult {
                // Force rescan
                ILOG("skins: Forcing rescan of skins")
                self.hasScanned = false
                try self.scanForSkins()
                return self.lastScannedSkins
            }
            // Apply results on MainActor synchronously so callers can rely
            // on loadedSkins being up-to-date when reloadSkins() returns.
            await MainActor.run {
                self.loadedSkins = scannedSkins
                self.skinsAreLoaded = true
                self.objectWillChange.send()
            }
            ILOG("skins: reloadSkins() completed successfully with \(scannedSkins.count) skins")
        } catch {
            ELOG("skins: Failed to reload skins: \(error)")
        }
    }

    /// Import a skin from a URL, handling spaces in paths.
    /// After this method returns, `loadedSkins` is guaranteed to contain the
    /// newly imported skin (the MainActor update is awaited, not fire-and-forget).
    public func importSkin(from url: URL) async throws {
        ILOG("skins: Starting skin import from: \(url.path)")
        defer { DeltaSkin.clearRepresentationCache() }

        let scannedSkins: [any DeltaSkinProtocol] = try await queue.asyncResult { [self] in
            // Get destination in the skins directory
            let skinsDir = try self.skinsDirectory
            let destinationURL = skinsDir.appendingPathComponent(url.lastPathComponent)
            ILOG("skins: Import destination: \(destinationURL.path)")

            // Remove existing file if needed
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                ILOG("skins: Removing existing skin at: \(destinationURL.path)")
                try FileManager.default.removeItem(at: destinationURL)
            }

            // Copy to skins directory
            ILOG("skins: Copying skin to: \(destinationURL.path)")
            try FileManager.default.copyItem(at: url, to: destinationURL)

            do {
                _ = try self.loadSkinFromURLWithoutAdding(destinationURL)
            } catch {
                ELOG("skins: Imported file failed validation (not a readable Delta skin): \(destinationURL.lastPathComponent) — \(error)")
                try? FileManager.default.removeItem(at: destinationURL)
                throw error
            }

            ILOG("skins: Skin import validated and completed successfully")

            // Scan to reload all skins
            try self.scanForSkins()
            return self.lastScannedSkins
        }

        // Apply to loadedSkins synchronously on MainActor so callers see the
        // new skin immediately (no fire-and-forget race).
        await MainActor.run {
            self.loadedSkins = scannedSkins
            self.skinsAreLoaded = true
        }
    }

    /// Check if a skin can be deleted (i.e., it's in the skins directory and not bundled)
    public func isDeletable(_ skin: any DeltaSkinProtocol) -> Bool {
        guard let skinsDir = try? skinsDirectory else { return false }
        return skin.fileURL.path.contains(skinsDir.path)
    }

    /// Delete a skin by its identifier.
    /// After this method returns, `loadedSkins` is guaranteed to reflect the deletion.
    public func deleteSkin(_ identifier: String) async throws {
        defer { DeltaSkin.clearRepresentationCache() }
        /// Captured outside the queue closure so we can drop the catalog sidecar
        /// after the queue work completes (the registry is an actor).
        var deletedSkinURL: URL?
        let scannedSkins: [any DeltaSkinProtocol] = try await queue.asyncResult { [self] in
            // Find the skin (use lastScannedSkins for immediate access on this queue)
            guard let skin = self.lastScannedSkins.first(where: { $0.identifier == identifier }) else {
                throw DeltaSkinError.notFound
            }

            // Verify it's deletable
            guard self.isDeletable(skin) else {
                throw DeltaSkinError.deletionNotAllowed
            }

            // Delete the file
            DLOG("Deleting skin at: \(skin.fileURL.path)")
            try FileManager.default.removeItem(at: skin.fileURL)
            deletedSkinURL = skin.fileURL

            // Rescan on this queue so lastScannedSkins is authoritative.
            self.hasScanned = false
            try self.scanForSkins()
            return self.lastScannedSkins
        }

        /// Drop the matching `<stem>.skinmeta` sidecar so cloud syncers stop
        /// replicating stale metadata for a skin that no longer exists locally.
        if let url = deletedSkinURL {
            await overrideRegistry.removeSidecar(for: url, skinIdentifier: identifier)
        }

        // Apply to loadedSkins synchronously so callers see the deletion immediately.
        await MainActor.run {
            self.loadedSkins = scannedSkins
            self.skinsAreLoaded = true
        }
    }

    /// The registry that holds catalog-derived system overrides and the `.skinmeta` sidecars.
    /// Deleting a skin removes its sidecar through this. Defaults to `.shared`.
    public var overrideRegistry: SkinSystemOverrideRegistry = .shared
}

// MARK: - Helper Extensions
extension DispatchQueue {
    func asyncResult<T>(_ block: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            self.async {
                do {
                    let result = try block()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// Add UTType for .deltaskin files
public extension UTType {
    /// UTType for .deltaskin files. Prefers our exported `com.provenance.deltaskin` (which owns
    /// the .deltaskin extension) so that file pickers accept files the system resolves to our UTI.
    /// Falls back to the imported `com.rileytestut.delta.skin` for interop when Delta is installed.
    static var deltaSkin: UTType {
        UTType("com.provenance.deltaskin") ?? UTType(importedAs: "com.rileytestut.delta.skin")
    }

    /// UTType for the Delta app's native skin identifier, used when interop with Delta is needed.
    static var deltaAppSkin: UTType {
        UTType(importedAs: "com.rileytestut.delta.skin")
    }

    static var manicSkin: UTType {
        // Try to use the imported type from plist first, fallback to dynamic type
        if let importedType = UTType("com.provenance.manicskin") {
            return importedType
        }
        return UTType(filenameExtension: "manicskin", conformingTo: .archive)!
    }
}

// MARK: - Extra Methods for Session Skin Management

extension DeltaSkinManager {
    /// Set or clear the session skin for a specific game
    /// - Parameters:
    ///   - skinIdentifier: The skin identifier to use for the session, or nil to clear
    ///   - systemId: The system identifier
    ///   - gameId: The game identifier
    ///   - orientation: The current orientation
    /// - Note: Delegates to centralized DeltaSkinSelectionManager
    public func setSessionSkin(_ skinIdentifier: String?, for systemId: SkinSystemID, gameId: String, orientation: SkinOrientation) {
        let selectionManager = self.selectionManager
        Task { @MainActor in
            selectionManager.setSkin(
                skinIdentifier,
                for: systemId,
                gameId: gameId,
                orientation: orientation,
                scope: .session
            )
        }
    }

    /// Get the session skin identifier for a specific game
    /// - Parameters:
    ///   - systemId: The system identifier
    ///   - gameId: The game identifier
    ///   - orientation: The current orientation
    /// - Returns: The session skin identifier if set, otherwise nil
    /// - Note: Delegates to centralized DeltaSkinSelectionManager
    public func sessionSkinIdentifier(for systemId: SkinSystemID, gameId: String, orientation: SkinOrientation) -> String? {
        return selectionManager.effectiveGameSkinIdentifier(
            for: systemId,
            gameId: gameId,
            orientation: orientation
        )
    }

    /// Get the effective skin identifier for a game, checking game-specific session skins first,
    /// then system session skins, then game preferences, and finally system preferences
    /// - Parameters:
    ///   - systemId: The system identifier
    ///   - gameId: The game identifier
    ///   - orientation: The current orientation
    /// - Returns: The effective skin identifier to use
    /// - Note: Delegates to centralized DeltaSkinSelectionManager
    public func effectiveGameSkinIdentifier(for systemId: SkinSystemID, gameId: String, orientation: SkinOrientation) -> String? {
        return selectionManager.effectiveGameSkinIdentifier(
            for: systemId,
            gameId: gameId,
            orientation: orientation
        )
    }
}
