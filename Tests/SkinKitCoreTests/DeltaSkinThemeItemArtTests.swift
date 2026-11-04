import CoreGraphics
import Foundation
import Testing
@testable import SkinKitCore

/// Themes that carry per-item artwork: `Theme.assets[device][displayType][orientation].items`, keyed by item index.
///
/// `ThemedItemArt-Test` has a base layout whose item 0 ("a") has its own art and items 1 ("b") and 2 ("start") have
/// none, and three themes: "neon" re-skins the background and items 0 and 1, "ocean" the background and item 0,
/// "plain" only the background (a theme from before `items` existed). Only portrait has theme artwork.
@Suite("Theme item artwork", .serialized)
struct DeltaSkinThemeItemArtTests {

    private static let portrait = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .portrait)
    private static let landscape = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .landscape)

    private static func skin() throws -> DeltaSkin {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/ThemedItemArt-Test", withExtension: "deltaskin"))
        var skin = try DeltaSkin(fileURL: url)
        skin.selectedThemeId = nil   // a choice left in UserDefaults by an earlier run would change the starting art
        return skin
    }

    private static func names(_ asset: DeltaSkin.AssetRepresentation?) -> [String]? {
        asset?.candidates()
    }

    // MARK: - Decoding

    @Test("The items map decodes per layout, keyed by item index")
    func decodesItems() throws {
        let skin = try Self.skin()
        let neon = try #require(skin.availableThemes.first { $0.id == "neon" })
        let layout = try #require(neon.assetRepresentation(for: Self.portrait))
        #expect(layout.resizable == "neon.png")
        #expect(layout.items?.keys.sorted() == ["0", "1"])
        #expect(layout.items?["0"]?.resizable == "neon-btn-a.png")
        #expect(layout.items?["1"]?.resizable == "neon-btn-b.png")
    }

    @Test("A theme without items, and a layout the theme does not cover, have no item art")
    func absentItems() throws {
        let skin = try Self.skin()
        let plain = try #require(skin.availableThemes.first { $0.id == "plain" })
        #expect(plain.assetRepresentation(for: Self.portrait)?.resizable == "neon.png")
        #expect(plain.assetRepresentation(for: Self.portrait)?.items == nil)
        #expect(plain.itemAsset(forItemAt: 0, traits: Self.portrait) == nil)

        let neon = try #require(skin.availableThemes.first { $0.id == "neon" })
        #expect(neon.assetRepresentation(for: Self.landscape) == nil)
        #expect(neon.itemAsset(forItemAt: 0, traits: Self.landscape) == nil)
    }

    @Test("A theme can leave items out: ocean covers item 0 only")
    func partialItems() throws {
        let skin = try Self.skin()
        let ocean = try #require(skin.availableThemes.first { $0.id == "ocean" })
        #expect(Self.names(ocean.itemAsset(forItemAt: 0, traits: Self.portrait)) == ["ocean-btn-a.png"])
        #expect(ocean.itemAsset(forItemAt: 1, traits: Self.portrait) == nil)
        #expect(ocean.itemAsset(forItemAt: 2, traits: Self.portrait) == nil)
        #expect(ocean.itemAsset(forItemAt: 99, traits: Self.portrait) == nil)
        #expect(ocean.itemAsset(forItemAt: -1, traits: Self.portrait) == nil)
    }

    @Test("A malformed items map is dropped and the theme's background still applies")
    func malformedItemsAreDropped() throws {
        let json = #"{"resizable": "bg.png", "items": ["not", "a", "map"]}"#
        let asset = try JSONDecoder().decode(DeltaSkin.AssetRepresentation.self, from: Data(json.utf8))
        #expect(asset.resizable == "bg.png")
        #expect(asset.items == nil)

        let blank = #"{"resizable": "bg.png", "items": {"0": {"resizable": "  "}}}"#
        let blanked = try JSONDecoder().decode(DeltaSkin.AssetRepresentation.self, from: Data(blank.utf8))
        #expect(blanked.items?["0"]?.candidates() == [])
    }

    @Test("Old info.json without items decodes and re-encodes with no items key")
    func additive() throws {
        let json = #"{"resizable": "bg.png", "large": "bg@3x.png"}"#
        let asset = try JSONDecoder().decode(DeltaSkin.AssetRepresentation.self, from: Data(json.utf8))
        #expect(asset.items == nil)
        #expect(asset.candidates() == ["bg.png", "bg@3x.png"])
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(asset)) as? [String: Any]
        #expect(encoded?["items"] == nil)

        let withItems = DeltaSkin.AssetRepresentation(
            resizable: "bg.png", small: nil, medium: nil, large: nil,
            items: ["2": DeltaSkin.AssetRepresentation(resizable: "x.png", small: nil, medium: nil, large: nil)])
        let back = try JSONDecoder().decode(DeltaSkin.AssetRepresentation.self, from: JSONEncoder().encode(withItems))
        #expect(back.items?["2"]?.resizable == "x.png")
    }

    @Test("The base layout is untouched by themes: items keep their own art and the skin still lists three themes")
    func baseLayoutUnchanged() throws {
        let skin = try Self.skin()
        #expect(skin.availableThemes.map(\.id) == ["neon", "ocean", "plain"])
        #expect(skin.representation(for: Self.portrait)?.assets.resizable == "base.png")
        #expect(skin.representation(for: Self.portrait)?.assets.items == nil)
        #expect(skin.buttons(for: Self.portrait)?.count == 3)
    }

    // MARK: - Switching the selected theme

    @Test("Switching theme changes both the background and the item art lookups")
    func switchingThemeChangesBackgroundAndItems() throws {
        var skin = try Self.skin()
        defer { skin.selectedThemeId = nil }

        // No theme: nothing themed, the skin's own art applies.
        #expect(skin.selectedTheme == nil)
        #expect(skin.themedAssetRepresentation(for: Self.portrait) == nil)
        #expect(skin.themedItemAsset(forItemAt: 0, traits: Self.portrait) == nil)

        skin.selectedThemeId = "neon"
        #expect(Self.names(skin.themedAssetRepresentation(for: Self.portrait)) == ["neon.png"])
        #expect(Self.names(skin.themedItemAsset(forItemAt: 0, traits: Self.portrait)) == ["neon-btn-a.png"])
        #expect(Self.names(skin.themedItemAsset(forItemAt: 1, traits: Self.portrait)) == ["neon-btn-b.png"])
        #expect(skin.themedItemAsset(forItemAt: 2, traits: Self.portrait) == nil)

        skin.selectedThemeId = "ocean"
        #expect(Self.names(skin.themedAssetRepresentation(for: Self.portrait)) == ["ocean.png"])
        #expect(Self.names(skin.themedItemAsset(forItemAt: 0, traits: Self.portrait)) == ["ocean-btn-a.png"])
        #expect(skin.themedItemAsset(forItemAt: 1, traits: Self.portrait) == nil)

        // A background-only theme restyles the background and leaves every item on its own art.
        skin.selectedThemeId = "plain"
        #expect(Self.names(skin.themedAssetRepresentation(for: Self.portrait)) == ["neon.png"])
        #expect(skin.themedItemAsset(forItemAt: 0, traits: Self.portrait) == nil)

        skin.selectedThemeId = nil
        #expect(skin.themedAssetRepresentation(for: Self.portrait) == nil)
        #expect(skin.themedItemAsset(forItemAt: 0, traits: Self.portrait) == nil)
    }

    @Test("Layouts the theme does not cover, and unknown theme ids, fall back to the skin's own art")
    func fallbacks() throws {
        var skin = try Self.skin()
        defer { skin.selectedThemeId = nil }

        skin.selectedThemeId = "neon"
        #expect(skin.themedAssetRepresentation(for: Self.landscape) == nil)
        #expect(skin.themedItemAsset(forItemAt: 0, traits: Self.landscape) == nil)

        skin.selectedThemeId = "removed-in-an-update"
        #expect(skin.selectedTheme == nil)
        #expect(skin.themedAssetRepresentation(for: Self.portrait) == nil)
        #expect(skin.themedItemAsset(forItemAt: 0, traits: Self.portrait) == nil)
    }

    @Test("The item index is the suffix of the decoded button id")
    func indexMatchesButtonOrder() throws {
        let skin = try Self.skin()
        let buttons = try #require(skin.buttons(for: Self.portrait))
        for (index, button) in buttons.enumerated() {
            #expect(button.id.hasSuffix("-button-\(index)"))
        }
    }
}
