import Combine
import Foundation
import SkinKitCore

/// Orientation for skin selection
public enum SkinOrientation: String, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case portrait
    case landscape

    public var id: String {
        rawValue
    }

    public static var allCases: [SkinOrientation] {
        [.portrait, .landscape]
    }

    public var displayName: String {
        switch self {
        case .portrait: return "Portrait"
        case .landscape: return "Landscape"
        }
    }

    public var icon: String {
        switch self {
        case .portrait: return "iphone"
        case .landscape: return "iphone.landscape"
        }
    }

    public var deltaSkinOrientation: DeltaSkinOrientation {
        switch self {
        case .portrait: return .portrait
        case .landscape: return .landscape
        }
    }
}

/// Manages user preferences for Delta skins
///
/// Moved from Provenance. Storage keys and formats are unchanged, so existing selections keep
/// applying:
/// - `com.provenance.deltaskin.preferences.v2`: `{systemRawValue: {orientation: skinId}}` JSON
/// - `com.provenance.deltaskin.preferences`: the legacy `{systemRawValue: skinId}` JSON, migrated
///   to v2 (as portrait) on first load and then removed
/// - `com.provenance.deltaskin.game.preferences.v1`: `{gameId: {orientation: skinId}}` JSON
/// - `com.provenance.deltaskin.game.altRepresentations.v1`: `{gameId: [skinId]}` JSON, the skins whose alternate
///   layout (`altRepresentations`) is on for that game. New in SkinKit; see ``DeltaSkinAltRepresentationsStoring``.
public final class DeltaSkinPreferences: ObservableObject, DeltaSkinAltRepresentationsStoring {
    /// Shared instance, backed by `UserDefaults.standard`.
    public static let shared = DeltaSkinPreferences()

    /// Currently selected skin identifier for each system and orientation
    @Published public private(set) var selectedSkins: [SkinSystemID: [SkinOrientation: String]] = [:]

    /// Currently selected skin identifier for specific games
    @Published public private(set) var gameSpecificSkins: [String: [SkinOrientation: String]] = [:]

    /// UserDefaults key for storing skin preferences
    public static let preferencesKey = "com.provenance.deltaskin.preferences.v2"

    /// UserDefaults key for storing game-specific skin preferences
    public static let gamePreferencesKey = "com.provenance.deltaskin.game.preferences.v1"

    /// UserDefaults key for the per-game alternate-layout choice: `{gameId: [skinId]}` JSON.
    public static let gameAltRepresentationsKey = "com.provenance.deltaskin.game.altRepresentations.v1"

    /// For each game key, the skins whose alternate layout set is on for that game.
    @Published public private(set) var gameAltRepresentations: [String: Set<String>] = [:]

    /// UserDefaults key of the pre-orientation format, read once and then removed.
    public static let legacyPreferencesKey = "com.provenance.deltaskin.preferences"

    /// Called with the skin identifier after a system-level pick (never for the built-in token).
    ///
    /// Provenance used this spot to tell `CaseControllerDetector` that the user picked a skin made
    /// for a physical case (`CaseControllerDetector.notifyIfCaseSkin`; passive cases such as Buppin
    /// can only be identified through their companion skin's identifier). That is Provenance's code,
    /// so the app sets this at launch, on iOS only, as before.
    public var systemSkinSelectionObserver: (@MainActor (_ skinIdentifier: String) -> Void)?

    private let defaults: UserDefaults

    /// - Parameter defaults: where selections persist. Tests pass an isolated suite.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadPreferences()
    }

    /// Get the selected skin identifier for a system and orientation
    /// - Parameters:
    ///   - system: The system identifier
    ///   - orientation: The orientation (portrait or landscape)
    /// - Returns: The selected skin identifier, or nil if none selected
    public func selectedSkinIdentifier(for system: SkinSystemID, orientation: SkinOrientation = .portrait) -> String? {
        return selectedSkins[system]?[orientation]
    }

    /// Get the selected skin identifier for a specific game
    /// - Parameters:
    ///   - gameId: The game's unique identifier
    ///   - orientation: The orientation (portrait or landscape)
    /// - Returns: The selected skin identifier, or nil if none selected
    public func selectedSkinIdentifier(for gameId: String, orientation: SkinOrientation = .portrait) -> String? {
        return gameSpecificSkins[gameId]?[orientation]
    }

    /// Get the selected skin identifier for a game, falling back to system if not set
    /// - Parameters:
    ///   - gameId: The game's unique identifier
    ///   - system: The system identifier (fallback)
    ///   - orientation: The orientation (portrait or landscape)
    /// - Returns: The selected skin identifier, or nil if none selected
    public func effectiveSkinIdentifier(for gameId: String, system: SkinSystemID, orientation: SkinOrientation = .portrait) -> String? {
        // First check for game-specific preference
        if let gameSkin = selectedSkinIdentifier(for: gameId, orientation: orientation) {
            return gameSkin
        }

        // Fall back to system preference
        return selectedSkinIdentifier(for: system, orientation: orientation)
    }

    /// Get the selected skin identifier for a system (legacy method)
    /// - Parameter system: The system identifier
    /// - Returns: The selected skin identifier for portrait orientation, or nil if none selected
    public func selectedSkinIdentifier(for system: SkinSystemID) -> String? {
        return selectedSkinIdentifier(for: system, orientation: .portrait)
    }

    /// Set the selected skin for a system and orientation
    /// - Parameters:
    ///   - skinIdentifier: The skin identifier to select
    ///   - system: The system identifier
    ///   - orientation: The orientation (portrait or landscape)
    @MainActor
    public func setSelectedSkin(_ skinIdentifier: String?, for system: SkinSystemID, orientation: SkinOrientation = .portrait) {
        if let skinIdentifier = skinIdentifier {
            if selectedSkins[system] == nil {
                selectedSkins[system] = [:]
            }
            selectedSkins[system]?[orientation] = skinIdentifier

            // Built-in preference sentinel is not a real skin id — never hand it to the observer.
            if skinIdentifier != DeltaSkinSelectionManager.builtInSkinPreferenceToken {
                systemSkinSelectionObserver?(skinIdentifier)
            }
        } else {
            selectedSkins[system]?[orientation] = nil

            // If both orientations are nil, remove the system entry entirely
            if selectedSkins[system]?.isEmpty ?? true {
                selectedSkins.removeValue(forKey: system)
            }
        }
        savePreferences()
    }

    /// Set the selected skin for a system (legacy method)
    /// - Parameters:
    ///   - skinIdentifier: The skin identifier to select
    ///   - system: The system identifier
    @MainActor
    public func setSelectedSkin(_ skinIdentifier: String?, for system: SkinSystemID) {
        setSelectedSkin(skinIdentifier, for: system, orientation: .portrait)
    }

    /// Set the selected skin for a specific game
    /// - Parameters:
    ///   - skinIdentifier: The skin identifier to select
    ///   - gameId: The game's unique identifier
    ///   - orientation: The orientation (portrait or landscape)
    @MainActor
    public func setSelectedSkin(_ skinIdentifier: String?, for gameId: String, orientation: SkinOrientation = .portrait) {
        if let skinIdentifier = skinIdentifier {
            if gameSpecificSkins[gameId] == nil {
                gameSpecificSkins[gameId] = [:]
            }
            gameSpecificSkins[gameId]?[orientation] = skinIdentifier
        } else {
            gameSpecificSkins[gameId]?[orientation] = nil

            // If both orientations are nil, remove the game entry entirely
            if gameSpecificSkins[gameId]?.isEmpty ?? true {
                gameSpecificSkins.removeValue(forKey: gameId)
            }
        }
        saveGamePreferences()
    }

    // MARK: - Theme Selection

    /// Get the selected theme ID for a skin.
    /// - Parameter skinIdentifier: The skin's unique identifier.
    /// - Returns: The selected theme ID, or nil if none selected (uses default).
    ///
    /// Same storage as `DeltaSkin.selectedThemeId`: `UserDefaultsThemeSelection` in SkinKitCore.
    public func selectedThemeId(for skinIdentifier: String) -> String? {
        DeltaSkinThemeSelection.selectedThemeId(for: skinIdentifier)
    }

    /// Set the selected theme ID for a skin, persisted in UserDefaults.
    /// - Parameters:
    ///   - id: The theme ID to select, or nil to revert to default.
    ///   - skinIdentifier: The skin's unique identifier.
    public func setSelectedThemeId(_ id: String?, for skinIdentifier: String) {
        DeltaSkinThemeSelection.setSelectedThemeId(id, for: skinIdentifier)
    }

    // MARK: - Alternate layout (altRepresentations)

    /// Whether the skin's alternate layout set is on for the game, checking every key the game may be stored under.
    ///
    /// The choice has the game skin pick's scope: one per game, stored per skin so turning it on for one skin does
    /// not flip another skin the game may use later. `false` when nothing is stored.
    public func usesAltRepresentations(skinIdentifier: String, gameIds: [String]) -> Bool {
        gameIds.contains { !$0.isEmpty && gameAltRepresentations[$0]?.contains(skinIdentifier) == true }
    }

    /// Persists the alternate-layout choice for a skin in a game.
    ///
    /// Written under `gameId` (Provenance passes `PVGame.id`, as the skin pickers do). Turning it off also clears
    /// the choice under `otherGameKeys` (md5, crc), so an older entry stored under another key can't keep it on.
    @MainActor
    public func setUsesAltRepresentations(_ usesAlt: Bool, skinIdentifier: String, gameId: String, otherGameKeys: [String] = []) {
        guard !gameId.isEmpty else { return }
        if usesAlt {
            gameAltRepresentations[gameId, default: []].insert(skinIdentifier)
        } else {
            for key in [gameId] + otherGameKeys where !key.isEmpty {
                gameAltRepresentations[key]?.remove(skinIdentifier)
                if gameAltRepresentations[key]?.isEmpty == true { gameAltRepresentations.removeValue(forKey: key) }
            }
        }
        saveGameAltRepresentations()
    }

    // MARK: - Persistence

    /// Load preferences from UserDefaults
    private func loadPreferences() {
        loadSystemPreferences()
        loadGamePreferences()
        loadGameAltRepresentations()
    }

    private func loadGameAltRepresentations() {
        guard let data = defaults.data(forKey: Self.gameAltRepresentationsKey),
              let stored = try? JSONDecoder().decode([String: [String]].self, from: data) else { return }
        gameAltRepresentations = stored.mapValues(Set.init).filter { !$0.value.isEmpty }
    }

    private func saveGameAltRepresentations() {
        let stored = gameAltRepresentations.mapValues { $0.sorted() }
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Self.gameAltRepresentationsKey)
        }
    }

    /// Load system-specific preferences
    private func loadSystemPreferences() {
        // Try to load new format first
        if let data = defaults.data(forKey: Self.preferencesKey),
           let preferences = try? JSONDecoder().decode([String: [String: String]].self, from: data) {

            // Convert string keys to SkinSystemID and SkinOrientation
            selectedSkins = preferences.compactMapKeys { key in
                SkinSystemID(rawValue: key)
            }.mapValues { orientationDict in
                orientationDict.compactMapKeys { key in
                    SkinOrientation(rawValue: key)
                }
            }
            return
        }

        // Try to load legacy format and migrate
        if let data = defaults.data(forKey: Self.legacyPreferencesKey),
           let preferences = try? JSONDecoder().decode([String: String].self, from: data) {

            // Convert legacy format to new format (all portrait)
            var newPreferences: [SkinSystemID: [SkinOrientation: String]] = [:]

            for (systemStr, skinId) in preferences {
                newPreferences[SkinSystemID(rawValue: systemStr)] = [.portrait: skinId]
            }

            selectedSkins = newPreferences
            savePreferences()

            // Clear legacy preferences
            defaults.removeObject(forKey: Self.legacyPreferencesKey)
        }
    }

    /// Save preferences to UserDefaults
    private func savePreferences() {
        // Convert SkinSystemID and SkinOrientation keys to strings
        let stringDict = selectedSkins.compactMapKeys { $0.rawValue }
            .mapValues { orientationDict in
                orientationDict.compactMapKeys { $0.rawValue }
            }

        if let data = try? JSONEncoder().encode(stringDict) {
            defaults.set(data, forKey: Self.preferencesKey)
        }
    }

    /// Load game-specific preferences
    private func loadGamePreferences() {
        if let data = defaults.data(forKey: Self.gamePreferencesKey),
           let preferences = try? JSONDecoder().decode([String: [String: String]].self, from: data) {

            // Convert string keys to SkinOrientation
            gameSpecificSkins = preferences.mapValues { orientationDict in
                orientationDict.compactMapKeys { key in
                    SkinOrientation(rawValue: key)
                }
            }
        }
    }

    /// Save game-specific preferences to UserDefaults
    private func saveGamePreferences() {
        // Convert SkinOrientation keys to strings
        let stringDict = gameSpecificSkins.mapValues { orientationDict in
            orientationDict.compactMapKeys { $0.rawValue }
        }

        if let data = try? JSONEncoder().encode(stringDict) {
            defaults.set(data, forKey: Self.gamePreferencesKey)
        }
    }
}

// Helper extension for dictionary transformations
extension Dictionary {
    func compactMapKeys<T>(_ transform: (Key) -> T?) -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            if let transformedKey = transform(key) {
                result[transformedKey] = value
            }
        }
        return result
    }
}
