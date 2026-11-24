//
//  BezelStripFocus.swift
//  SkinKitBezels
//
//  The pause menu's TV switcher on Apple TV: what a focus change in the strip means.
//

import Foundation

/// On Apple TV the strip has no cursor of its own: the focused TV is the selected TV.
/// This decides what each focus change does.
///
/// Focus arriving on the list from outside it (the strip opening, or coming back up from
/// Keep and Cancel) is the system picking the nearest TV, not the player choosing one, so
/// it is sent to the selected TV. A move from one TV to the next selects.
public struct BezelStripFocus: Equatable, Sendable {

    public enum Action: Equatable, Sendable {
        case none
        /// Put focus on the item with this id, and select nothing.
        case moveFocus(to: String)
        /// The player moved onto the item with this id.
        case select(String)
    }

    /// Focus was on a TV in the list at the last change.
    public private(set) var isOnList = false

    public init() {}

    /// - Parameters:
    ///   - id: the list item focus is on now; `nil` when it is on anything else, or nowhere.
    ///   - selection: the selected item's id.
    public mutating func focusChanged(to id: String?, selection: String) -> Action {
        guard let id else {
            isOnList = false
            return .none
        }
        let arrived = !isOnList
        isOnList = true
        if id == selection { return .none }
        // Sent back once only: if focus cannot go there, the next move selects as usual.
        return arrived ? .moveFocus(to: selection) : .select(id)
    }
}
