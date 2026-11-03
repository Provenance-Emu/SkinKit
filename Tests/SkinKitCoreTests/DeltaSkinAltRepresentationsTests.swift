import CoreGraphics
import Foundation
import Testing
@testable import SkinKitCore

/// Ignited's `altRepresentations`: a second layout tree that the `toggleAltRepresentations` button switches to.
///
/// `DS-AltToggle-Test` is synthetic: its alternate set has iPhone standard portrait (swapped screens, its own
/// mapping size and artwork) and iPhone edgeToEdge landscape (no `screens`), and no iPad.
/// `IgnitedDS-Alt-Test` is the catalog's Ignited DS `info.json` (deltastyles.com), trimmed to iPhone and its `tv` entry.
@Suite("altRepresentations")
struct DeltaSkinAltRepresentationsTests {

    private static func skin(_ name: String, options: DeltaSkin.DecodingOptions = []) throws -> DeltaSkin {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "deltaskin"))
        return try DeltaSkin(fileURL: url, options: options)
    }

    private static func traits(_ device: DeltaSkinDevice = .iphone,
                               _ displayType: DeltaSkinDisplayType = .standard,
                               _ orientation: DeltaSkinOrientation = .portrait,
                               alt: Bool) -> DeltaSkinTraits {
        DeltaSkinTraits(device: device, displayType: displayType, orientation: orientation, usesAltRepresentations: alt)
    }

    private static func outputFrames(_ skin: DeltaSkin, _ traits: DeltaSkinTraits) -> [CGRect?] {
        skin.representation(for: traits)?.screens?.map(\.outputFrame) ?? []
    }

    // MARK: - Decoding

    @Test("The alternate tree decodes with the same shape as representations")
    func decodesAltTree() throws {
        let skin = try Self.skin("DS-AltToggle-Test")
        #expect(skin.hasAltRepresentations)
        let alt = try #require(skin.info.altRepresentations)
        #expect(alt[.iphone]?.standard?["portrait"]?.mappingSize == CGSize(width: 414, height: 896))
        #expect(alt[.iphone]?.edgeToEdge?["landscape"] != nil)
        #expect(alt[.ipad] == nil)
    }

    @Test("A skin without altRepresentations has none, and the flag changes nothing")
    func absentAltIsNormalSet() throws {
        let skin = try Self.skin("DS-Test", options: .lenient)   // DS-Test needs the lenient reading (comments, a null size)
        #expect(!skin.hasAltRepresentations)
        #expect(skin.info.altRepresentations == nil)
        for device in [DeltaSkinDevice.iphone, .ipad] {
            for displayType in [DeltaSkinDisplayType.standard, .edgeToEdge] {
                for orientation in DeltaSkinOrientation.allCases {
                    let off = Self.traits(device, displayType, orientation, alt: false)
                    let on = Self.traits(device, displayType, orientation, alt: true)
                    #expect(skin.mappingSize(for: off) == skin.mappingSize(for: on))
                    #expect(Self.outputFrames(skin, off) == Self.outputFrames(skin, on))
                    #expect(skin.representation(for: off)?.assets.resizable == skin.representation(for: on)?.assets.resizable)
                }
            }
        }
    }

    @Test("A null altRepresentations decodes as absent")
    func nullAltIsAbsent() throws {
        let json = """
        {"name":"N","identifier":"t.null.alt","gameTypeIdentifier":"com.rileytestut.delta.game.ds",
         "representations":{"iphone":{"standard":{"portrait":{"mappingSize":{"width":1,"height":1}}}}},
         "altRepresentations":null}
        """
        let info = try DeltaSkin.Info.decode(Data(json.utf8))
        #expect(info.altRepresentations == nil)
    }

    @Test("The lenient reading keeps the alternate tree")
    func lenientKeepsAlt() throws {
        let skin = try Self.skin("DS-AltToggle-Test", options: .lenient)
        #expect(skin.hasAltRepresentations)
        #expect(skin.mappingSize(for: Self.traits(alt: true)) == CGSize(width: 414, height: 896))
    }

    @Test("The toggle button decodes as a single input in both sets")
    func toggleInputDecodes() throws {
        let skin = try Self.skin("DS-AltToggle-Test")
        for alt in [false, true] {
            let buttons = try #require(skin.buttons(for: Self.traits(alt: alt)))
            let toggle = buttons.first { button in
                if case .single(let input) = button.input { return input == DeltaSkin.toggleAltRepresentationsInput }
                return false
            }
            #expect(toggle != nil, "alt: \(alt)")
        }
        #expect(DeltaSkin.toggleAltRepresentationsInput == "toggleAltRepresentations")
    }

    // MARK: - Selecting the set

    @Test("The flag selects the alternate representation: items, artwork, mapping size and screens")
    func flagSelectsAltSet() throws {
        let skin = try Self.skin("DS-AltToggle-Test")
        let normal = try #require(skin.representation(for: Self.traits(alt: false)))
        let alt = try #require(skin.representation(for: Self.traits(alt: true)))

        #expect(normal.mappingSize == CGSize(width: 414, height: 736))
        #expect(alt.mappingSize == CGSize(width: 414, height: 896))
        #expect(normal.assets.resizable == "normal-portrait.pdf")
        #expect(alt.assets.resizable == "alt-portrait.pdf")

        func inputs(_ rep: DeltaSkin.RepresentationInfo) -> [String] {
            rep.items?.compactMap { if case .single(let list) = $0.inputs { return list.first } else { return nil } } ?? []
        }
        #expect(inputs(normal) == ["a", "toggleAltRepresentations"])
        #expect(inputs(alt) == ["b", "toggleAltRepresentations"])

        // The alternate layout swaps the two DS screens.
        let normalScreens = try #require(skin.screens(for: Self.traits(alt: false)))
        let altScreens = try #require(skin.screens(for: Self.traits(alt: true)))
        #expect(altScreens.count == 2)
        #expect(altScreens[0].outputFrame == normalScreens[1].outputFrame)
        #expect(altScreens[1].outputFrame == normalScreens[0].outputFrame)

        let groups = try #require(skin.screenGroups(for: Self.traits(alt: true))?.first)
        #expect(groups.screens.map(\.outputFrame) == altScreens.map(\.outputFrame))
    }

    @Test("Toggling back and forth on one skin is not served from the other set's cache")
    func cacheKeepsSetsApart() throws {
        DeltaSkin.clearRepresentationCache()
        let skin = try Self.skin("DS-AltToggle-Test")
        for _ in 0..<3 {
            #expect(skin.mappingSize(for: Self.traits(alt: false)) == CGSize(width: 414, height: 736))
            #expect(skin.mappingSize(for: Self.traits(alt: true)) == CGSize(width: 414, height: 896))
        }
    }

    // MARK: - Fallback

    @Test("A device the alternate set lacks falls back to the normal set")
    func missingDeviceFallsBack() throws {
        let skin = try Self.skin("DS-AltToggle-Test")
        let on = Self.traits(.ipad, .standard, .portrait, alt: true)
        let off = Self.traits(.ipad, .standard, .portrait, alt: false)
        #expect(skin.supports(on))
        #expect(skin.mappingSize(for: on) == CGSize(width: 768, height: 1024))
        #expect(skin.representation(for: on)?.assets.resizable == "normal-ipad.pdf")
        #expect(Self.outputFrames(skin, on) == Self.outputFrames(skin, off))
    }

    @Test("Inside the alternate set, standard and edgeToEdge fall back to each other before the normal set")
    func altDisplayTypeFallback() throws {
        let skin = try Self.skin("DS-AltToggle-Test")
        // Alt has only edgeToEdge landscape; the normal set has standard landscape.
        let rep = try #require(skin.representation(for: Self.traits(.iphone, .standard, .landscape, alt: true)))
        #expect(rep.assets.resizable == "alt-landscape.pdf")
        #expect(rep.mappingSize == CGSize(width: 896, height: 414))
    }

    @Test("An alternate representation without screens keeps the normal set's screens for that trait")
    func screensFallBackPerTrait() throws {
        let skin = try Self.skin("DS-AltToggle-Test")
        let on = Self.traits(.iphone, .edgeToEdge, .landscape, alt: true)
        let off = Self.traits(.iphone, .edgeToEdge, .landscape, alt: false)   // normal resolves standard landscape
        let screens = try #require(skin.screens(for: on))
        #expect(screens.count == 2)
        #expect(screens.map(\.outputFrame) == (skin.screens(for: off) ?? []).map(\.outputFrame))
        #expect(screens[0].outputFrame == CGRect(x: 100, y: 0, width: 400, height: 300))
        // The rest of the representation is still the alternate one.
        #expect(skin.representation(for: on)?.assets.resizable == "alt-landscape.pdf")
        #expect(skin.screenGroups(for: on)?.first?.screens.count == 2)
    }

    @Test("A matching gameOverride still wins over the alternate set")
    func gameOverrideBeatsAlt() throws {
        let json = """
        {"name":"G","identifier":"t.override.alt","gameTypeIdentifier":"com.rileytestut.delta.game.ds",
         "representations":{"iphone":{"standard":{"portrait":{"mappingSize":{"width":1,"height":1}}}}},
         "altRepresentations":{"iphone":{"standard":{"portrait":{"mappingSize":{"width":2,"height":2}}}}},
         "gameOverrides":{"Mario":{"iphone":{"standard":{"portrait":{"mappingSize":{"width":3,"height":3}}}}}}}
        """
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("alt-override-\(UUID().uuidString).deltaskin")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(json.utf8).write(to: dir.appendingPathComponent("info.json"))
        let skin = try DeltaSkin(fileURL: dir)

        let game = DeltaSkinTraits(device: .iphone, gameIdentifier: "Mario", usesAltRepresentations: true)
        #expect(skin.mappingSize(for: game) == CGSize(width: 3, height: 3))
        let other = DeltaSkinTraits(device: .iphone, gameIdentifier: "Zelda", usesAltRepresentations: true)
        #expect(skin.mappingSize(for: other) == CGSize(width: 2, height: 2))
    }

    // MARK: - Real Ignited skin

    @Test("The catalog's Ignited DS decodes strictly and switches to its swapped-screen layout")
    func ignitedDS() throws {
        let skin = try Self.skin("IgnitedDS-Alt-Test")
        #expect(skin.identifier == "com.ignited.ds.standard")
        #expect(skin.hasAltRepresentations)

        for displayType in [DeltaSkinDisplayType.standard, .edgeToEdge] {
            for orientation in DeltaSkinOrientation.allCases {
                let off = Self.traits(.iphone, displayType, orientation, alt: false)
                let on = Self.traits(.iphone, displayType, orientation, alt: true)
                let normal = try #require(skin.screens(for: off))
                let alt = try #require(skin.screens(for: on))
                #expect(normal.count == 2 && alt.count == 2)
                // Ignited's alternate layout puts the touch screen where the top screen was, and the reverse.
                #expect(alt[0].outputFrame == normal[1].outputFrame)
                #expect(alt[1].outputFrame == normal[0].outputFrame)

                for traits in [off, on] {
                    let tokens = skin.buttons(for: traits)?.compactMap { button -> String? in
                        if case .single(let input) = button.input { return input } else { return nil }
                    } ?? []
                    #expect(tokens.contains(DeltaSkin.toggleAltRepresentationsInput), "\(traits.description)")
                }
            }
        }
    }

    @Test("The catalog's Ignited DS also decodes under the lenient reading")
    func ignitedDSLenient() throws {
        let skin = try Self.skin("IgnitedDS-Alt-Test", options: .lenient)
        #expect(skin.hasAltRepresentations)
        #expect(skin.screens(for: Self.traits(alt: true))?.count == 2)
    }

    // MARK: - Traits

    @Test("The flag round-trips through Codable, and traits encoded before it decode as false")
    func traitsCodable() throws {
        let on = DeltaSkinTraits(device: .iphone, displayType: .edgeToEdge, orientation: .landscape,
                                 gameIdentifiers: ["abc"], usesAltRepresentations: true)
        let decoded = try JSONDecoder().decode(DeltaSkinTraits.self, from: JSONEncoder().encode(on))
        #expect(decoded == on)
        #expect(decoded.usesAltRepresentations)

        let off = on.withAltRepresentations(false)
        let offJSON = try #require(String(data: JSONEncoder().encode(off), encoding: .utf8))
        #expect(!offJSON.contains("usesAltRepresentations"))   // unchanged encoding for the default

        let legacy = #"{"device":"iphone","displayType":"standard","orientation":"portrait","externalDisplay":"none"}"#
        #expect(try !JSONDecoder().decode(DeltaSkinTraits.self, from: Data(legacy.utf8)).usesAltRepresentations)
    }

    @Test("Traits that differ only in the flag are different traits")
    func traitsEquality() {
        let off = Self.traits(alt: false)
        let on = off.withAltRepresentations(true)
        #expect(off != on)
        #expect(Set([off, on]).count == 2)
        #expect(on.description.hasSuffix("-alt"))
        #expect(!off.description.contains("alt"))
    }

    // MARK: - DS touchscreen and raw items follow the active set

    @Test("On the Ignited DS, the touchscreen follows the DS bottom screen's input after toggling")
    func ignitedTouchScreenFollowsToggle() throws {
        let skin = try Self.skin("IgnitedDS-Alt-Test")
        for displayType in [DeltaSkinDisplayType.standard, .edgeToEdge] {
            for orientation in DeltaSkinOrientation.allCases {
                let off = Self.traits(.iphone, displayType, orientation, alt: false)
                let on = Self.traits(.iphone, displayType, orientation, alt: true)
                let normal = try #require(skin.screenGroups(for: off)?.first?.screens)
                let alt = try #require(skin.screenGroups(for: on)?.first?.screens)

                // Normal set: the touchscreen (input y 192) is drawn lowest; both rules agree.
                let normalTouch = try #require(DeltaSkinScreen.ndsBottomScreen(in: normal, byInputIdentity: off.usesAltRepresentations))
                #expect(normalTouch.inputFrame?.minY == 192)
                #expect(DeltaSkinScreen.ndsBottomScreen(in: normal, byInputIdentity: true)?.id == normalTouch.id)

                // Alternate set: the touchscreen is drawn where the top screen was, above the other screen.
                let altTouch = try #require(DeltaSkinScreen.ndsBottomScreen(in: alt, byInputIdentity: on.usesAltRepresentations))
                #expect(altTouch.inputFrame?.minY == 192, "\(on.description)")
                #expect(altTouch.outputFrame == normal[0].outputFrame, "\(on.description)")
                // The output-position rule alone would have picked the non-touch screen.
                #expect(DeltaSkinScreen.ndsBottomScreen(in: alt, byInputIdentity: false)?.inputFrame?.minY == 0)
            }
        }
    }

    @Test("Raw items come from the same tree as the decoded buttons, for both sets")
    func rawItemsFollowActiveSet() throws {
        let skin = try Self.skin("DS-AltToggle-Test")
        func frame(_ item: [String: Any]) -> CGRect? {
            guard let f = item["frame"] as? [String: Any],
                  let x = (f["x"] as? NSNumber)?.doubleValue, let y = (f["y"] as? NSNumber)?.doubleValue,
                  let w = (f["width"] as? NSNumber)?.doubleValue, let h = (f["height"] as? NSNumber)?.doubleValue else { return nil }
            return CGRect(x: x, y: y, width: w, height: h)
        }
        let cases: [(DeltaSkinDevice, DeltaSkinDisplayType, DeltaSkinOrientation)] = [
            (.iphone, .standard, .portrait), (.iphone, .edgeToEdge, .portrait),
            (.iphone, .standard, .landscape), (.iphone, .edgeToEdge, .landscape),
        ]
        for (device, displayType, orientation) in cases {
            for alt in [false, true] {
                let traits = Self.traits(device, displayType, orientation, alt: alt)
                let raw = DeltaSkin.rawItems(in: skin.jsonRepresentation, for: traits) ?? []
                let decoded = skin.buttons(for: traits) ?? []
                #expect(raw.map(frame) == decoded.map { $0.frame }, "\(traits.description)")
            }
        }
        // Concretely: the alternate portrait items are the alternate tree's.
        let altItems = DeltaSkin.rawItems(in: skin.jsonRepresentation, for: Self.traits(alt: true)) ?? []
        #expect(altItems.first?["inputs"] as? [String] == ["b"])
        let normalItems = DeltaSkin.rawItems(in: skin.jsonRepresentation, for: Self.traits(alt: false)) ?? []
        #expect(normalItems.first?["inputs"] as? [String] == ["a"])
        // A device the alternate set lacks reads the normal tree (no items there).
        #expect(DeltaSkin.rawItems(in: skin.jsonRepresentation, for: Self.traits(.ipad, .standard, .portrait, alt: true)) == nil)
    }
}
