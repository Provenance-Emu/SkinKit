//
//  DeltaSkinGameScreenSelectionTests.swift
//  SkinKitCoreTests
//
//  `DeltaSkinScreen.gameScreen(in:mappingSize:)` picks the screen that shows the game
//  out of a skin's screens array, skipping effect backdrops and effect strips.
//

import CoreGraphics
import Testing
@testable import SkinKitCore

@Suite("DeltaSkinScreen game screen selection")
struct DeltaSkinGameScreenSelectionTests {

    private static func screen(_ id: String, _ frame: CGRect) -> DeltaSkinScreen {
        DeltaSkinScreen(id: id,
                        inputFrame: CGRect(x: 0, y: 0, width: 256, height: 240),
                        outputFrame: frame,
                        placement: .controller,
                        filters: nil)
    }

    /// R3BEL [CRT PORTABLE] [REFLECTIVE BEZEL] NES, iPhone edge-to-edge portrait: the game
    /// screen plus four reflection strips, two of them exactly as wide as the skin.
    @Test("Reflection strips as wide as the skin are not the game screen")
    func skipsFullWidthStrips() {
        let mappingSize = CGSize(width: 1290, height: 2796)
        let screens = [
            Self.screen("game", CGRect(x: 34, y: 260, width: 1222, height: 926)),
            Self.screen("right", CGRect(x: 1247, y: 243, width: 90, height: 961)),
            Self.screen("left", CGRect(x: -48, y: 243, width: 90, height: 961)),
            Self.screen("top", CGRect(x: 0, y: 207, width: 1290, height: 60)),
            Self.screen("bottom", CGRect(x: 0, y: 1177, width: 1290, height: 80)),
        ]
        #expect(DeltaSkinScreen.gameScreen(in: screens, mappingSize: mappingSize)?.id == "game")
        #expect(!screens[3].isLargeEnoughForGameScreen(mappingSize: mappingSize))
        #expect(!screens[4].isLargeEnoughForGameScreen(mappingSize: mappingSize))
    }

    @Test("A larger blurred backdrop loses to the game screen")
    func prefersGameOverBackdrop() {
        let mappingSize = CGSize(width: 1290, height: 2796)
        let screens = [
            Self.screen("backdrop", CGRect(x: 0, y: 0, width: 1290, height: 2796)),
            Self.screen("game", CGRect(x: 34, y: 260, width: 1222, height: 926)),
        ]
        #expect(DeltaSkinScreen.gameScreen(in: screens, mappingSize: mappingSize)?.id == "game")
    }

    @Test("Normalised frames use the normalised minimum size")
    func normalisedFrames() {
        let mappingSize = CGSize(width: 1290, height: 2796)
        let screens = [
            Self.screen("backdrop", CGRect(x: 0, y: 0, width: 1, height: 1)),
            Self.screen("game", CGRect(x: 0.03, y: 0.09, width: 0.95, height: 0.33)),
            Self.screen("strip", CGRect(x: 0, y: 0.07, width: 1, height: 0.02)),
        ]
        #expect(DeltaSkinScreen.gameScreen(in: screens, mappingSize: mappingSize)?.id == "game")
    }

    @Test("No screen large enough gives nil")
    func noneLargeEnough() {
        let screens = [Self.screen("strip", CGRect(x: 0, y: 207, width: 1290, height: 60))]
        #expect(DeltaSkinScreen.gameScreen(in: screens, mappingSize: CGSize(width: 1290, height: 2796)) == nil)
    }
}
