//
//  BezelSwitcherModelTests.swift
//  SkinKitBezels
//
//  The pause menu's TV switcher: what it lists, how it steps and what Keep saves.
//

import Testing
@testable import SkinKitBezels

@Suite("BezelSwitcherModel")
struct BezelSwitcherModelTests {

    private func model(current: String = "auto", pin: Bool = false) -> BezelSwitcherModel {
        BezelSwitcherModel(builtIn: ["living-room-tv", "studio-monitor"], shaderPresets: ["uborder"],
                           yours: [], current: current, gameHasPin: pin, lightsRoom: true)
    }

    @Test("Items run Off, Automatic, TVs, More, and it opens on the current choice")
    func order() {
        let model = model(current: "studio-monitor")
        #expect(model.items.map(\.id) == ["", "auto", "living-room-tv", "studio-monitor", "uborder", "more"])
        #expect(model.selection.id == "studio-monitor")
        #expect(!model.thisGameOnly)
        #expect(self.model(current: "studio-monitor", pin: true).thisGameOnly)
    }

    @Test("A current choice that is gone opens on Automatic")
    func missingCurrent() {
        #expect(model(current: "deleted-import").selection.id == "auto")
    }

    @Test("Stepping clamps at both ends")
    func clamps() {
        var model = model(current: "")
        model.step(-1)
        #expect(model.selection.id == "")
        model.step(99)
        #expect(model.selection.id == "more")
    }

    @Test("Group jumps skip empty groups")
    func groups() {
        var model = model(current: "")
        model.jumpGroup(1)
        #expect(model.selection.id == "living-room-tv")
        model.jumpGroup(1)
        #expect(model.selection.id == "uborder")
        model.jumpGroup(1)
        #expect(model.selection.id == "more")   // "yours" is empty
        model.jumpGroup(1)
        #expect(model.selection.id == "more")
        model.jumpGroup(-1)
        #expect(model.selection.id == "uborder")
    }

    @Test("Selecting an unknown id changes nothing")
    func selectUnknown() {
        var model = model(current: "studio-monitor")
        model.select(id: "no-such-tv")
        #expect(model.selection.id == "studio-monitor")
    }

    @Test("Keep for every game saves the choice and drops this game's pin")
    func keepEveryGame() {
        var model = model(current: "auto", pin: true)
        model.thisGameOnly = false
        model.select(id: "studio-monitor")
        #expect(model.commit(gameHasPin: true) == .init(chosen: "studio-monitor", pin: .remove, lightsRoom: true))
        #expect(model.commit(gameHasPin: false) == .init(chosen: "studio-monitor", pin: .unchanged, lightsRoom: true))
    }

    @Test("Keep for this game pins it and leaves the saved choice alone")
    func keepThisGame() {
        var model = model()
        model.thisGameOnly = true
        model.lightsRoom = false
        model.select(id: "")
        #expect(model.commit(gameHasPin: false) == .init(chosen: nil, pin: .set(""), lightsRoom: false))
        model.select(id: "auto")
        #expect(model.commit(gameHasPin: true) == .init(chosen: nil, pin: .remove, lightsRoom: false))
    }

    @Test("Keep on More saves nothing")
    func keepOnMore() {
        var model = model()
        model.select(id: "more")
        #expect(model.commit(gameHasPin: false) == nil)
    }

    @Test("Kept for every game, a TV another rule would hide is pinned to the running game")
    func pinsWhatWouldBeHidden() {
        var model = model(current: "auto")
        model.select(id: "studio-monitor")
        // Nothing hides it: saved, and an old pin dropped.
        #expect(model.commit(gameHasPin: false) { $0 } == .init(chosen: "studio-monitor", pin: .unchanged, lightsRoom: true))
        #expect(model.commit(gameHasPin: true) { $0 } == .init(chosen: "studio-monitor", pin: .remove, lightsRoom: true))
        // Game artwork or the player's own system bezel would show instead: pinned as well.
        #expect(model.commit(gameHasPin: false) { _ in "file:game-art.png" }
            == .init(chosen: "studio-monitor", pin: .set("studio-monitor"), lightsRoom: true))
        #expect(model.commit(gameHasPin: true) { _ in "file:game-art.png" }
            == .init(chosen: "studio-monitor", pin: .set("studio-monitor"), lightsRoom: true))
        // Off while artwork would show is pinned; Off that shows nothing is not.
        model.select(id: "")
        #expect(model.commit(gameHasPin: false) { _ in "file:game-art.png" }?.pin == .set(""))
        #expect(model.commit(gameHasPin: false) { _ in nil }?.pin == .unchanged)
        // Automatic is never pinned, whatever it shows.
        model.select(id: "auto")
        #expect(model.commit(gameHasPin: true) { _ in "file:game-art.png" }?.pin == .remove)
        // This game only is unchanged by what would show.
        model.select(id: "studio-monitor")
        model.thisGameOnly = true
        #expect(model.commit(gameHasPin: false) { _ in "file:game-art.png" }
            == .init(chosen: nil, pin: .set("studio-monitor"), lightsRoom: true))
    }
}
