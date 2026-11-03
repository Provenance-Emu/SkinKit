import Foundation

/// Which tagged catalog entries the stores show: generated sample skins (`sample`) and adult skins
/// (`mature`). Both are hidden by default.
///
/// Each app wires its own settings into ``current`` at launch and whenever they change: a
/// developer setting "Show test skins" and a user setting "Show mature skins". Every store path
/// reads it at filter time (`SkinStorePolicy.section(for:)`, SkinKitUI's catalog queries), so the
/// static `SkinStorePolicy.iFly` / `.iCube` presets follow the settings without being rebuilt. A
/// policy can pin its own value instead (`SkinStorePolicy.visibility`), which tests do.
///
/// Filter before grouping into families, so a hidden entry never shows up inside a family card.
public struct SkinContentVisibility: Sendable, Hashable {
    /// Show entries tagged `sample` (developer setting "Show test skins").
    public var showTestSkins: Bool
    /// Show entries tagged `mature` (user setting "Show mature skins").
    public var showMatureSkins: Bool

    public init(showTestSkins: Bool = false, showMatureSkins: Bool = false) {
        self.showTestSkins = showTestSkins
        self.showMatureSkins = showMatureSkins
    }

    /// Both hidden: what a store shows when the app has wired nothing.
    public static let `default` = SkinContentVisibility()

    /// Whether a store shows `entry`.
    public func allows(_ entry: SkinCatalogEntry) -> Bool {
        if entry.isTestSkin, !showTestSkins { return false }
        if entry.isMature, !showMatureSkins { return false }
        return true
    }

    /// `entries` minus the ones this visibility hides, order kept.
    public func filter(_ entries: [SkinCatalogEntry]) -> [SkinCatalogEntry] {
        entries.filter(allows)
    }

    // MARK: - App-wide setting

    private static let lock = NSLock()
    private static var _current = SkinContentVisibility.default

    /// The app's current settings. Set it from the app's settings at launch and on change.
    public static var current: SkinContentVisibility {
        get { lock.withLock { _current } }
        set { lock.withLock { _current = newValue } }
    }
}
