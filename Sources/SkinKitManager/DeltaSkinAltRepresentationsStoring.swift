import Foundation

/// Where the per-game alternate-layout choice (Ignited's `altRepresentations`) persists.
///
/// The choice has the same scope as the game's skin pick: one per game, kept per skin. ``DeltaSkinPreferences``
/// is the store (UserDefaults); ``DeltaSkinSelectionManager`` wraps it and posts
/// ``DeltaSkinSelectionManager/altRepresentationsChangedNotification``. A host that keeps its own per-game
/// settings can conform instead and build `DeltaSkinTraits.usesAltRepresentations` from it.
public protocol DeltaSkinAltRepresentationsStoring: AnyObject {
    /// Whether the alternate set is on for this skin in this game, checking each game key in order.
    func usesAltRepresentations(skinIdentifier: String, gameIds: [String]) -> Bool

    /// Persists the choice under `gameId`. Turning it off also clears it under `otherGameKeys`.
    @MainActor
    func setUsesAltRepresentations(_ usesAlt: Bool, skinIdentifier: String, gameId: String, otherGameKeys: [String])
}
