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
@frozen public enum BezelChoice {

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
        if let preview {
            // The TV being tried is the TV shown: the player's own bezel for the system does
            // not stand in for it, or stepping through the strip would change nothing.
            return TVBezelCatalog.resolve(chosen: preview.choice, matchesSystem: false,
                                          systemID: systemID, systemSuitsTV: systemSuitsTV)
        }
        return TVBezelCatalog.resolve(chosen: settings.chosenBezel, matchesSystem: settings.matchesSystem,
                                      systemID: systemID, systemSuitsTV: systemSuitsTV,
                                      pinned: settings.pinnedBezel(forGame: gameID),
                                      gameArt: gameArt(forGame: gameID, settings: settings))
    }

    /// Artwork found for `gameID` this session, when the player wants game artwork shown.
    @MainActor
    private static func gameArt(forGame gameID: String?, settings: any BezelSettingsStore) -> String? {
        settings.showsGameArtwork ? ExternalDisplayGameArtwork.shared.bezelID(forGame: gameID) : nil
    }

    /// The TV the game would show with `choice` saved for every game and no pin of its own;
    /// `nil` for none. What `BezelSwitcherModel.pinForEveryGame` asks.
    @MainActor
    public static func shownBezelID(ifChosen choice: String, gameID: String?, systemID: String?, systemSuitsTV: Bool,
                                    settings: any BezelSettingsStore = BezelEnvironment.current.settings) -> String? {
        TVBezelCatalog.resolve(chosen: choice, matchesSystem: settings.matchesSystem, systemID: systemID,
                               systemSuitsTV: systemSuitsTV,
                               gameArt: gameArt(forGame: gameID, settings: settings)).resolution.bezelID
    }

    /// Saves `choice` as the TV for every game, from a list shown over a running game, so
    /// that the game shows it: the game's pin goes, and where another rule would still hide
    /// the choice for this game it is pinned to it (`BezelSwitcherModel.pinForEveryGame`).
    /// With no game running it only saves the choice.
    @MainActor
    public static func chooseForEveryGame(_ choice: String, playing gameID: String?, systemID: String?,
                                          systemSuitsTV: Bool,
                                          settings: any BezelSettingsStore = BezelEnvironment.current.settings) {
        settings.chosenBezel = choice
        guard let gameID else { return }
        let pin = BezelSwitcherModel.pinForEveryGame(choice: choice, gameHasPin: settings.pinnedBezel(forGame: gameID) != nil) {
            shownBezelID(ifChosen: $0, gameID: gameID, systemID: systemID, systemSuitsTV: systemSuitsTV, settings: settings)
        }
        apply(pin, toGame: gameID, settings: settings)
    }

    /// Writes a pin change for `gameID`.
    public static func apply(_ pin: BezelSwitcherModel.PinChange, toGame gameID: String,
                             settings: any BezelSettingsStore = BezelEnvironment.current.settings) {
        switch pin {
        case .set(let id): settings.pinnedBezels[gameID] = id
        case .remove: settings.pinnedBezels[gameID] = nil
        case .unchanged: break
        }
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
        guard settings.showsGameArtwork, settings.pinnedBezel(forGame: game.gameID) == nil else { return false }
        let artwork = ExternalDisplayGameArtwork.shared
        let style = settings.bezelProjectStyle
        guard artwork.begin(game: game.gameID, style: style) else { return false }
        guard let downloaded = await BezelProjectService.shared.artwork(for: game, style: style) else { return false }
        return artwork.finish(game: game.gameID, style: style, bezelID: downloaded.id)
    }
}
