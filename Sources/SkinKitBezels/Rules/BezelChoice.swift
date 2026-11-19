//
//  BezelChoice.swift
//  SkinKitBezels
//
//  The TV in effect for the game being played: the rules applied to the stored choices.
//

import Foundation

/// A choice being tried in the pause menu's switcher. It is read ahead of the stored choices
/// and stored nowhere. `choice` is a TV's id, `ExternalDisplayBezelRules.noBezelID` for Off
/// or `automaticBezelID`. No preview at all is a `nil` `BezelPreview?`: do not fold it with Off.
public struct BezelPreview: Equatable, Sendable {
    public var choice: String
    public var lightsRoom: Bool

    public init(choice: String, lightsRoom: Bool) {
        self.choice = choice
        self.lightsRoom = lightsRoom
    }
}

/// Applies `ExternalDisplayBezelRules` to the catalogue and the stored choices.
public enum BezelChoice {

    /// What the rules decide for a game, and the TV to show (`nil` for the picture alone): the
    /// switcher's preview first, then the game's pin, artwork found for the game, and the
    /// stored choice.
    ///
    /// - Parameters:
    ///   - gameID: the app's key for the running game (the key `pinnedBezels` uses); `nil`
    ///     when it has none.
    ///   - systemSuitsTV: the system was played on a TV or monitor, not on a screen of its own.
    @MainActor
    public static func resolve(gameID: String?, systemID: String?, systemSuitsTV: Bool, preview: BezelPreview?,
                               settings: any BezelSettingsStore = BezelEnvironment.current.settings)
        -> (resolution: ExternalDisplayBezelRules.Resolution, bezel: TVBezel?) {
        let matchesSystem = settings.matchesSystem
        if let preview {
            return TVBezelCatalog.resolve(chosen: preview.choice, matchesSystem: matchesSystem,
                                          systemID: systemID, systemSuitsTV: systemSuitsTV)
        }
        let gameArt = settings.showsGameArtwork ? ExternalDisplayGameArtwork.shared.bezelID(forGame: gameID) : nil
        return TVBezelCatalog.resolve(chosen: settings.chosenBezel, matchesSystem: matchesSystem,
                                      systemID: systemID, systemSuitsTV: systemSuitsTV,
                                      pinned: settings.pinnedBezel(forGame: gameID), gameArt: gameArt)
    }

    /// Whether the picture lights the room: the switcher's preview first, then the setting.
    public static func lightsRoom(preview: BezelPreview?) -> Bool {
        preview?.lightsRoom ?? TVBezelRoomLight.isOn
    }

    /// Looks for artwork made for `game` when the player wants it, once per game and style.
    /// Returns `true` when artwork was found and is now on the device, so the caller should
    /// resolve again.
    ///
    /// Never call it while a preview is showing, or for a game with a pin.
    @MainActor
    public static func fetchGameArtwork(for game: ExternalDisplayGameContext,
                                        settings: any BezelSettingsStore = BezelEnvironment.current.settings) async -> Bool {
        guard settings.showsGameArtwork, settings.pinnedBezel(forGame: game.md5) == nil else { return false }
        let artwork = ExternalDisplayGameArtwork.shared
        let style = settings.bezelProjectStyle
        guard artwork.begin(game: game.md5, style: style) else { return false }
        guard let downloaded = await BezelProjectService.shared.artwork(for: game, style: style) else { return false }
        return artwork.finish(game: game.md5, style: style, bezelID: downloaded.id)
    }
}
