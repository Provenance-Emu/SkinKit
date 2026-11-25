// SkinKitBezelsUI: the views of the TV bezel feature, for iOS and tvOS.
//
//   BezelSwitcherStrip / BezelSwitcherHost  the pause menu's strip: step through TVs over the paused game
//   TVBezelPickerView                       the full list, with import and The Bezel Project
//   BezelProjectBrowserView                 The Bezel Project's systems and artwork
//   TVBezelArtworkView / TVBezelStage       a TV as a plain image around the picture, for an app that
//                                           does not draw it with a shader
//
// The app supplies what only it knows through `BezelSwitcherSession` (the running game and whether a TV
// can show now), a publisher of `BezelNavigationCommand`s for its controller input, and
// `BezelEnvironment.current` (settings, folders, system names).

@_exported import SkinKitBezels

/// A step of controller input, as the bezel views understand it. An app maps its own menu
/// input onto these; tvOS moves focus instead and needs none.
@frozen public enum BezelNavigationCommand: Equatable, Sendable {
    case left, right, up, down
    /// Jump to the group of TVs before or after the selection's (the shoulder buttons).
    case previousGroup, nextGroup
    case activate, back
    case toggleRoomLight
    case toggleThisGameOnly
}
