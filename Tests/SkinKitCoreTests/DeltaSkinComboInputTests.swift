import Foundation
import Testing
@testable import SkinKitCore

/// A Delta item with `"inputs": ["a", "b"]` is a combo hotspot (iFly presses both). `input` stays the
/// first input, so a consumer that does not know about combos behaves as it always did.
@Suite("Combo hotspot inputs")
struct DeltaSkinComboInputTests {

    private func makeSkin() throws -> DeltaSkin {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkinKitCoreTests-\(UUID().uuidString).deltaskin", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = """
        {
          "name": "Combo", "identifier": "com.example.combo",
          "gameTypeIdentifier": "public.aoshuang.game.dc",
          "representations": { "iphone": { "edgeToEdge": { "portrait": {
            "assets": { "resizable": "skin.pdf" },
            "mappingSize": { "width": 414, "height": 896 },
            "items": [
              { "inputs": ["a"], "frame": { "x": 10, "y": 20, "width": 50, "height": 50 } },
              { "inputs": ["a", "b"], "frame": { "x": 70, "y": 20, "width": 50, "height": 50 } },
              { "inputs": ["x", "y", "start"], "frame": { "x": 130, "y": 20, "width": 50, "height": 50 } },
              { "inputs": { "up": "up", "down": "down", "left": "left", "right": "right" },
                "frame": { "x": 100, "y": 200, "width": 80, "height": 80 } }
            ]
          } } } }
        }
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("info.json"))
        return try DeltaSkin(fileURL: dir)
    }

    private let traits = DeltaSkinTraits(device: .iphone, displayType: .edgeToEdge, orientation: .portrait)

    @Test("A combo item keeps its first input as `input` and lists every input in comboInputs")
    func comboItems() throws {
        let buttons = try #require(makeSkin().buttons(for: traits))
        #expect(buttons.count == 4)

        #expect(buttons[0].input == .single("a"))
        #expect(buttons[0].comboInputs.isEmpty)

        #expect(buttons[1].input == .single("a"))
        #expect(buttons[1].comboInputs == ["a", "b"])

        #expect(buttons[2].input == .single("x"))
        #expect(buttons[2].comboInputs == ["x", "y", "start"])

        #expect(buttons[3].comboInputs.isEmpty)
        if case .directional = buttons[3].input {} else { Issue.record("expected a directional input") }
    }

    @Test("comboInputs never has exactly one element")
    func normalised() {
        let frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        #expect(DeltaSkinButton(id: "a", input: .single("a"), frame: frame, comboInputs: ["a"]).comboInputs.isEmpty)
        #expect(DeltaSkinButton(id: "a", input: .single("a"), frame: frame, comboInputs: ["a", "b"]).comboInputs == ["a", "b"])
    }

    @Test("withFrame and Codable keep the combo")
    func preserved() throws {
        let frame = CGRect(x: 1, y: 2, width: 3, height: 4)
        let button = DeltaSkinButton(id: "ab", input: .single("a"), frame: frame, comboInputs: ["a", "b"])
        #expect(button.withFrame(CGRect(x: 5, y: 6, width: 7, height: 8)).comboInputs == ["a", "b"])

        let decoded = try JSONDecoder().decode(DeltaSkinButton.self, from: JSONEncoder().encode(button))
        #expect(decoded.comboInputs == ["a", "b"])
        #expect(decoded == button)

        // A button encoded before the key existed decodes with no combo.
        let plain = DeltaSkinButton(id: "a", input: .single("a"), frame: frame)
        let plainJSON = try JSONEncoder().encode(plain)
        #expect(!String(decoding: plainJSON, as: UTF8.self).contains("comboInputs"))
        #expect(try JSONDecoder().decode(DeltaSkinButton.self, from: plainJSON).comboInputs.isEmpty)
    }
}
