import Foundation
import CoreGraphics
import CoreImage
import ZIPFoundation

/// Represents a decoded DeltaSkin file
public struct DeltaSkin: DeltaSkinProtocol {
    /// The decoded info.json contents
    public let info: Info

    /// The URL to the .deltaskin file
    public let fileURL: URL

    /// The raw dictionary from info.json
    private let rawDictionary: [String: Any]

    /// Initialize from either a .deltaskin file or directory
    public init(fileURL: URL) throws {
        self.fileURL = fileURL

        let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        DLOG("Loading DeltaSkin from \(fileURL.lastPathComponent) (isDirectory: \(isDirectory))")

        if isDirectory {
            // Load from directory
            let infoURL = fileURL.appendingPathComponent("info.json")
            guard let infoData = try? Data(contentsOf: infoURL) else {
                ELOG("Missing info.json in directory: \(fileURL.path)")
                throw DeltaSkinError.missingInfoFile
            }

            // Store raw dictionary
            guard let jsonObject = try? JSONSerialization.jsonObject(with: infoData),
                  let rawDict = jsonObject as? [String: Any] else {
                throw DeltaSkinError.invalidInfoFile
            }
            self.rawDictionary = rawDict

            let decoder = JSONDecoder()
            let sanitizedData = try sanitizeJSON(infoData)
            self.info = try decoder.decode(Info.self, from: sanitizedData)

        } else {
            // Load from .deltaskin archive
            guard let archive = try? Archive(url: fileURL, accessMode: .read, pathEncoding: nil) else {
                ELOG("Failed to open archive: \(fileURL.path)")
                throw DeltaSkinError.invalidArchive
            }

            guard let infoEntry = archive["info.json"],
                  let infoData = archive.extractData(infoEntry) else {
                ELOG("Failed to extract info.json from archive: \(fileURL.path)")
                throw DeltaSkinError.missingInfoFile
            }

            // Store raw dictionary
            guard let jsonObject = try? JSONSerialization.jsonObject(with: infoData),
                  let rawDict = jsonObject as? [String: Any] else {
                throw DeltaSkinError.invalidInfoFile
            }
            self.rawDictionary = rawDict

            let decoder = JSONDecoder()
            let sanitizedData = try sanitizeJSON(infoData)
            self.info = try decoder.decode(Info.self, from: sanitizedData)
        }

        DLOG("Successfully loaded skin info: \(info.name)")
    }

    // MARK: - DeltaSkinProtocol Conformance

    public var identifier: String { info.identifier }
    public var name: String { info.name }
    public var gameType: DeltaSkinGameType { info.gameTypeIdentifier }
    public var isDebugEnabled: Bool { info.debug }

    /// True if the skin declared `"caseController": true` in info.json,
    /// OR if the identifier matches known case-controller patterns.
    public var isCaseControllerSkin: Bool {
        info.caseController || DeltaSkinCompanionSkinDetection.isCompanionSkin(identifier)
    }
    /// Keyboard overlay configuration decoded from the skin's `keyboardOverlay` JSON key.
    /// Returns `nil` for skins that do not declare a keyboard overlay.
    public var keyboardOverlay: KeyboardOverlayConfig? { info.keyboardOverlay }

    /// All theme variants bundled in this skin. Empty for legacy skins without themes.
    public var availableThemes: [DeltaSkin.Theme] { info.themes ?? [] }

    /// The currently selected theme ID, persisted per skin in UserDefaults.
    public var selectedThemeId: String? {
        get { DeltaSkinThemeSelection.selectedThemeId(for: identifier) }
        set { DeltaSkinThemeSelection.setSelectedThemeId(newValue, for: identifier) }
    }

    public func supports(_ traits: DeltaSkinTraits) -> Bool {
        let result = representation(for: traits) != nil
        // DLOG: SwiftUI bodies and every fallback check call this; ILOG ships in release builds.
        DLOG("skins: supports() - device: \(traits.device.rawValue), displayType: \(traits.displayType.rawValue), orientation: \(traits.orientation.rawValue) -> \(result)")
        return result
    }

    public func screens(for traits: DeltaSkinTraits) -> [DeltaSkinScreen]? {
        guard let rep = representation(for: traits),
              let screens = rep.screens else {
            return nil
        }

        return screens.enumerated().map { index, screen in
            DeltaSkinScreen(
                id: "\(identifier)-screen-\(index)",
                inputFrame: screen.inputFrame,
                outputFrame: screen.outputFrame,
                placement: screen.placement ?? .controller,
                filters: screen.filters?.compactMap { filter in
                    let ciFilter = CIFilter(name: filter.name)
                    filter.parameters.forEach { key, value in
                        switch value {
                        case .number(let num):
                            ciFilter?.setValue(num, forKey: key)
                        case .vector(let x, let y):
                            ciFilter?.setValue(CIVector(x: CGFloat(x), y: CGFloat(y)), forKey: key)
                        case .color(let r, let g, let b):
                            ciFilter?.setValue(CIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b)), forKey: key)
                        case .rectangle(let x, let y, let width, let height):
                            ciFilter?.setValue(CIVector(x: CGFloat(x), y: CGFloat(y), z: CGFloat(width), w: CGFloat(height)), forKey: key)
                        case .affineTransform(let sx, let sy, let tx, let ty, let rot):
                            // Build a CGAffineTransform: T = Translate * Rotate * Scale
                            var t = CGAffineTransform.identity
                            if let sx = sx, let sy = sy {
                                t = t.scaledBy(x: CGFloat(sx), y: CGFloat(sy))
                            }
                            if let rot = rot { t = t.rotated(by: CGFloat(rot)) }
                            if let tx = tx, let ty = ty { t = t.translatedBy(x: CGFloat(tx), y: CGFloat(ty)) }
                            ciFilter?.setValue(affineTransformValue(t), forKey: key)
                        }
                    }
                    return ciFilter
                },
                filterInfos: screen.filters,
                maintainAspectRatio: screen.maintainAspectRatio
            )
        }
    }

    public func mappingSize(for traits: DeltaSkinTraits) -> CGSize? {
        let rep = representation(for: traits)
        let size = rep?.mappingSize
        if let size = size {
            VLOG("skins: mappingSize() - device: \(traits.device.rawValue), displayType: \(traits.displayType.rawValue), orientation: \(traits.orientation.rawValue) -> \(size)")
        } else {
            ELOG("skins: ERROR - mappingSize() returned nil for traits: \(traits.description)")
        }
        return size
    }

    public func buttons(for traits: DeltaSkinTraits) -> [DeltaSkinButton]? {
        guard let rep = representation(for: traits),
              let items = rep.items else {
            return nil
        }

        return items.enumerated().map { index, item in
            let input: DeltaSkinInput
            switch item.inputs {
            case .single(let inputs):
                input = .single(inputs.first ?? "")
            case .directional(let mapping):
                input = .directional(mapping)
            }

            return DeltaSkinButton(
                id: "\(identifier)-button-\(index)",
                input: input,
                frame: item.frame,
                extendedEdges: item.extendedEdges,
                haptic: item.haptic,
                states: item.states
            )
        }
    }

    public func screenGroups(for traits: DeltaSkinTraits) -> [DeltaSkinScreenGroup]? {
        guard let rep = representation(for: traits),
              let screens = rep.screens else {
            return nil
        }

        return [
            DeltaSkinScreenGroup(
                id: "\(identifier)-screens",
                screens: screens.enumerated().map { index, screen in
                    DeltaSkinScreen(
                        id: "\(identifier)-screen-\(index)",
                        inputFrame: screen.inputFrame,
                        outputFrame: screen.outputFrame,
                        placement: screen.placement ?? .controller,
                        filters: screen.filters?.compactMap { filterInfo in
                            createFilter(from: filterInfo)
                        },
                        filterInfos: screen.filters,
                        maintainAspectRatio: screen.maintainAspectRatio
                    )
                },
                extendedEdges: rep.extendedEdges,
                translucent: rep.translucent ?? false,
                gameScreenFrame: rep.gameScreenFrame
            )
        ]
    }

    /// Returns the `OrientationRepresentations` for the given traits (without converting to RepresentationInfo).
    /// Checks per-game overrides first, then falls back to the default representations.
    private func orientationRepresentations(for traits: DeltaSkinTraits) -> OrientationRepresentations? {
        // Check per-game overrides first
        if let gameOverride = gameOverrideRepresentation(for: traits) {
            return gameOverride
        }
        guard let deviceReps = info.representations[traits.device] else { return nil }
        return resolveOrientationReps(from: deviceReps, traits: traits)
    }

    /// Returns the animated background configuration for the given traits, if any.
    public func backgroundAnimation(for traits: DeltaSkinTraits) -> DeltaSkinBackgroundAnimation? {
        return orientationRepresentations(for: traits)?.backgroundAnimation
    }

    /// Representation lookups by skin + traits. SwiftUI bodies, the skin pickers' cells and their
    /// detached preview renders all call `representation(for:)`, from several threads at once. The
    /// old single key/value pair was written unlocked, so a reader could pair one skin's key with
    /// another skin's value, and alternating cells evicted each other on every call.
    private static let repCacheLock = NSLock()
    private static var repCache: [String: DeltaSkin.RepresentationInfo] = [:]
    private static let repCacheLimit = 256

    private static func cachedRepresentation(forKey key: String) -> DeltaSkin.RepresentationInfo? {
        repCacheLock.withLock { repCache[key] }
    }

    /// Called when skins are scanned, imported or deleted.
    public static func clearRepresentationCache() {
        repCacheLock.withLock { repCache.removeAll() }
    }

    private static func storeRepresentation(_ info: DeltaSkin.RepresentationInfo?, forKey key: String) {
        guard let info else { return }
        repCacheLock.withLock {
            if repCache.count >= repCacheLimit { repCache.removeAll(keepingCapacity: true) }
            repCache[key] = info
        }
    }

    /// Look up an `OrientationRepresentations` from a `DeviceRepresentations` for the given traits,
    /// including standard/edgeToEdge fallback logic.
    private func resolveOrientationReps(from deviceReps: DeviceRepresentations, traits: DeltaSkinTraits) -> OrientationRepresentations? {
        var orientationReps: OrientationRepresentations?
        switch traits.displayType {
        case .standard:
            orientationReps = deviceReps.standard?[traits.orientation.rawValue]
        case .edgeToEdge:
            orientationReps = deviceReps.edgeToEdge?[traits.orientation.rawValue]
        case .splitView:
            orientationReps = deviceReps.splitView?[traits.orientation.rawValue]
        case .stageManager:
            orientationReps = deviceReps.stageManager?[traits.orientation.rawValue]
        case .externalDisplay:
            orientationReps = deviceReps.externalDisplay?[traits.orientation.rawValue]
        }

        // edgeToEdge <-> standard fallback
        if orientationReps == nil && traits.displayType == .edgeToEdge {
            orientationReps = deviceReps.standard?[traits.orientation.rawValue]
        }
        if orientationReps == nil && traits.displayType == .standard {
            orientationReps = deviceReps.edgeToEdge?[traits.orientation.rawValue]
        }
        return orientationReps
    }

    /// Try to find a game-specific override representation for the given traits.
    /// Matches against game title, ROM filename (without extension), and MD5 hash
    /// stored in `traits.gameIdentifier`.
    private func gameOverrideRepresentation(for traits: DeltaSkinTraits) -> OrientationRepresentations? {
        guard let gameId = traits.gameIdentifier,
              let overrides = info.gameOverrides else {
            return nil
        }

        // Try exact match first (game title, filename, or MD5)
        if let deviceMap = overrides[gameId],
           let deviceReps = deviceMap[traits.device.rawValue] {
            if let reps = resolveOrientationReps(from: deviceReps, traits: traits) {
                DLOG("skins: Found game override for '\(gameId)' (exact match)")
                return reps
            }
        }

        // Try case-insensitive match
        let lowerId = gameId.lowercased()
        for (key, deviceMap) in overrides {
            if key.lowercased() == lowerId,
               let deviceReps = deviceMap[traits.device.rawValue],
               let reps = resolveOrientationReps(from: deviceReps, traits: traits) {
                DLOG("skins: Found game override for '\(gameId)' (case-insensitive match on '\(key)')")
                return reps
            }
        }

        return nil
    }

    public func representation(for traits: DeltaSkinTraits) -> DeltaSkin.RepresentationInfo? {
        // Fast-path cache: same skin + traits + game → return cached value without logging.
        // The skin's identity is part of the key: without it, a lookup on one skin returned the
        // representation another skin had just resolved for the same traits (its items and mappingSize).
        let gameKey = traits.gameIdentifier ?? ""
        let cacheKey = "\(identifier)|\(fileURL.path)|\(traits.device.rawValue)-\(traits.displayType.rawValue)-\(traits.orientation.rawValue)-\(gameKey)"
        if let cached = Self.cachedRepresentation(forKey: cacheKey) {
            return cached
        }

        let gameName = traits.gameIdentifier ?? "none"
        VLOG("skins: representation(for:) device=\(traits.device.rawValue) display=\(traits.displayType.rawValue) orient=\(traits.orientation.rawValue) game=\(gameName)")
        VLOG("skins: Available device reps: \(info.representations.keys.map { $0.rawValue })")

        // Check per-game overrides first
        if let gameOverride = gameOverrideRepresentation(for: traits) {
            let result = gameOverride.toRepresentationInfo()
            Self.storeRepresentation(result, forKey: cacheKey)
            return result
        }

        guard let deviceReps = info.representations[traits.device] else {
            ELOG("skins: ERROR - No representation found for device: \(traits.device.rawValue)")
            ELOG("skins: Available devices: \(info.representations.keys.map { $0.rawValue }.joined(separator: ", "))")
            return nil
        }
            VLOG("skins: Found device representation for: \(traits.device.rawValue)")

        // Log available display types for debugging
        var availableDisplayTypes: [String] = []
        if deviceReps.standard != nil { availableDisplayTypes.append("standard") }
        if deviceReps.edgeToEdge != nil { availableDisplayTypes.append("edgeToEdge") }
        if deviceReps.splitView != nil { availableDisplayTypes.append("splitView") }
        if deviceReps.stageManager != nil { availableDisplayTypes.append("stageManager") }
        if deviceReps.externalDisplay != nil { availableDisplayTypes.append("externalDisplay") }
        VLOG("skins: Available display types for \(traits.device.rawValue): \(availableDisplayTypes.joined(separator: ", "))")

        let orientationReps = resolveOrientationReps(from: deviceReps, traits: traits)

        if orientationReps == nil {
            ELOG("skins: ERROR - No orientation representation found for displayType: \(traits.displayType.rawValue), orientation: \(traits.orientation.rawValue), and fallbacks failed")
        }

        let result = orientationReps?.toRepresentationInfo()
        Self.storeRepresentation(result, forKey: cacheKey)
        return result
    }


    /// A named visual theme variant within a skin file
    public struct Theme: Codable, Identifiable {
        /// Unique identifier for the theme (e.g. "dark", "neon")
        public let id: String
        /// Display name shown in the theme picker
        public let name: String
        /// Per-device asset overrides. Keyed by device rawValue → displayType → orientation → AssetRepresentation.
        /// assets["iphone"]["standard"]["portrait"] = AssetRepresentation
        public let assets: [String: [String: [String: AssetRepresentation]]]?
    }

    /// JSON structure for DeltaSkin info.json
    public struct Info: Codable {
        /// Name displayed in Delta's skin selection menu
        public let name: String

        /// Unique identifier in reverse-dns format (e.g. com.yourname.console.skinname)
        public let identifier: String

        /// Identifies which system the skin belongs to
        public let gameTypeIdentifier: DeltaSkinGameType

        /// Whether to show debug overlay of button mappings. Defaults to false when absent.
        public let debug: Bool

        /// Device-specific skin representations
        public let representations: Dictionary<DeltaSkinDevice, DeviceRepresentations>

        /// Optional keyboard overlay configuration. When present, a virtual keyboard
        /// overlay will be available for this skin. Old skins that omit this key
        /// fall back gracefully with no keyboard shown.
        public let keyboardOverlay: KeyboardOverlayConfig?

        /// Optional list of named visual theme variants bundled in this skin.
        /// Legacy skins that omit this key have no themes (empty array).
        public let themes: [Theme]?

        /// Per-game layout overrides. Keys are game identifiers (title, ROM filename without
        /// extension, or MD5 hash). Values map device rawValue to orientation representations,
        /// mirroring the structure of `DeviceRepresentations`.
        ///
        /// Example JSON:
        /// ```json
        /// "gameOverrides": {
        ///   "Alien vs Predator": {
        ///     "iphone": { "standard": { "portrait": { ... } } }
        ///   }
        /// }
        /// ```
        public let gameOverrides: [String: [String: DeviceRepresentations]]?

        /// Whether this skin is designed for a physical phone-case controller.
        /// Set `"caseController": true` in info.json to mark a skin as case-specific.
        /// Defaults to `false` when absent.
        public let caseController: Bool

        private enum CodingKeys: String, CodingKey {
            case name, identifier, gameTypeIdentifier, debug, representations, keyboardOverlay, themes, gameOverrides, caseController
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            name = try container.decode(String.self, forKey: .name)
            identifier = try container.decode(String.self, forKey: .identifier)
            gameTypeIdentifier = try container.decode(DeltaSkinGameType.self, forKey: .gameTypeIdentifier)
            debug = try container.decodeIfPresent(Bool.self, forKey: .debug) ?? false

            // Manually decode the dictionary with string keys
            let repContainer = try container.nestedContainer(keyedBy: StringCodingKey.self, forKey: .representations)
            var reps: [DeltaSkinDevice: DeviceRepresentations] = [:]

            for key in repContainer.allKeys {
                if let device = DeltaSkinDevice(rawValue: key.stringValue) {
                    let value = try repContainer.decode(DeviceRepresentations.self, forKey: key)
                    reps[device] = value
                }
            }

            representations = reps
            keyboardOverlay = try container.decodeIfPresent(KeyboardOverlayConfig.self, forKey: .keyboardOverlay)
            themes = try container.decodeIfPresent([Theme].self, forKey: .themes)

            caseController = try container.decodeIfPresent(Bool.self, forKey: .caseController) ?? false

            // Decode per-game overrides
            if container.contains(.gameOverrides) {
                let overridesContainer = try container.nestedContainer(keyedBy: StringCodingKey.self, forKey: .gameOverrides)
                var overrides: [String: [String: DeviceRepresentations]] = [:]

                for gameKey in overridesContainer.allKeys {
                    let deviceContainer = try overridesContainer.nestedContainer(keyedBy: StringCodingKey.self, forKey: gameKey)
                    var deviceReps: [String: DeviceRepresentations] = [:]
                    for deviceKey in deviceContainer.allKeys {
                        let value = try deviceContainer.decode(DeviceRepresentations.self, forKey: deviceKey)
                        deviceReps[deviceKey.stringValue] = value
                    }
                    overrides[gameKey.stringValue] = deviceReps
                }
                gameOverrides = overrides
            } else {
                gameOverrides = nil
            }
        }
    }

    /// Display types for different device modes
    public enum DisplayType: String, Codable {
        case standard
        case edgeToEdge
        case splitView
        case stageManager
        case externalDisplay
    }

    /// Represents device-specific configurations
    public struct DeviceRepresentations: Codable {
        public let standard: [String: OrientationRepresentations]?
        public let edgeToEdge: [String: OrientationRepresentations]?
        public let splitView: [String: OrientationRepresentations]?
        public let stageManager: [String: OrientationRepresentations]?
        public let externalDisplay: [String: OrientationRepresentations]?
        public let mini: [String: OrientationRepresentations]?
        public let pro13: [String: OrientationRepresentations]?
        public let dedicated: [String: OrientationRepresentations]?

        private enum CodingKeys: String, CodingKey {
            case standard
            case edgeToEdge = "edgeToEdge"
            case splitView = "splitView"
            case stageManager = "stageManager"
            case externalDisplay = "externalDisplay"
            case mini
            case pro13
            case dedicated
        }
    }

    /// Represents orientation-specific configurations
    public struct OrientationRepresentations: Codable {
        /// Assets dictionary for skin images
        public let assets: AssetRepresentation?

        /// Button and control mappings
        public let items: [ItemRepresentation]?

        /// Screen configurations
        public let screens: [ScreenInfo]?

        /// Size in points for mapping coordinates
        public let mappingSize: CGSize?

        /// Extended touch edges
        public let extendedEdges: DeltaSkinEdgeInsets?

        /// Whether the skin supports opacity adjustment
        public let translucent: Bool?

        /// Frame for the game screen
        public let gameScreenFrame: CGRect?

        /// Optional animated background configuration
        public let backgroundAnimation: DeltaSkinBackgroundAnimation?

        private enum CodingKeys: String, CodingKey {
            case assets, items, screens, mappingSize, extendedEdges, translucent, gameScreenFrame, backgroundAnimation
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            assets = try container.decodeIfPresent(AssetRepresentation.self, forKey: .assets)
            items = try container.decodeIfPresent([ItemRepresentation].self, forKey: .items)
            screens = try container.decodeIfPresent([ScreenInfo].self, forKey: .screens)

            // Use decodeIfPresent for mappingSize
            if let sizeContainer = try? container.superDecoder(forKey: .mappingSize) {
                mappingSize = try CGSize(fromDeltaSkin: sizeContainer)
            } else {
                mappingSize = nil
            }

            // Handle optional extended edges with more robust null checking
            if container.contains(.extendedEdges),
               let edgeContainer = try? container.superDecoder(forKey: .extendedEdges),
               let edges = try? DeltaSkinEdgeInsets(fromDeltaSkin: edgeContainer) {
                extendedEdges = edges
            } else {
                extendedEdges = nil
            }

            translucent = try container.decodeIfPresent(Bool.self, forKey: .translucent)

            // Decode gameScreenFrame if present
            if let frameContainer = try? container.superDecoder(forKey: .gameScreenFrame),
               let frame = try? CGRect(fromDeltaSkin: frameContainer) {
                gameScreenFrame = frame
            } else {
                gameScreenFrame = nil
            }

            backgroundAnimation = try container.decodeIfPresent(DeltaSkinBackgroundAnimation.self, forKey: .backgroundAnimation)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(assets, forKey: .assets)
            try container.encodeIfPresent(items, forKey: .items)
            try container.encodeIfPresent(screens, forKey: .screens)
            try mappingSize?.encodeDeltaSkin(to: container.superEncoder(forKey: .mappingSize))
            try container.encodeIfPresent(extendedEdges, forKey: .extendedEdges)
            try container.encodeIfPresent(translucent, forKey: .translucent)

            if let frame = gameScreenFrame {
                try frame.encodeDeltaSkin(to: container.superEncoder(forKey: .gameScreenFrame))
            }

            try container.encodeIfPresent(backgroundAnimation, forKey: .backgroundAnimation)
        }

        /// Convert to RepresentationInfo
        public func toRepresentationInfo() -> DeltaSkin.RepresentationInfo {
            // Create a default asset representation if none exists
            let defaultAssets = DeltaSkin.AssetRepresentation(
                resizable: nil,
                small: nil,
                medium: nil,
                large: nil
            )

            // Validate assets
            if let assets = assets {
                // Allow both PDF and PNG for resizable assets
                if let resizable = assets.resizable,
                   !resizable.hasSuffix(".pdf") && !resizable.hasSuffix(".png") && !resizable.hasSuffix(".svg") {
                    ELOG("Resizable asset must be a PDF, PNG, or SVG file")
                    return DeltaSkin.RepresentationInfo(
                        assets: defaultAssets,
                        mappingSize: mappingSize ?? CGSize(width: 0, height: 0),
                        translucent: translucent,
                        screens: screens,
                        items: items,
                        extendedEdges: extendedEdges,
                        gameScreenFrame: gameScreenFrame
                    )
                }
            }

            return DeltaSkin.RepresentationInfo(
                assets: assets ?? defaultAssets,
                mappingSize: mappingSize ?? CGSize(width: 0, height: 0),
                translucent: translucent,
                screens: screens,
                items: items,
                extendedEdges: extendedEdges,
                gameScreenFrame: gameScreenFrame
            )
        }
    }

    /// Asset representation in a skin
    public struct AssetRepresentation: Codable {
        /// Resizable PDF or PNG asset filename
        public let resizable: String?

        /// Size-specific PNG asset filenames
        public let small: String?
        public let medium: String?
        public let large: String?

        /// Get filename for a specific size
        public func filename(for size: DeltaSkinAssetSize) -> String? {
            switch size {
            case .resizable: return resizable
            case .small: return small
            case .medium: return medium
            case .large: return large
            }
        }

        /// Candidate filenames in priority order, de-duplicated
        public func candidates() -> [String] {
            var list: [String] = []
            if let r = resizable { list.append(r) }
            if let l = large { list.append(l) }
            if let m = medium { list.append(m) }
            if let s = small { list.append(s) }
            // De-duplicate while preserving order
            var seen = Set<String>()
            return list.filter { seen.insert($0).inserted }
        }

        /// The filename to use for this asset
        public var filename: String {
            // Try resizable first
            if let resizable = resizable {
                return resizable
            }

            // Fall back to largest available size
            if let large = large {
                return large
            }
            if let medium = medium {
                return medium
            }
            if let small = small {
                return small
            }

            // If we get here, something's wrong with the skin
            fatalError("Invalid asset configuration")
        }

        private enum CodingKeys: String, CodingKey {
            case resizable, small, medium, large
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Decode optional fields and sanitize empty/whitespace values to nil
            func clean(_ s: String?) -> String? {
                guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
                return t
            }
            let rawResizable = try container.decodeIfPresent(String.self, forKey: .resizable)
            let rawSmall = try container.decodeIfPresent(String.self, forKey: .small)
            let rawMedium = try container.decodeIfPresent(String.self, forKey: .medium)
            let rawLarge = try container.decodeIfPresent(String.self, forKey: .large)

            resizable = clean(rawResizable)
            small = clean(rawSmall)
            medium = clean(rawMedium)
            large = clean(rawLarge)

            // Do not hard-fail on missing or invalid asset names here.
            // Validation and fallbacks are handled in toRepresentationInfo().
        }

        public init(resizable: String?, small: String?, medium: String?, large: String?) {
            self.resizable = resizable
            self.small = small
            self.medium = medium
            self.large = large
        }
    }

    /// Represents a button or control mapping
    public struct ItemRepresentation: Codable {
        /// Input mappings (single, multiple, or directional)
        public let inputs: InputType

        /// Frame rectangle in points
        public let frame: CGRect

        /// Extended touch edges
        public let extendedEdges: DeltaSkinEdgeInsets?

        /// Optional thumbstick configuration
        public let thumbstick: ThumbstickConfig?

        /// Optional per-button haptic feedback configuration
        public let haptic: DeltaSkinHaptic?

        /// Optional per-button visual states (normal/pressed images, animated frames)
        public let states: DeltaSkinButtonStates?

        private enum CodingKeys: String, CodingKey {
            case inputs, frame, extendedEdges, thumbstick, haptic, states
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            inputs = try container.decode(InputType.self, forKey: .inputs)
            frame = try CGRect(fromDeltaSkin: container.superDecoder(forKey: .frame))

            // Handle optional extended edges with direct dictionary decoding
            if container.contains(.extendedEdges),
               let edgeContainer = try? container.nestedContainer(keyedBy: DeltaSkinCodingKeys.self, forKey: .extendedEdges) {
                let top = try edgeContainer.decodeIfPresent(CGFloat.self, forKey: .top) ?? 0
                let left = try edgeContainer.decodeIfPresent(CGFloat.self, forKey: .left) ?? 0
                let bottom = try edgeContainer.decodeIfPresent(CGFloat.self, forKey: .bottom) ?? 0
                let right = try edgeContainer.decodeIfPresent(CGFloat.self, forKey: .right) ?? 0
                extendedEdges = DeltaSkinEdgeInsets(top: top, left: left, bottom: bottom, right: right)
            } else {
                extendedEdges = nil
            }

            thumbstick = try container.decodeIfPresent(ThumbstickConfig.self, forKey: .thumbstick)
            haptic = try container.decodeIfPresent(DeltaSkinHaptic.self, forKey: .haptic)
            states = try container.decodeIfPresent(DeltaSkinButtonStates.self, forKey: .states)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(inputs, forKey: .inputs)
            try frame.encodeDeltaSkin(to: container.superEncoder(forKey: .frame))

            if let edges = extendedEdges {
                try edges.encodeDeltaSkin(to: container.superEncoder(forKey: .extendedEdges))
            }

            try container.encodeIfPresent(thumbstick, forKey: .thumbstick)
            try container.encodeIfPresent(haptic, forKey: .haptic)
            try container.encodeIfPresent(states, forKey: .states)
        }
    }

    /// Represents different types of input configurations
    public enum InputType: Codable {
        case single([String])          // ["a"]
        case directional([String: String])  // {"up": "up", "down": "down"}

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            if let array = try? container.decode([String].self) {
                self = .single(array)
            } else if let dict = try? container.decode([String: String].self) {
                self = .directional(dict)
            } else {
                throw DecodingError.typeMismatch(
                    InputType.self,
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected either array of strings or directional mapping"
                    )
                )
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .single(let array):
                try container.encode(array)
            case .directional(let dict):
                try container.encode(dict)
            }
        }
    }

    /// Configuration for thumbstick controls
    public struct ThumbstickConfig: Codable {
        public let name: String
        public let width: CGFloat
        public let height: CGFloat
    }

    /// Screen configuration and filters
    public struct ScreenInfo: Codable {
        public let inputFrame: CGRect?
        public let outputFrame: CGRect?
        public let placement: DeltaSkinScreenPlacement?
        public let filters: [FilterInfo]?
        /// When `true` (default) the emulator viewport should maintain the system's
        /// native pixel aspect ratio rather than stretching to fill `outputFrame`.
        public let maintainAspectRatio: Bool

        private enum CodingKeys: String, CodingKey {
            case inputFrame, outputFrame, placement, filters, maintainAspectRatio
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Decode inputFrame if present
            if let inputContainer = try? container.nestedContainer(keyedBy: DeltaSkinCodingKeys.self, forKey: .inputFrame) {
                let x = try inputContainer.decode(CGFloat.self, forKey: .x)
                let y = try inputContainer.decode(CGFloat.self, forKey: .y)
                let width = try inputContainer.decode(CGFloat.self, forKey: .width)
                let height = try inputContainer.decode(CGFloat.self, forKey: .height)
                inputFrame = CGRect(x: x, y: y, width: width, height: height)
            } else {
                inputFrame = nil
            }

            // Decode optional outputFrame
            if let outputContainer = try? container.nestedContainer(keyedBy: DeltaSkinCodingKeys.self, forKey: .outputFrame) {
                let x = try outputContainer.decode(CGFloat.self, forKey: .x)
                let y = try outputContainer.decode(CGFloat.self, forKey: .y)
                let width = try outputContainer.decode(CGFloat.self, forKey: .width)
                let height = try outputContainer.decode(CGFloat.self, forKey: .height)
                outputFrame = CGRect(x: x, y: y, width: width, height: height)
            } else {
                outputFrame = nil
            }

            // Decode optional fields
            placement = try container.decodeIfPresent(DeltaSkinScreenPlacement.self, forKey: .placement)
            filters = try container.decodeIfPresent([FilterInfo].self, forKey: .filters)
            maintainAspectRatio = try container.decodeIfPresent(Bool.self, forKey: .maintainAspectRatio) ?? true
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            // Encode inputFrame if present
            if let inputFrame = inputFrame {
                var inputContainer = container.nestedContainer(keyedBy: DeltaSkinCodingKeys.self, forKey: .inputFrame)
                try inputContainer.encode(inputFrame.origin.x, forKey: .x)
                try inputContainer.encode(inputFrame.origin.y, forKey: .y)
                try inputContainer.encode(inputFrame.size.width, forKey: .width)
                try inputContainer.encode(inputFrame.size.height, forKey: .height)
            }

            // Encode optional outputFrame
            if let frame = outputFrame {
                var outputContainer = container.nestedContainer(keyedBy: DeltaSkinCodingKeys.self, forKey: .outputFrame)
                try outputContainer.encode(frame.origin.x, forKey: .x)
                try outputContainer.encode(frame.origin.y, forKey: .y)
                try outputContainer.encode(frame.size.width, forKey: .width)
                try outputContainer.encode(frame.size.height, forKey: .height)
            }

            // Encode optional fields
            try container.encodeIfPresent(placement, forKey: .placement)
            try container.encodeIfPresent(filters, forKey: .filters)
            try container.encode(maintainAspectRatio, forKey: .maintainAspectRatio)
        }
    }

    /// CoreImage filter configuration
    public struct FilterInfo: Codable, Sendable {
        public let name: String
        public let parameters: [String: FilterParameter]

        public init(name: String, parameters: [String: FilterParameter] = [:]) {
            self.name = name
            self.parameters = parameters
        }

        private enum CodingKeys: String, CodingKey {
            case name, parameters
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            let rawParameters = try container.decodeIfPresent([String: FilterParameter].self, forKey: .parameters) ?? [:]

            // Sanitize parameters during decoding
            if name == "CIGaussianBlur" {
                parameters = rawParameters.filter { key, _ in
                    key == "inputRadius"
                }
            } else {
                parameters = rawParameters
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(parameters, forKey: .parameters)
        }
    }

    /// Add this to the DeltaSkin struct
    public struct RepresentationInfo: Codable {
        /// Assets for this representation
        public let assets: AssetRepresentation

        /// Size in points for mapping coordinates
        public let mappingSize: CGSize

        /// Whether the skin supports opacity adjustment
        public let translucent: Bool?

        /// Screen configurations
        public let screens: [ScreenInfo]?

        /// Button and control mappings
        public let items: [ItemRepresentation]?

        /// Extended touch edges
        public let extendedEdges: DeltaSkinEdgeInsets?

        /// Frame for the game screen
        public let gameScreenFrame: CGRect?

        public init(assets: AssetRepresentation, mappingSize: CGSize = .zero, translucent: Bool? = nil, screens: [ScreenInfo]? = nil, items: [ItemRepresentation]? = nil, extendedEdges: DeltaSkinEdgeInsets? = nil, gameScreenFrame: CGRect? = nil) {
            self.assets = assets
            self.mappingSize = mappingSize
            self.translucent = translucent
            self.screens = screens
            self.items = items
            self.extendedEdges = extendedEdges
            self.gameScreenFrame = gameScreenFrame
        }
    }

    public var jsonRepresentation: [String: Any] {
        return rawDictionary
    }

    /// Convert representation info into button group
    public func toButtonGroup(from rep: RepresentationInfo) -> DeltaSkinButtonGroup {
        let buttons = rep.items?.map { item -> DeltaSkinButton in
            // Convert input type
            let input: DeltaSkinInput
            switch item.inputs {
            case .single(let inputs):
                // Use first input as primary if multiple exist
                input = .single(inputs[0])
            case .directional(let mapping):
                input = .directional(mapping)
            }

            // Create unique ID from input
            let id: String
            switch input {
            case .single(let name): id = name
            case .directional: id = "dpad"
            }

            return DeltaSkinButton(
                id: id,
                input: input,
                frame: item.frame,
                extendedEdges: item.extendedEdges,
                haptic: item.haptic,
                states: item.states
            )
        } ?? []

        return DeltaSkinButtonGroup(
            buttons: buttons,
            extendedEdges: rep.extendedEdges,
            translucent: rep.translucent
        )
    }

    /// Safely sanitizes filter parameters for known problematic filters
    private func sanitizeFilterParameters(_ filterInfo: FilterInfo) -> [String: FilterParameter] {
        var parameters = filterInfo.parameters

        // Handle CIGaussianBlur - only allow inputRadius
        if filterInfo.name == "CIGaussianBlur" {
            parameters = parameters.filter { key, _ in
                key == "inputRadius"
            }
        }

        return parameters
    }

    private func createFilter(from filterInfo: FilterInfo) -> CIFilter? {
        // Use custom screen filter for special effects
        if let screenFilter = DeltaSkinScreenFilter(filterInfo: filterInfo) {
            return screenFilter.filter
        }
        return nil
    }
}

/// Helper for string-keyed coding keys
private struct StringCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

// MARK: - Error Types
public enum DeltaSkinError: Error {
    case invalidArchive
    case missingInfoFile
    case invalidInfoFile
    case unsupportedTraits
    case missingAsset
    case missingAssetFile
    case invalidPDF
    case invalidPNG
    case invalidSVG
    case invalidAssetSize
    case invalidScreenConfiguration
    case invalidButtonConfiguration
    case accessDenied
    case notFound
    case deletionNotAllowed
}

public extension Archive {
    /// Exact path, then a case-insensitive match on the last path component.
    ///
    /// If that file was never packed, try the same stem as `.pdf`, `.png`, or `.svg`.
    /// Delta skins often name a PNG in `info.json` while the archive only contains the PDF.
    func entry(matchingAssetNamed filename: String) -> Entry? {
        if let exact = self[filename] { return exact }
        let wanted = (filename as NSString).lastPathComponent
        let wantedLower = wanted.lowercased()
        guard !wantedLower.isEmpty else { return nil }
        if let match = first(where: { ($0.path as NSString).lastPathComponent.lowercased() == wantedLower }) {
            return match
        }
        let stem = (wanted as NSString).deletingPathExtension.lowercased()
        guard !stem.isEmpty else { return nil }
        for ext in ["pdf", "png", "svg"] {
            let candidate = "\(stem).\(ext)"
            guard candidate != wantedLower else { continue }
            if let match = first(where: { ($0.path as NSString).lastPathComponent.lowercased() == candidate }) {
                return match
            }
        }
        return nil
    }

    func extractData(_ entry: Entry) -> Data? {
        var data = Data()
        do {
            _ = try self.extract(entry) { chunk in
                data.append(chunk)
            }
            return data
        } catch {
            return nil
        }
    }
}

private func sanitizeJSON(_ data: Data) throws -> Data {
    guard let jsonString = String(data: data, encoding: .utf8) else {
        throw DeltaSkinError.invalidInfoFile
    }

    // Remove single line comments and handle special fields
    var lines = jsonString.components(separatedBy: .newlines)
    lines = lines.map { line in
        var line = line

        // Handle special comment fields that are valid JSON
        if line.contains("\"_comment\"") {
            return line
        }

        // Remove standard comments
        if let commentIndex = line.range(of: "//")?.lowerBound {
            line = String(line[..<commentIndex])
        }

        return line.trimmingCharacters(in: .whitespaces)
    }
    .filter { !$0.isEmpty }

    // Rejoin and convert back to data
    let sanitized = lines.joined(separator: "\n")
    guard let sanitizedData = sanitized.data(using: .utf8) else {
        throw DeltaSkinError.invalidInfoFile
    }

    return sanitizedData
}

/// Asset size options for Delta skins
public enum DeltaSkinAssetSize: String {
    case small
    case medium
    case large
    case resizable
}
