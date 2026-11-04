import CryptoKit
import Foundation
import Testing
@testable import SkinKitRetroArch

@Suite("RetroArch input map")
struct RetroArchInputMapTests {
    let map = try! RetroArchInputMap.bundled()

    /// SHA-256 of `retroarch-input-map.json` as vendored from skins#38 (`docs/js/skin/retroarch-input-map.json`).
    /// The website vendors a copy of this file; change both together and update this value.
    static let vendoredSHA256 = "dc0b9da4826e13c215a3008f4c4e6c5179b4ef5311ebd93b113cb91d7078e613"

    @Test("The bundled table is the vendored file, unchanged")
    func bundledIsVendoredCopy() throws {
        let url = try #require(RetroArchInputMap.bundledURL)
        let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        #expect(digest == Self.vendoredSHA256, "retroarch-input-map.json changed: re-vendor it in the skins repo too")
        #expect(map.version == 1)
        #expect(map.systems["n64"]?.assumes?.contains("Mupen64Plus-Next") == true)
    }

    @Test("systemOf uses gameTypes, then the identifier's suffix")
    func systems() {
        #expect(map.system(forGameTypeIdentifier: "com.rileytestut.delta.game.ds") == "nds")
        #expect(map.system(forGameTypeIdentifier: "COM.RILEYTESTUT.DELTA.GAME.DS") == "nds")
        #expect(map.system(forGameTypeIdentifier: "public.aoshuang.game.megadrive") == "genesis")
        #expect(map.system(forGameTypeIdentifier: "com.whatever.psx") == "psx")
        #expect(map.system(forGameTypeIdentifier: "com.whatever.zzz") == "zzz")
        #expect(map.system(forGameTypeIdentifier: nil) == "unknown")
        #expect(map.system(forGameTypeIdentifier: "") == "unknown")
    }

    @Test("Tokens resolve per system, then aliases, common and the default row")
    func lookups() {
        #expect(map.lookup("z", system: "n64") == .bind("l2"))
        #expect(map.lookup("c", system: "genesis") == .bind("a"))
        #expect(map.lookup("a", system: "genesis") == .bind("y"))
        #expect(map.lookup("cross", system: "psx") == .bind("b"))
        #expect(map.lookup("menu", system: "gba") == .bind("menu_toggle"))
        #expect(map.lookup("l2", system: "unknown") == .bind("l2"))
        #expect(map.lookup("c-up", system: "n64") == .bind("r_y_minus"), "aliases resolve through the system row")
        #expect(map.lookup("c-up", system: "gba") == .unknown, "aliases belong to their system")
        #expect(map.lookup("nonsense", system: "nes") == .unknown)
    }

    @Test("A known token with nothing to bind differs from an unknown one")
    func nullIsNotAbsent() {
        #expect(map.lookup("touchScreenX", system: "nds") == .noEquivalent)
        #expect(map.lookup("touchScreenX", system: "nds").bindID == nil)
        #expect(map.reason(forUnconvertible: "touchScreenX", system: "nds").contains("pointer"))
        #expect(map.reason(forUnconvertible: "nonsense", system: "nes") == "No RetroArch bind known for \"nonsense\" on nes.")
        #expect(map.reason(forUnconvertible: "touchScreen", system: "gba").contains("pointer"))
    }

    @Test("Malformed input maps are rejected")
    func rejectsGarbage() {
        #expect(throws: RetroArchInputMap.LoadError.invalidJSON) { try RetroArchInputMap(data: Data("[]".utf8)) }
        #expect(throws: (any Error).self) { try RetroArchInputMap(data: Data("nope".utf8)) }
        #expect(throws: RetroArchInputMap.LoadError.invalidJSON) { try RetroArchInputMap(data: Data("{}".utf8)) }
    }
}

@Suite("RetroArch overlay preset writer")
struct RetroArchPresetWriterTests {

    @Test("Numbers are rounded to six places like the website writes them")
    func fixed6() {
        #expect(RetroArchOverlayPreset.fixed6(0.5) == "0.500000")
        #expect(RetroArchOverlayPreset.fixed6(1.0 / 3.0) == "0.333333")
        #expect(RetroArchOverlayPreset.fixed6(2.0 / 3.0) == "0.666667")
        #expect(RetroArchOverlayPreset.fixed6(-0.0) == "0.000000")
        #expect(RetroArchOverlayPreset.fixed6(-0.0000001) == "0.000000", "negative zero is written without a sign")
        #expect(RetroArchOverlayPreset.fixed6(-0.25) == "-0.250000")
        #expect(RetroArchOverlayPreset.fixed6(0.0000005) == "0.000001")
        #expect(RetroArchOverlayPreset.fixed6(1.7777777777) == "1.777778")
    }

    @Test("Keys come out in one fixed order, with the sub-keys after their descriptor")
    func order() {
        let preset = RetroArchOverlayPreset(
            headerComments: ["Test overlay"],
            overlays: [
                .init(name: "portrait", image: "t-portrait.png", aspectRatio: 0.5625,
                      rect: .init(x: 0, y: 0.5, width: 1, height: 0.5),
                      descs: [
                          .init(inputs: ["up", "left"], x: 0.25, y: 0.75, shape: .rect, rangeX: 0.1, rangeY: 0.05),
                          .init(inputs: ["analog_left"], x: 0.2, y: 0.8, shape: .radial, rangeX: 0.1, rangeY: 0.1,
                                image: "t-thumb1.png", movable: true),
                          .init(inputs: ["overlay_next"], x: 0.5, y: 0, shape: .rect, rangeX: 0.001, rangeY: 0.001,
                                nextTarget: "landscape", reachX: 0, reachY: 0),
                      ]),
            ])
        #expect(preset.cfg == """
            # Test overlay

            overlays = 1

            overlay0_name = "portrait"
            overlay0_overlay = "t-portrait.png"
            overlay0_full_screen = true
            overlay0_normalized = true
            overlay0_aspect_ratio = 0.562500
            overlay0_rect = "0.000000,0.500000,1.000000,0.500000"
            overlay0_descs = 3
            overlay0_desc0 = "up|left,0.250000,0.750000,rect,0.100000,0.050000"
            overlay0_desc1 = "analog_left,0.200000,0.800000,radial,0.100000,0.100000"
            overlay0_desc1_overlay = "t-thumb1.png"
            overlay0_desc1_movable = true
            overlay0_desc2 = "overlay_next,0.500000,0.000000,rect,0.001000,0.001000"
            overlay0_desc2_next_target = "landscape"
            overlay0_desc2_reach_x = 0.0
            overlay0_desc2_reach_y = 0.0

            """)
    }

    @Test("A preset without overlays writes nothing")
    func emptyPreset() {
        #expect(RetroArchOverlayPreset().cfg == "")
        #expect(RetroArchOverlayPreset(headerComments: ["x"]).cfg == "")
    }

    @Test("The cfg reads back as key = value lines with the counts it declares")
    func cfgIsWellFormed() throws {
        let converter = try RetroArchConverter.bundled()
        let result = converter.convert(try Fixture.info("n64-comments"))
        var values: [String: String] = [:]
        for raw in result.cfg.split(separator: "\n", omittingEmptySubsequences: true) where !raw.hasPrefix("#") {
            let parts = raw.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            #expect(parts.count == 2, "key = value: \(raw)")
            values[parts[0]] = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        let overlays = try #require(Int(values["overlays"] ?? ""))
        #expect(overlays == result.preset.overlays.count)
        for k in 0..<overlays {
            let count = try #require(Int(values["overlay\(k)_descs"] ?? ""))
            for d in 0..<count {
                let desc = try #require(values["overlay\(k)_desc\(d)"])
                let fields = desc.split(separator: ",")
                #expect(fields.count == 6, "six fields: \(desc)")
                #expect(["rect", "radial"].contains(String(fields[3])))
                if fields[0].hasPrefix("analog_") { #expect(fields[3] == "radial", "analog descs are radial") }
            }
            #expect(values["overlay\(k)_desc\(count)"] == nil, "no descs past the count")
        }
    }
}

@Suite("RetroArch converter")
struct RetroArchConverterTests {
    let converter = try! RetroArchConverter.bundled()

    @Test("stripComments drops comments and trailing commas outside strings only")
    func stripComments() throws {
        let src = "{\n  // a comment\n  \"name\": \"a // b, /* not */ }\", // trailing\n  /* block\n comment */ \"url\": \"http://x,}\",\n  \"a\": [1, 2, // c\n ],\n}\n"
        let cleaned = RetroArchSkinInfo.stripComments(src)
        let json = try #require(JSONSerialization.jsonObject(with: Data(cleaned.utf8)) as? [String: Any])
        #expect(json["name"] as? String == "a // b, /* not */ }")
        #expect(json["url"] as? String == "http://x,}")
        #expect(json["a"] as? [Int] == [1, 2])
        let info = try RetroArchSkinInfo(infoJSON: Data("\u{FEFF}{\"name\":\"x\", // c\n \"a\":[1,],}".utf8))
        #expect(info.name == "x")
    }

    @Test("resolveAsset is lenient like the apps")
    func resolveAsset() {
        let entries = ["info.json", "Art/IPhone_Portrait.PDF", "landscape.png"]
        #expect(RetroArchConverter.resolveAsset(entries, "info.json") == "info.json")
        #expect(RetroArchConverter.resolveAsset(entries, "iphone_portrait.pdf") == "Art/IPhone_Portrait.PDF")
        #expect(RetroArchConverter.resolveAsset(entries, "landscape.pdf") == "landscape.png")
        #expect(RetroArchConverter.resolveAsset(entries, "missing.pdf") == nil)
        #expect(RetroArchConverter.resolveAsset(entries, nil) == nil)
        #expect(RetroArchConverter.resolveAsset(entries, "") == nil)
    }

    @Test("slugify keeps folder names portable")
    func slugify() {
        #expect(RetroArchConverter.slugify("N64 Comments // Test") == "N64_Comments_Test")
        #expect(RetroArchConverter.slugify("Backbone One — GBA") == "Backbone_One_GBA")
        #expect(RetroArchConverter.slugify("  __weird__  ") == "weird")
        for dots in [".", "..", "...", " .. ", "_.._"] {
            #expect(RetroArchConverter.slugify(dots) == "skin", "\(dots) must not name the current or parent folder")
        }
        #expect(RetroArchConverter.slugify("..hidden") == "..hidden")
        #expect(RetroArchConverter.slugify("a.b-c_d") == "a.b-c_d")
        #expect(RetroArchConverter.slugify("") == "skin")
        #expect(RetroArchConverter.slugify(nil) == "skin")
        #expect(RetroArchConverter.slugify("###") == "skin")
        #expect(RetroArchConverter.slugify(String(repeating: "x", count: 100)).count == 60)
        // NFKD splits the accent off, and the combining mark becomes an underscore run, as in JavaScript.
        #expect(RetroArchConverter.slugify("Café Skin") == "Cafe_Skin")
        #expect(RetroArchConverter.slugify("ＡＢＣ") == "ABC", "compatibility forms fold to ASCII")
    }

    @Test("Backbone GBA: SVG landscape layout, hitboxes include edges, zl/zr land on l2/r2")
    func backboneGBA() throws {
        let r = converter.convert(try Fixture.info("backbone-gba"))
        #expect(r.system == "gba")
        #expect(r.preset.overlays.count == 1)
        #expect(r.preset.overlays[0].name == "landscape")
        #expect(r.images.count == 1)
        #expect(r.images[0].asset == "controller.svg")
        #expect(r.images[0].width == 852 && r.images[0].height == 393)
        #expect(r.images[0].clearRects.isEmpty, "translucent layout: its screen area is already clear")
        let binds = Set(r.preset.overlays[0].descs.map { $0.inputs.joined(separator: "|") })
        for b in ["a", "b", "l", "r", "l2", "r2", "select", "start", "menu_toggle", "up|left", "down|right", "up", "left"] {
            #expect(binds.contains(b), "has \(b)")
        }
        #expect(!binds.contains("overlay_next"), "single layout: no rotate desc")
        // The "a" button: frame 766,231 42x34 with item edges 8 is hitbox 758,223 58x50 of 852x393.
        let a = try #require(r.preset.overlays[0].descs.first { $0.inputs == ["a"] })
        #expect(a.x == 787.0 / 852.0)
        #expect(a.y == 248.0 / 393.0)
        #expect(a.rangeX == 29.0 / 852.0)
        #expect(a.rangeY == 25.0 / 393.0)
        #expect(r.unconvertible.isEmpty)
    }

    @Test("N64: thumbstick, C pad, combos, frontend buttons, alt layouts, unconvertible touch")
    func n64() throws {
        let r = converter.convert(try Fixture.info("n64-comments"))
        #expect(r.system == "n64")
        #expect(r.name == "N64_Comments_Test")
        #expect(r.preset.overlays.map(\.name) == ["landscape", "portrait", "portrait-alt"])
        let portrait = r.preset.overlays[1]
        let binds = portrait.descs.map { $0.inputs.joined(separator: "|") }
        let stick = try #require(portrait.descs.first { $0.inputs == ["analog_left"] })
        #expect(stick.shape == .radial)
        #expect(stick.image?.hasSuffix("-thumb0.png") == true)
        #expect(stick.movable)
        let thumb = try #require(r.images.first { $0.kind == .thumbstick })
        #expect([thumb.width, thumb.height, thumb.innerWidth, thumb.innerHeight] == [100, 100, 60, 60], "hitbox 80+10+10, cap 60")
        for b in ["r_y_minus", "r_y_plus", "r_x_minus", "r_x_plus", "r_y_minus|r_x_minus", "r_y_plus|r_x_plus"] {
            #expect(binds.contains(b), "C pad cell \(b)")
        }
        #expect(binds.filter { ["up", "down", "left", "right", "up|left", "up|right", "down|left", "down|right"].contains($0) }.count == 8,
                "plain d-pad is nine rects, centre empty")
        #expect(binds.contains("a|b"))
        #expect(binds.contains("l2"), "N64 Z on L2")
        for b in ["menu_toggle", "toggle_fast_forward", "save_state", "load_state"] { #expect(binds.contains(b)) }
        // The toggle jumps into the alt layout and back from it.
        let toggle = try #require(portrait.descs.first { $0.inputs == ["overlay_next"] && $0.reachX == nil })
        #expect(toggle.nextTarget == "portrait-alt")
        let altToggle = try #require(r.preset.overlays[2].descs.first { $0.inputs == ["overlay_next"] && $0.reachX == nil })
        #expect(altToggle.nextTarget == "portrait")
        // Hidden rotate descs: no hitbox, pointing at the other orientation.
        func rotate(_ k: Int) -> RetroArchOverlayPreset.Desc? { r.preset.overlays[k].descs.first { $0.reachX == 0 } }
        #expect(rotate(0)?.nextTarget == "portrait")
        #expect(rotate(1)?.nextTarget == "landscape")
        #expect(rotate(2)?.nextTarget == "landscape")
        #expect(rotate(1)?.reachY == 0)
        // DS touch inputs are reported, not dropped silently.
        let touch = r.unconvertible.filter { $0.input.hasPrefix("touchScreen") }
        #expect(touch.count == 2)
        #expect(touch.first?.reason.contains("pointer") == true)
        // A 320x340 portrait is a controller strip: bottom-anchored, share (340/320) / (19.5/9) = 0.490385.
        let rect = try #require(portrait.rect)
        #expect(RetroArchOverlayPreset.fixed6(rect.y) == "0.509615" && RetroArchOverlayPreset.fixed6(rect.height) == "0.490385")
        #expect(r.images.first { $0.overlayName == "landscape" }?.clearRects.count == 1, "not translucent: the screen is cleared")
        #expect(r.readme.contains("touchScreenX"))
        #expect(r.readme.contains("Mupen64Plus-Next"))
    }

    @Test("Genesis standard strip: bottom-anchored, core button layout, iPad and fallback")
    func genesis() throws {
        let info = try Fixture.info("genesis-standard-png")
        var options = RetroArchConverter.Options()
        options.displayType = .standard
        let r = converter.convert(info, options: options)
        #expect(r.images[0].asset == "portrait_large.png")
        let overlay = r.preset.overlays[0]
        #expect(overlay.name == "portrait")
        #expect(RetroArchOverlayPreset.fixed6(overlay.aspectRatio) == "0.562500")
        // 375x240 on a 16:9 phone: height share (240/375) / (16/9) = 0.36
        #expect(RetroArchOverlayPreset.fixed6(try #require(overlay.rect).height) == "0.360000")
        let binds = Set(overlay.descs.map { $0.inputs.joined(separator: "|") })
        for b in ["y", "b", "a", "select", "start"] { #expect(binds.contains(b), "Genesis \(b)") }
        #expect(!binds.contains("c"), "Genesis C is remapped")

        options.device = .ipad
        let ipad = converter.convert(info, options: options)
        #expect(ipad.name == "Genesis_Standard_PNG-ipad")
        #expect(ipad.preset.overlays[0].name == "landscape")
        #expect(RetroArchOverlayPreset.fixed6(ipad.preset.overlays[0].aspectRatio) == "1.333333")
        #expect(ipad.notes.isEmpty)

        let fallback = converter.convert(info)
        #expect(fallback.notes.contains { $0.contains("using standard") })
    }

    @Test("Without the artwork a layout is skipped, not emitted")
    func missingArtwork() throws {
        let info = try Fixture.info("n64-comments")
        var options = RetroArchConverter.Options()
        options.entries = ["info.json", "portrait.PDF", "PortraitAlt.pdf", "Thumb.pdf"]
        let r = converter.convert(info, options: options)
        #expect(r.preset.overlays.map(\.name) == ["portrait", "portrait-alt"])
        #expect(r.skipped.count == 1)
        #expect(r.skipped[0].overlayName == "landscape")
        #expect(r.skipped[0].reason.contains("Landscape.pdf"))
        #expect(r.images.allSatisfy { $0.overlayName != "landscape" })
        #expect(r.images.contains { $0.kind == .thumbstick }, "cap resolved case-insensitively")
        #expect(r.readme.contains("Layouts left out"))

        options.entries = ["info.json", "Portrait.pdf", "PortraitAlt.pdf"]
        let noCap = converter.convert(info, options: options)
        #expect(!noCap.images.contains { $0.kind == .thumbstick })
        #expect(noCap.preset.overlays.allSatisfy { $0.descs.allSatisfy { !$0.movable } })
        #expect(noCap.notes.contains { $0.contains("thumb.pdf") })

        #expect(converter.convert(info).skipped.isEmpty, "no entries given: nothing to check against")
    }

    @Test("A skin with no artwork converts to nothing, with a note")
    func noArtwork() throws {
        let r = converter.convert(try Fixture.info("empty"))
        #expect(r.cfg.isEmpty)
        #expect(r.readme.isEmpty)
        #expect(r.preset.overlays.isEmpty)
        #expect(!r.notes.isEmpty)
        #expect(r.device == nil)
    }

    @Test("Image sizes are 2x the mapping size, long side capped at 2048")
    func pixelSizes() {
        func plan(_ w: Double, _ h: Double) -> RetroArchConversion.ImagePlan {
            .init(file: "x.png", kind: .overlay, asset: nil, orientation: "portrait", overlayName: "portrait",
                  width: w, height: h, innerWidth: nil, innerHeight: nil, clearRects: [])
        }
        #expect(plan(414, 896).pixelSize() == (828, 1792))
        #expect(plan(852, 393).pixelSize() == (1704, 786))
        let big = plan(1334, 750).pixelSize()
        #expect(big.width == 2048 && big.height == 1151, "long side stops at 2048 (\(big))")
        let tiny = plan(0.2, 0.2).pixelSize()
        #expect(tiny.width >= 1 && tiny.height >= 1)
    }
}
