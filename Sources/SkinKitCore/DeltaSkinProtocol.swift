import CoreGraphics
import Foundation

/// Protocol defining core DeltaSkin functionality
public protocol DeltaSkinProtocol: Identifiable, Equatable {
    /// Unique identifier for the skin
    var identifier: String { get }

    /// Display name of the skin
    var name: String { get }

    /// Type of game this skin is for (e.g. "com.rileytestut.delta.game.ds")
    var gameType: DeltaSkinGameType { get }

    /// URL where the skin file is stored
    var fileURL: URL { get }

    /// Whether this skin supports given traits
    func supports(_ traits: DeltaSkinTraits) -> Bool

    /// Get screen layouts for the current skin and traits
    func screens(for traits: DeltaSkinTraits) -> [DeltaSkinScreen]?

    /// Get the mapping size for layout calculations
    func mappingSize(for traits: DeltaSkinTraits) -> CGSize?

    /// Returns button mappings for the given traits
    func buttons(for traits: DeltaSkinTraits) -> [DeltaSkinButton]?

    /// Returns screen groups for the given traits
    func screenGroups(for traits: DeltaSkinTraits) -> [DeltaSkinScreenGroup]?

    /// Returns whether debug mode is enabled for this skin
    var isDebugEnabled: Bool { get }

    /// The raw JSON representation of the skin
    var jsonRepresentation: [String: Any] { get }

    func representation(for traits: DeltaSkinTraits) -> DeltaSkin.RepresentationInfo?

    /// Optional keyboard overlay configuration embedded in the skin.
    /// Returns `nil` for skins that do not declare a keyboard overlay.
    var keyboardOverlay: KeyboardOverlayConfig? { get }

    /// All named theme variants bundled in this skin. Empty for legacy skins.
    var availableThemes: [DeltaSkin.Theme] { get }

    /// The currently selected theme ID for this skin, or nil for the default appearance.
    var selectedThemeId: String? { get set }

    /// Optional animated background configuration for this skin representation.
    /// Returns `nil` for skins that do not declare a background animation.
    func backgroundAnimation(for traits: DeltaSkinTraits) -> DeltaSkinBackgroundAnimation?

    /// Whether this skin is designed for a physical phone-case controller (GameSir, Soolra, Buppin, etc.).
    /// Determined by the `"caseController"` key in info.json, or by identifier heuristics.
    var isCaseControllerSkin: Bool { get }

    /// Whether the skin has an alternate layout set (Ignited's `altRepresentations`) that its
    /// `toggleAltRepresentations` button switches to. Lookups pick the set from `DeltaSkinTraits.usesAltRepresentations`.
    var hasAltRepresentations: Bool { get }
}

public extension DeltaSkinProtocol {
    /// Default implementation — skins that do not override this return `nil`.
    var keyboardOverlay: KeyboardOverlayConfig? { nil }

    /// Default implementation — skins without themes return an empty array.
    var availableThemes: [DeltaSkin.Theme] { [] }

    /// Default: check identifier against known case-controller patterns.
    var isCaseControllerSkin: Bool {
        DeltaSkinCompanionSkinDetection.isCompanionSkin(identifier)
    }

    /// Default implementation — reads/writes from DeltaSkinThemeSelection using the skin identifier.
    var selectedThemeId: String? {
        get { DeltaSkinThemeSelection.selectedThemeId(for: identifier) }
        set { DeltaSkinThemeSelection.setSelectedThemeId(newValue, for: identifier) }
    }

    /// Default implementation — skins that do not override this return `nil`.
    func backgroundAnimation(for traits: DeltaSkinTraits) -> DeltaSkinBackgroundAnimation? { nil }

    /// Default: no alternate set, so the toggle button does nothing.
    var hasAltRepresentations: Bool { false }

    /// The selected theme, or nil when none is selected or the stored id names a theme this skin no longer has.
    var selectedTheme: DeltaSkin.Theme? {
        guard let themeId = selectedThemeId else { return nil }
        return availableThemes.first { $0.id == themeId }
    }

    /// The selected theme's background artwork for exactly these traits, if it has any.
    func themedAssetRepresentation(for traits: DeltaSkinTraits) -> DeltaSkin.AssetRepresentation? {
        selectedTheme?.assetRepresentation(for: traits)
    }

    /// The selected theme's artwork for the item at `index` of the layout for `traits`, or nil when the theme
    /// (or its entry for that item) has none, in which case the item's own art is drawn. `index` is the item's
    /// position in the layout's `items`, which is also the suffix of the matching `DeltaSkinButton.id`.
    func themedItemAsset(forItemAt index: Int, traits: DeltaSkinTraits) -> DeltaSkin.AssetRepresentation? {
        selectedTheme?.itemAsset(forItemAt: index, traits: traits)
    }
}

public extension Identifiable where  Self: DeltaSkinProtocol  {
    var id: String  { identifier }
}


public extension Equatable where  Self: DeltaSkinProtocol  {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identifier == rhs.identifier
    }
}
