import CoreGraphics
import Foundation
import SkinKitCore
import SkinKitManager
import Testing
@testable import SkinKitUI

// No UIKit here: these run in `swift test` on the macOS host.

@Suite("Skin edit geometry")
struct DeltaSkinEditGeometryTests {
    /// A 100x200 mapping area drawn at 2x in a 200x400 container.
    let geometry = DeltaSkinEditGeometry(mappingSize: CGSize(width: 100, height: 200), containerSize: CGSize(width: 200, height: 400))
    let frame = CGRect(x: 40, y: 80, width: 20, height: 20)

    @Test("Screen deltas become mapping deltas, and mapping rects become screen rects")
    func conversion() {
        #expect(geometry.mappingDelta(forScreenDelta: CGSize(width: 20, height: -10)) == CGPoint(x: 10, y: -5))
        #expect(geometry.screenRect(forMappingRect: frame) == CGRect(x: 80, y: 160, width: 40, height: 40))
        let empty = DeltaSkinEditGeometry(mappingSize: .zero, containerSize: CGSize(width: 10, height: 10))
        #expect(empty.mappingDelta(forScreenDelta: CGSize(width: 5, height: 5)) == .zero)
        #expect(empty.screenRect(forMappingRect: frame) == .zero)
    }

    @Test("A drag adds to the existing move")
    func dragAccumulates() {
        let start = DeltaSkinButtonEdit(dx: 5, dy: 0)
        let moved = geometry.dragged(start, by: CGSize(width: 20, height: 20), baseFrame: frame)
        #expect(moved.dx == 15)
        #expect(moved.dy == 10)
        #expect(moved.scale == 1)
    }

    @Test("A drag stops at the edges of the mapping area")
    func dragClamps() {
        let right = geometry.dragged(.identity, by: CGSize(width: 10_000, height: 0), baseFrame: frame)
        #expect(right.applying(to: frame).maxX == 100)
        let top = geometry.dragged(.identity, by: CGSize(width: 0, height: -10_000), baseFrame: frame)
        #expect(top.applying(to: frame).minY == 0)
    }

    @Test("A pinch multiplies the size the pinch started at")
    func pinchMultiplies() {
        let grown = geometry.pinched(DeltaSkinButtonEdit(scale: 1.5), by: 1.2, baseFrame: frame)
        #expect(abs(grown.scale - 1.8) < 1e-9)
        let shrunk = geometry.pinched(.identity, by: 0.8, baseFrame: frame)
        #expect(abs(shrunk.scale - 0.8) < 1e-9)
    }

    @Test("A pinch is clamped to 0.5x...2x")
    func pinchClamps() {
        #expect(geometry.pinched(.identity, by: 10, baseFrame: frame).scale == 2.0)
        #expect(geometry.pinched(.identity, by: 0.01, baseFrame: frame).scale == 0.5)
        #expect(geometry.pinched(DeltaSkinButtonEdit(scale: 1.9), by: 1.5, baseFrame: frame).scale == 2.0)
    }

    @Test("A bad pinch value changes nothing")
    func pinchRejectsGarbage() {
        let start = DeltaSkinButtonEdit(dx: 3, dy: 4, scale: 1.25)
        for bad in [Double.nan, .infinity, 0, -1] {
            #expect(geometry.pinched(start, by: bad, baseFrame: frame) == start)
        }
    }

    @Test("Growing near an edge slides the button back inside, using the scaled frame")
    func growthKeepsButtonInside() {
        let corner = CGRect(x: 80, y: 180, width: 20, height: 20) // touches the bottom-right corner
        let grown = geometry.pinched(.identity, by: 2, baseFrame: corner)
        let result = grown.applying(to: corner)
        #expect(result.width == 40)
        #expect(result.maxX == 100)
        #expect(result.maxY == 200)
        #expect(result.minX >= 0 && result.minY >= 0)
    }

    @Test("A frame larger than the area is centered on it")
    func oversizedIsCentered() {
        let wide = CGRect(x: 0, y: 90, width: 80, height: 20)
        let grown = geometry.pinched(.identity, by: 2, baseFrame: wide) // 160 wide in a 100 area
        #expect(grown.applying(to: wide).midX == 50)
    }
}

@MainActor
@Suite("Skin edit session")
struct DeltaSkinEditSessionTests {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("EditSessionTests-\(UUID().uuidString)", isDirectory: true)
    let skin = "com.example.edit-session"
    let portrait = DeltaSkinTraits(device: .iphone, displayType: .edgeToEdge, orientation: .portrait).layoutEditKey
    let landscape = DeltaSkinTraits(device: .iphone, displayType: .edgeToEdge, orientation: .landscape).layoutEditKey
    let geometry = DeltaSkinEditGeometry(mappingSize: CGSize(width: 100, height: 200), containerSize: CGSize(width: 100, height: 200))
    let frame = CGRect(x: 40, y: 80, width: 20, height: 20)

    private func makeSession(_ store: DeltaSkinLayoutEdits, trait: String) -> DeltaSkinEditSession {
        DeltaSkinEditSession(store: store, skinIdentifier: skin, traitKey: trait)
    }

    @Test("Drag and pinch persist to the store, and survive a new store on the same folder")
    func persists() {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeltaSkinLayoutEdits(editsDirectory: directory)
        let session = makeSession(store, trait: portrait)
        session.commitDrag("a", translation: CGSize(width: 10, height: -5), baseFrame: frame, geometry: geometry)
        session.commitPinch("a", magnification: 1.5, baseFrame: frame, geometry: geometry)

        let expected = store.edit(forButton: "a", skinIdentifier: skin, traitKey: portrait)
        #expect(expected.dx == 10 && expected.dy == -5)
        #expect(abs(expected.scale - 1.5) < 1e-9)
        #expect(session.edit(for: "a") == expected)
        #expect(session.lastSaveError == nil)

        let reloaded = DeltaSkinLayoutEdits(editsDirectory: directory)
        #expect(reloaded.edit(forButton: "a", skinIdentifier: skin, traitKey: portrait) == expected)
        #expect(makeSession(reloaded, trait: portrait).edit(for: "a") == expected)
    }

    @Test("An edit in portrait leaves landscape unchanged")
    func perOrientation() {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeltaSkinLayoutEdits(editsDirectory: directory)
        makeSession(store, trait: portrait)
            .commitDrag("a", translation: CGSize(width: 10, height: 0), baseFrame: frame, geometry: geometry)
        let land = makeSession(store, trait: landscape)
        #expect(land.edit(for: "a") == .identity)
        #expect(!land.hasEdits)
        #expect(store.hasEdits(skinIdentifier: skin, traitKey: portrait))
        #expect(!store.hasEdits(skinIdentifier: skin, traitKey: landscape))
    }

    @Test("Dragging a button back to where it started removes its edit")
    func returningToStartStoresNothing() {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeltaSkinLayoutEdits(editsDirectory: directory)
        let session = makeSession(store, trait: portrait)
        session.commitDrag("a", translation: CGSize(width: 10, height: 0), baseFrame: frame, geometry: geometry)
        session.commitDrag("a", translation: CGSize(width: -10, height: 0), baseFrame: frame, geometry: geometry)
        #expect(!session.hasEdits)
        #expect(!store.hasEdits(skinIdentifier: skin))
    }

    @Test("Reset this button clears only the selected button")
    func resetSelected() {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeltaSkinLayoutEdits(editsDirectory: directory)
        let session = makeSession(store, trait: portrait)
        session.commitPinch("a", magnification: 1.5, baseFrame: frame, geometry: geometry)
        session.commitPinch("b", magnification: 0.7, baseFrame: frame, geometry: geometry)
        #expect(!session.selectedHasEdit)
        session.select("a")
        #expect(session.selectedHasEdit)
        session.resetSelected()
        #expect(session.edit(for: "a") == .identity)
        #expect(store.edit(forButton: "a", skinIdentifier: skin, traitKey: portrait) == .identity)
        #expect(session.edit(for: "b").scale != 1)
        #expect(!session.selectedHasEdit)
    }

    @Test("Reset all clears this orientation only")
    func resetAllInTrait() {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeltaSkinLayoutEdits(editsDirectory: directory)
        let session = makeSession(store, trait: portrait)
        session.commitPinch("a", magnification: 1.5, baseFrame: frame, geometry: geometry)
        makeSession(store, trait: landscape).commitPinch("a", magnification: 1.5, baseFrame: frame, geometry: geometry)
        session.resetAllInTrait()
        #expect(!session.hasEdits)
        #expect(!store.hasEdits(skinIdentifier: skin, traitKey: portrait))
        #expect(store.hasEdits(skinIdentifier: skin, traitKey: landscape))
    }

    @Test("The live edit previews a gesture without saving it")
    func liveEditDoesNotSave() {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeltaSkinLayoutEdits(editsDirectory: directory)
        let session = makeSession(store, trait: portrait)
        let live = session.liveEdit(
            for: "a", baseFrame: frame, translation: CGSize(width: 8, height: 0), magnification: 1.5, geometry: geometry
        )
        #expect(live.dx == 8)
        #expect(abs(live.scale - 1.5) < 1e-9)
        #expect(session.edit(for: "a") == .identity)
        #expect(!store.hasEdits(skinIdentifier: skin))
    }

    @Test("A simultaneous drag and pinch saves exactly what the preview showed, even at an edge")
    func combinedGestureMatchesPreview() {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeltaSkinLayoutEdits(editsDirectory: directory)
        let session = makeSession(store, trait: portrait)
        // A button at the right edge of the 100-point-wide mapping area, grown 2x and dragged 20 mapping points left.
        let edgeFrame = CGRect(x: 80, y: 80, width: 20, height: 20)
        let drag = CGSize(width: -40, height: 0)  // screen points; the container is drawn at 2x
        let preview = session.liveEdit(for: "a", baseFrame: edgeFrame, translation: drag, magnification: 2, geometry: geometry)
        // Committing the two gestures one after the other, in either order, would clamp differently.
        let dragThenPinch = geometry.pinched(geometry.dragged(.identity, by: drag, baseFrame: edgeFrame), by: 2, baseFrame: edgeFrame)
        #expect(dragThenPinch != preview, "the fixture really is order-sensitive")
        session.commitGesture("a", translation: drag, magnification: 2, baseFrame: edgeFrame, geometry: geometry)
        #expect(session.edit(for: "a") == preview.normalized)
        #expect(preview.applying(to: edgeFrame).maxX <= 100)
    }

    @Test("A failed save is kept, logged and does not change what is shown")
    func saveFailure() throws {
        // The edits "folder" is a file, so creating the directory under it fails.
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("EditSessionBlocker-\(UUID().uuidString)")
        try Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let store = DeltaSkinLayoutEdits(editsDirectory: blocker.appendingPathComponent("edits"))
        let session = makeSession(store, trait: portrait)
        session.commitDrag("a", translation: CGSize(width: 10, height: 0), baseFrame: frame, geometry: geometry)
        #expect(session.lastSaveError != nil)
        #expect(session.edit(for: "a") == .identity)
    }
}

@Suite("Skin options model")
struct DeltaSkinOptionsModelTests {
    private func model(
        themes: Bool = false, alt: Bool = false, keys: [String] = [], matched: String? = nil, title: String? = nil,
        edit: Bool = false, export: Bool = false, edits: Bool = false
    ) -> DeltaSkinOptionsModel {
        DeltaSkinOptionsModel(
            hasThemes: themes, hasAltRepresentations: alt, altGameKeys: keys, matchedOverrideKey: matched,
            gameTitle: title, canEditControls: edit, canExport: export, hasEdits: edits
        )
    }

    @Test("Rows show only when they apply")
    func rows() {
        let none = model()
        #expect(!none.showsThemePicker && !none.showsAltToggle && none.gameOverrideLine == nil)
        #expect(!none.showsEditControls && !none.showsExport)

        #expect(model(themes: true).showsThemePicker)
        #expect(model(alt: true, keys: ["g"]).showsAltToggle)
        #expect(!model(alt: true, keys: []).showsAltToggle)   // no game to store the choice under
        #expect(!model(alt: false, keys: ["g"]).showsAltToggle)
        #expect(model(edit: true).showsEditControls)
        #expect(model(export: true).showsExport)
    }

    @Test("Reset is enabled only when something is edited")
    func resetEnabled() {
        #expect(!model(edit: true, edits: false).resetEnabled)
        #expect(model(edit: true, edits: true).resetEnabled)
    }

    @Test("The override line prefers the game title over the matched key")
    func overrideLine() {
        #expect(model(matched: "Doom").gameOverrideLine == "Layout for: Doom")
        #expect(model(matched: "5d41402abc4b2a76b9719d911017c592", title: "Doom").gameOverrideLine == "Layout for: Doom")
        #expect(model(matched: "Doom", title: "  ").gameOverrideLine == "Layout for: Doom")
    }

    @Test("Alt-layout keys put the game id first and drop empties and repeats")
    func altKeys() {
        #expect(DeltaSkinOptionsModel.altGameKeys(gameId: "id", traitGameKeys: ["md5", "id", " ", "crc"]) == ["id", "md5", "crc"])
        #expect(DeltaSkinOptionsModel.altGameKeys(gameId: nil, traitGameKeys: ["md5"]) == ["md5"])
        #expect(DeltaSkinOptionsModel.altGameKeys(gameId: nil, traitGameKeys: []).isEmpty)
        #expect(DeltaSkinOptionsModel.altGameKeys(gameId: "", traitGameKeys: []).isEmpty)
    }

    @Test("Override keys match in candidate order, exactly then case-insensitively, per device")
    func overrideMatching() {
        let overrides: [String: [String: Int]] = [
            "Metroid": ["iphone": 1],
            "ABCDEF": ["iphone": 1, "ipad": 1],
            "Zelda": ["ipad": 1],
        ]
        func match(_ candidates: [String], _ device: DeltaSkinDevice = .iphone) -> String? {
            DeltaSkinOptionsModel.matchedOverrideKey(candidates: candidates, overrides: overrides, device: device)
        }
        #expect(match(["Metroid"]) == "Metroid")
        #expect(match(["metroid"]) == "Metroid")                       // case-insensitive
        #expect(match(["abcdef", "Metroid"]) == "ABCDEF")             // the first candidate wins
        #expect(match(["nope", "Metroid"]) == "Metroid")              // later candidates still count
        #expect(match(["Zelda"]) == nil)                              // no iPhone entry
        #expect(match(["Zelda"], .ipad) == "Zelda")
        #expect(match([]) == nil)
    }
}
