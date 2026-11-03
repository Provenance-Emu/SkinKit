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

    /// Posted after a skin's selected theme changes (not when it is set to the value it already has), from
    /// whichever thread made the change. The object is `nil`; `userInfo[skinIdentifierUserInfoKey]` is the
    /// skin's identifier (a `String`).
    ///
    /// Views that already drew the skin observe this to redraw with the new theme's artwork; a stored
    /// choice alone is only read the next time the artwork loads.
    public static let didChangeNotification = Notification.Name("com.provenance.deltaskin.themeSelectionDidChange")

    /// `userInfo` key of ``didChangeNotification`` holding the skin identifier.
    public static let skinIdentifierUserInfoKey = "skinIdentifier"

    /// Persist the selected theme ID for a skin. Pass `nil` to revert to the default appearance.
    public static func setSelectedThemeId(_ id: String?, for skinIdentifier: String) {
        let key = keyPrefix + skinIdentifier
        let previous = UserDefaults.standard.string(forKey: key)
        if let id {
            UserDefaults.standard.set(id, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        guard previous != id else { return }
        NotificationCenter.default.post(
            name: didChangeNotification,
            object: nil,
            userInfo: [skinIdentifierUserInfoKey: skinIdentifier]
        )
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
