//
//  BezelStripFocusTests.swift
//  SkinKitBezels
//
//  The TV switcher on Apple TV: which focus changes select a TV.
//

import Testing
@testable import SkinKitBezels

@Suite("BezelStripFocus")
struct BezelStripFocusTests {

    @Test("Focus arriving on the selected TV changes nothing")
    func opensOnSelection() {
        var focus = BezelStripFocus()
        #expect(focus.focusChanged(to: "auto", selection: "auto") == .none)
        #expect(focus.isOnList)
    }

    @Test("Focus arriving on another TV is sent to the selected one, and selects nothing")
    func opensElsewhere() {
        var focus = BezelStripFocus()
        #expect(focus.focusChanged(to: "", selection: "auto") == .moveFocus(to: "auto"))
        #expect(focus.focusChanged(to: "auto", selection: "auto") == .none)
    }

    @Test("Moving from one TV to the next selects it")
    func movingSelects() {
        var focus = BezelStripFocus()
        _ = focus.focusChanged(to: "auto", selection: "auto")
        #expect(focus.focusChanged(to: "studio-monitor", selection: "auto") == .select("studio-monitor"))
        #expect(focus.focusChanged(to: "dorm-tv", selection: "studio-monitor") == .select("dorm-tv"))
    }

    @Test("Coming back up from the buttons returns to the selected TV")
    func returnsFromButtons() {
        var focus = BezelStripFocus()
        _ = focus.focusChanged(to: "studio-monitor", selection: "studio-monitor")
        #expect(focus.focusChanged(to: nil, selection: "studio-monitor") == .none)
        #expect(!focus.isOnList)
        #expect(focus.focusChanged(to: "dorm-tv", selection: "studio-monitor") == .moveFocus(to: "studio-monitor"))
        #expect(focus.focusChanged(to: "studio-monitor", selection: "studio-monitor") == .none)
        #expect(focus.focusChanged(to: "dorm-tv", selection: "studio-monitor") == .select("dorm-tv"))
    }

    @Test("Focus passing through nowhere on its way to the selected TV selects nothing")
    func redirectThroughNowhere() {
        var focus = BezelStripFocus()
        #expect(focus.focusChanged(to: "", selection: "auto") == .moveFocus(to: "auto"))
        #expect(focus.focusChanged(to: nil, selection: "auto") == .none)
        #expect(focus.focusChanged(to: "auto", selection: "auto") == .none)
    }

    @Test("A refused move does not trap focus: the next move selects")
    func refusedMove() {
        var focus = BezelStripFocus()
        #expect(focus.focusChanged(to: "", selection: "auto") == .moveFocus(to: "auto"))
        #expect(focus.focusChanged(to: "living-room-tv", selection: "auto") == .select("living-room-tv"))
    }
}
