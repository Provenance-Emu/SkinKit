import Foundation

// Two small seams where Provenance's skin model reached into app code. Both keep the
// behavior the model had in Provenance.

/// Per-skin theme selection, persisted in `UserDefaults.standard`.
///
/// Same storage key as Provenance's `DeltaSkinPreferences` used (`com.provenance.deltaskin.theme.<id>`),
/// so a theme the user already picked keeps applying after Provenance moves to SkinKitCore.
public enum DeltaSkinThemeSelection {
    /// Key prefix; the skin identifier is appended.
    public static let keyPrefix = "com.provenance.deltaskin.theme."

    /// The selected theme ID for a skin, or `nil` when none is selected (default appearance).
    public static func selectedThemeId(for skinIdentifier: String) -> String? {
        UserDefaults.standard.string(forKey: keyPrefix + skinIdentifier)
    }

    /// Persist the selected theme ID for a skin. Pass `nil` to revert to the default appearance.
    public static func setSelectedThemeId(_ id: String?, for skinIdentifier: String) {
        let key = keyPrefix + skinIdentifier
        if let id {
            UserDefaults.standard.set(id, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

/// Identifier-based check for skins that ship as companions to a physical phone-case controller.
///
/// Provenance decides this with `CaseControllerDetector`, which knows the physical case layouts
/// and depends on GameController and app settings. SkinKitCore has none of that, so the check is
/// injected: the host app sets `matcher` once at launch. The default matches nothing, so
/// `DeltaSkin.isCaseControllerSkin` then only reflects the `"caseController"` key in `info.json`.
public enum DeltaSkinCompanionSkinDetection {
    private static let lock = NSLock()
    private static var _matcher: @Sendable (String) -> Bool = { _ in false }

    /// Returns `true` when a skin identifier is a known case-companion skin.
    public static var matcher: @Sendable (String) -> Bool {
        get { lock.withLock { _matcher } }
        set { lock.withLock { _matcher = newValue } }
    }

    static func isCompanionSkin(_ skinIdentifier: String) -> Bool {
        matcher(skinIdentifier)
    }
}
