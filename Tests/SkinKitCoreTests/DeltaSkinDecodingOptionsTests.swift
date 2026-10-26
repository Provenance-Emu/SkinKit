import Foundation
import Testing
import ZIPFoundation
@testable import SkinKitCore

/// `DeltaSkin.DecodingOptions`: every option in both modes. The default (`[]`) must read an `info.json` exactly as
/// SkinKitCore always has, so Provenance and iFly are unchanged; each option then changes one thing, and
/// `.lenient` (all of them) is iCube's reading. The fixtures are the cases iCube's own decoder was checked against.
@Suite("DeltaSkin decoding options")
struct DeltaSkinDecodingOptionsTests {
    typealias Options = DeltaSkin.DecodingOptions

    // MARK: - Fixtures

    static let ngc = "public.aoshuang.game.ngc"

    static func skin(_ representations: String, gameType: String = ngc) -> String {
        #"{"name":"N","identifier":"x","gameTypeIdentifier":"\#(gameType)","representations":\#(representations)}"#
    }

    /// One iPhone standard portrait representation with `body` inside it (after a valid `mappingSize`).
    static func portrait(_ body: String, mapping: String = #""mappingSize":{"width":10,"height":20}"#) -> String {
        skin(#"{"iphone":{"standard":{"portrait":{\#(mapping),\#(body)}}}}"#)
    }

    static func decode(_ json: String, _ options: Options) throws -> DeltaSkin.Info {
        try DeltaSkin.Info.decode(Data(json.utf8), options: options)
    }

    static func rep(_ info: DeltaSkin.Info) -> DeltaSkin.OrientationRepresentations? {
        info.representations[.iphone]?.standard?["portrait"]
    }

    static func items(_ json: String, _ options: Options) throws -> [DeltaSkin.ItemRepresentation] {
        try rep(decode(json, options))?.items ?? []
    }

    static func inputs(_ items: [DeltaSkin.ItemRepresentation]) -> [[String]] {
        items.map {
            switch $0.inputs {
            case let .single(names): return names
            case let .directional(map): return map.keys.sorted()
            }
        }
    }

    /// A file on disk, for the `DeltaSkin(fileURL:options:)` path.
    static func directory(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("opts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url.appendingPathComponent("info.json"))
        return url
    }

    // MARK: - The default is unchanged

    @Test("Default options: the ten iCube cases behave as SkinKitCore always has")
    func defaultIsToday() throws {
        // A leading comment fails the up-front parse; `//` inside a string is cut by sanitizeJSON.
        #expect(throws: DeltaSkinError.self) { try Self.decode("// hdr\n" + Self.portrait(#""items":[]"#), []) }
        #expect(throws: (any Error).self) {
            try Self.decode(#"{"name":"https://example.com/s","identifier":"x","gameTypeIdentifier":"public.aoshuang.game.ngc","representations":{}}"#, [])
        }
        // One bad item, or one bad representation, rejects the skin.
        #expect(throws: (any Error).self) { try Self.decode(Self.portrait(#""items":[{"inputs":["b"],"frame":"nope"},{"inputs":["a"],"frame":[1,2,3,4]}]"#), []) }
        #expect(throws: (any Error).self) { try Self.decode(Self.skin(#"{"iphone":{"standard":{"portrait":{"items":[]}}}}"#), []) }
        #expect(throws: (any Error).self) {
            try Self.decode(Self.skin(#"{"iphone":{"standard":{"portrait":{"mappingSize":{"width":"x"}},"landscape":{"mappingSize":{"width":20,"height":10}}}}}"#), [])
        }
        // No limits, no complete-d-pad rule, no edge inheritance, no item asset.
        let huge = try Self.items(Self.portrait(#""items":[{"inputs":["h"],"frame":{"x":0,"y":0,"width":1e308,"height":1}}]"#), [])
        #expect(huge.count == 1 && huge[0].frame.width == 1e308)
        let partial = try Self.items(Self.portrait(#""items":[{"inputs":{"up":"up","down":"down","left":"left"},"frame":[0,0,1,1]}]"#), [])
        #expect(partial.count == 1)
        let edges = try Self.items(Self.portrait(#""extendedEdges":{"top":5,"bottom":5,"left":5,"right":5},"items":[{"inputs":["a"],"frame":[0,0,1,1],"extendedEdges":{"left":20}}]"#), [])
        #expect(edges[0].extendedEdges == DeltaSkinEdgeInsets(top: 0, left: 20, bottom: 0, right: 0))
        let asset = try Self.items(Self.portrait(#""items":[{"inputs":["a"],"frame":[0,0,1,1],"asset":{"normal":"btn-a.pdf"}}]"#), [])
        #expect(asset[0].asset == nil)
        // gcn is read as GameCube.
        #expect(try Self.decode(Self.portrait(#""items":[]"#).replacingOccurrences(of: Self.ngc, with: "com.example.game.GCN"), []).gameTypeIdentifier == .gamecube)
    }

    @Test("Empty options go through the same path as init(fileURL:)")
    func fileInitMatches() throws {
        let url = try Self.directory(Self.portrait(#""items":[{"inputs":["a"],"frame":[1,2,3,4]}]"#))
        let plain = try DeltaSkin(fileURL: url)
        let optioned = try DeltaSkin(fileURL: url, options: [])
        #expect(plain.info.name == optioned.info.name)
        #expect(plain.jsonRepresentation["identifier"] as? String == optioned.jsonRepresentation["identifier"] as? String)
    }

    // MARK: - stripsComments

    @Test("stripsComments: whole-line and trailing comments go; a URL in a string stays")
    func stripsComments() throws {
        let json = """
        // header
        {"name":"https://example.com/skin","identifier":"x","gameTypeIdentifier":"\(Self.ngc)", // trailing
         "representations":{"iphone":{"standard":{"portrait":{"mappingSize":{"width":1,"height":1}}}}}}
        """
        #expect(try Self.decode(json, .stripsComments).name == "https://example.com/skin")
        #expect(throws: DeltaSkinError.self) { try Self.decode(json, []) }
        #expect(String(decoding: try DeltaSkin.stripComments(Data(#"{"a":"http://x//y"} // c"#.utf8)), as: UTF8.self) == #"{"a":"http://x//y"} "#)
    }

    @Test("stripsComments alone changes nothing else: a bad item still rejects the skin")
    func commentsAloneAreNotLenient() {
        #expect(throws: (any Error).self) {
            try Self.decode(Self.portrait(#""items":[{"inputs":["b"],"frame":"nope"}]"#), .stripsComments)
        }
    }

    @Test("A commented skin loads from a directory with stripsComments")
    func commentedSkinFromDisk() throws {
        let json = "// c\n" + Self.portrait(#""items":[]"#)
        let url = try Self.directory(json)
        #expect(throws: DeltaSkinError.self) { try DeltaSkin(fileURL: url) }
        #expect(try DeltaSkin(fileURL: url, options: .stripsComments).name == "N")
    }

    // MARK: - dropsInvalidElements

    @Test("dropsInvalidElements: an item, a representation and a screen are dropped one at a time")
    func dropsElements() throws {
        let items = try Self.items(Self.portrait(#""items":[{"inputs":["b"],"frame":"nope"},{"inputs":["a"],"frame":[1,2,3,4]}]"#), .dropsInvalidElements)
        #expect(Self.inputs(items) == [["a"]])
        #expect(items[0].frame == CGRect(x: 1, y: 2, width: 3, height: 4))

        let reps = try Self.decode(Self.skin(#"{"iphone":{"standard":{"portrait":{"items":[]},"landscape":{"mappingSize":{"width":20,"height":10}}}}}"#), .dropsInvalidElements)
        #expect(reps.representations[.iphone]?.standard?["portrait"] == nil)
        #expect(reps.representations[.iphone]?.standard?["landscape"]?.mappingSize == CGSize(width: 20, height: 10))

        let screens = try Self.decode(Self.portrait(#""screens":[{"outputFrame":"bad"},{"outputFrame":[0,0,10,10]},{"inputFrame":[0,0,1,1]}]"#), .dropsInvalidElements)
        #expect(Self.rep(screens)?.screens?.count == 2, "the bad screen goes; a placement-only screen (no outputFrame) is not invalid")
    }

    @Test("dropsInvalidElements: wrong-typed representation fields drop the representation")
    func dropsRepresentationsWithWrongTypes() throws {
        let json = Self.skin("""
        {"iphone":{"standard":{
          "portrait":{"mappingSize":{"width":10,"height":20},"translucent":"yes"},
          "landscape":{"mappingSize":{"width":20,"height":10},"items":"nope"}}},
         "ipad":{"standard":{"portrait":{"mappingSize":{"width":10,"height":20},"assets":{"resizable":3}},
                              "landscape":{"mappingSize":{"width":20,"height":10}}}}}
        """)
        let info = try Self.decode(json, .dropsInvalidElements)
        #expect(info.representations[.iphone] == nil)
        #expect(info.representations[.ipad]?.standard?["portrait"] == nil)
        #expect(info.representations[.ipad]?.standard?["landscape"] != nil)
    }

    @Test("dropsInvalidElements: throws noUsableRepresentation only when nothing is left")
    func nothingLeft() {
        #expect(throws: DeltaSkinInfoError.noUsableRepresentation) {
            try Self.decode(Self.skin(#"{"iphone":{"standard":{"portrait":{"items":[]}}}}"#), .dropsInvalidElements)
        }
        #expect(throws: DeltaSkinInfoError.noUsableRepresentation) { try Self.decode(Self.skin("{}"), .dropsInvalidElements) }
    }

    @Test("dropsInvalidElements: an optional extra that does not decode is ignored, not fatal")
    func ignoresBrokenExtras() throws {
        let json = #"""
        {"name":"N","identifier":"x","gameTypeIdentifier":"public.aoshuang.game.ngc","debug":"loud","caseController":3,
         "keyboardOverlay":"x","themes":"y","gameOverrides":[1],
         "representations":{"iphone":{"standard":{"portrait":{"mappingSize":{"width":10,"height":20},
           "backgroundAnimation":"oops","gameScreenFrame":"nope",
           "screens":[{"outputFrame":[0,0,10,10],"filters":"garbage","placement":42,"maintainAspectRatio":"x"}],
           "items":[{"inputs":["a"],"frame":[0,0,1,1],"haptic":"???","states":[1,2]}]}}}}}
        """#
        let info = try Self.decode(json, .dropsInvalidElements)
        #expect(Self.rep(info)?.items?.count == 1)
        #expect(Self.rep(info)?.screens?.first?.maintainAspectRatio == true)
        #expect(info.debug == false)
        #expect(throws: (any Error).self) { try Self.decode(json, []) }
    }

    @Test("Without dropsInvalidElements a validating option makes an invalid element an error")
    func validatingOptionsThrowWithoutDrops() {
        #expect(throws: DeltaSkinError.self) {
            try Self.decode(Self.portrait(#""items":[{"inputs":["a"],"frame":[0,0,1,1]},{"inputs":["h"],"frame":[0,0,1e308,1]}]"#), .limitsFrames)
        }
    }

    // MARK: - limitsFrames

    @Test("limitsFrames: out-of-range frames, sizes and edges are invalid")
    func limitsFrames() throws {
        let both: Options = [.dropsInvalidElements, .limitsFrames]
        let items = try Self.items(Self.portrait("""
        "items":[
          {"inputs":["huge"],"frame":{"x":0,"y":0,"width":1e308,"height":1}},
          {"inputs":["negative"],"frame":{"x":0,"y":0,"width":-5,"height":1}},
          {"inputs":["hugeArray"],"frame":[0,0,1,1e308]},
          {"inputs":["negativeArray"],"frame":[0,0,1,-1]},
          {"inputs":["farOrigin"],"frame":{"x":-1e308,"y":0,"width":1,"height":1}},
          {"inputs":["edges"],"frame":[0,0,1,1],"extendedEdges":{"left":1e308}},
          {"inputs":["a"],"frame":[1,2,3,4]}]
        """), both)
        #expect(Self.inputs(items) == [["a"]])
    }

    @Test("limitsFrames: a number that parses to infinity (-1e999) is rejected, never re-serialised")
    func infinityDoesNotCrash() throws {
        let json = Self.portrait(#""items":[{"inputs":["inf"],"frame":[0,0,-1e999,1]},{"inputs":["a"],"frame":[1,2,3,4]}]"#)
        #expect(Self.inputs(try Self.items(json, [.dropsInvalidElements, .limitsFrames])) == [["a"]])
        // With the limit off the number still reaches the rewrite; that throws instead of raising an exception.
        #expect(throws: DeltaSkinError.self) { try Self.decode(json, .dropsInvalidElements) }
    }

    @Test("limitsFrames: mappingSize must be positive and sane")
    func limitsMappingSize() throws {
        let json = Self.skin("""
        {"iphone":{"standard":{
          "portrait":{"mappingSize":{"width":0,"height":20}},
          "landscape":{"mappingSize":{"width":1e308,"height":10}}}},
         "ipad":{"standard":{"portrait":{"mappingSize":{"width":-10,"height":20}},
                              "landscape":{"mappingSize":{"width":20,"height":10}}}}}
        """)
        let info = try Self.decode(json, [.dropsInvalidElements, .limitsFrames])
        #expect(info.representations[.iphone] == nil)
        #expect(info.representations[.ipad]?.standard?["portrait"] == nil)
        #expect(info.representations[.ipad]?.standard?["landscape"]?.mappingSize == CGSize(width: 20, height: 10))
        // Not limited: a zero-width mapping size is accepted, as it always was.
        #expect(try Self.decode(json, [.dropsInvalidElements]).representations[.iphone]?.standard?["portrait"] != nil)
    }

    @Test("limitsFrames: thumbstick sizes and screen frames are limited too")
    func limitsThumbsticksAndScreens() throws {
        func thumbs(_ width: String) throws -> [DeltaSkin.ItemRepresentation] {
            try Self.items(Self.portrait("""
            "items":[
              {"inputs":{"up":"rightThumbstickUp","down":"rightThumbstickDown","left":"rightThumbstickLeft","right":"rightThumbstickRight"},
               "frame":[0,0,10,10],"thumbstick":{"name":"stick.pdf","width":\(width),"height":8}},
              {"inputs":["a"],"frame":[1,2,3,4]}]
            """), [.dropsInvalidElements, .limitsFrames])
        }
        for bad in ["-1e999", "-5", "1e308", "100001"] {
            #expect(Self.inputs(try thumbs(bad)) == [["a"]], "width \(bad)")
        }
        let kept = try thumbs("6")
        #expect(kept.count == 2 && kept[0].thumbstick?.width == 6)

        let screens = try Self.decode(Self.portrait(#""screens":[{"outputFrame":[0,0,1e308,1]},{"outputFrame":[0,0,10,10],"inputFrame":[0,0,-1,1]},{"outputFrame":[0,0,10,10]}]"#), [.dropsInvalidElements, .limitsFrames])
        #expect(Self.rep(screens)?.screens?.count == 1)
    }

    // MARK: - inheritsEdges

    @Test("inheritsEdges: an absent item side takes the representation's, then 0")
    func inheritsEdges() throws {
        let json = Self.portrait(#""extendedEdges":{"left":7},"items":[{"inputs":["a"],"frame":[0,0,1,1]},{"inputs":["b"],"frame":[0,0,1,1],"extendedEdges":{"top":3,"left":null}}]"#)
        let info = try Self.decode(json, .inheritsEdges)
        #expect(Self.rep(info)?.extendedEdges == DeltaSkinEdgeInsets(top: 0, left: 7, bottom: 0, right: 0), "a partial representation fills with 0")
        let items = Self.rep(info)?.items ?? []
        #expect(items[0].extendedEdges == DeltaSkinEdgeInsets(top: 0, left: 7, bottom: 0, right: 0))
        #expect(items[1].extendedEdges == DeltaSkinEdgeInsets(top: 3, left: 7, bottom: 0, right: 0))
        // Off: nothing inherits and a partial representation's edges are ignored.
        let plain = try Self.decode(json, [])
        #expect(Self.rep(plain)?.extendedEdges == nil)
        #expect(Self.rep(plain)?.items?[0].extendedEdges == nil)
        #expect(Self.rep(plain)?.items?[1].extendedEdges == DeltaSkinEdgeInsets(top: 3, left: 0, bottom: 0, right: 0))
    }

    // MARK: - requiresCompleteDirections

    @Test("requiresCompleteDirections: a d-pad missing a direction is invalid; a complete one keeps its four")
    func completeDirections() throws {
        let json = Self.portrait("""
        "items":[
          {"inputs":{"up":"up","down":"down","left":"left"},"frame":[0,0,1,1]},
          {"inputs":{"up":"up","down":"down","left":"left","right":"right","extra":7},"frame":[0,0,1,1]},
          {"inputs":["a"],"frame":[1,2,3,4]}]
        """)
        let items = try Self.items(json, [.dropsInvalidElements, .requiresCompleteDirections])
        #expect(Self.inputs(items) == [["down", "left", "right", "up"], ["a"]])
        #expect(throws: DeltaSkinError.self) { try Self.decode(json, .requiresCompleteDirections) }
        // Off: the partial dictionary is a d-pad like any other (and the item with a number in it is the only failure).
        #expect(throws: (any Error).self) { try Self.decode(json, []) }
    }

    // MARK: - keepsItemAssets

    @Test("keepsItemAssets: Manic per-item art is kept; a malformed asset invalidates the item")
    func keepsAssets() throws {
        let json = Self.portrait("""
        "items":[
          {"inputs":["a"],"frame":[0,0,1,1],"asset":{"normal":"btn-a.pdf"}},
          {"inputs":["b"],"frame":[0,0,1,1],"asset":{"normal":3}},
          {"inputs":["c"],"frame":[0,0,1,1]}]
        """)
        let kept = try Self.items(json, [.dropsInvalidElements, .keepsItemAssets])
        #expect(Self.inputs(kept) == [["a"], ["c"]])
        #expect(kept[0].asset == DeltaSkin.ItemAsset(normal: "btn-a.pdf"))
        #expect(kept[1].asset == nil)
        // Off: the key is ignored, whatever it holds.
        let ignored = try Self.items(json, [])
        #expect(ignored.count == 3 && ignored.allSatisfy { $0.asset == nil })
        // It round-trips when present.
        let encoded = try JSONEncoder().encode(kept[0])
        #expect(String(decoding: encoded, as: UTF8.self).contains("btn-a.pdf"))
    }

    // MARK: - canonicalGameTypes

    @Test("canonicalGameTypes: gcn, nintendogamecube and separator spellings are refused; the canonical ones are not")
    func canonicalGameTypes() throws {
        func decode(_ id: String, _ options: Options) throws -> DeltaSkinGameType {
            try Self.decode(Self.portrait(#""items":[]"#).replacingOccurrences(of: Self.ngc, with: id), options).gameTypeIdentifier
        }
        for refused in ["com.example.game.gcn", "com.example.game.NintendoGameCube", "com.example.game.game-cube", "com.example.game.game_cube", "com.example.game.sega cd"] {
            #expect(throws: DeltaSkinInfoError.unsupportedGameType(refused)) { try decode(refused, .canonicalGameTypes) }
        }
        for (accepted, type) in [("public.aoshuang.game.ngc", DeltaSkinGameType.gamecube), ("com.rileytestut.delta.game.GC", .gamecube),
                                 ("gamecube", .gamecube), ("com.rileytestut.delta.game.wii", .wii), ("com.rileytestut.delta.game.n64", .n64)] {
            #expect(try decode(accepted, .canonicalGameTypes) == type)
        }
        // Off: every alias is accepted, as before.
        #expect(try decode("com.example.game.gcn", []) == .gamecube)
        #expect(try decode("com.example.game.nintendogamecube", []) == .gamecube)
        #expect(try decode("com.example.game.game-cube", []) == .gamecube)
    }

    // MARK: - Game overrides and unknown devices

    /// A skin whose base layout is fine and whose per-game layout for "Crazy Taxi" holds the items in `overrideItems`.
    static func skinWithOverride(_ overrideItems: String, rep: String = #""extendedEdges":{"left":7},"#) -> String {
        #"""
        {"name":"N","identifier":"x","gameTypeIdentifier":"public.aoshuang.game.ngc",
         "representations":{"iphone":{"standard":{"portrait":{"mappingSize":{"width":10,"height":20},"items":[{"inputs":["a"],"frame":[0,0,1,1]}]}}}},
         "gameOverrides":{"Crazy Taxi":{"iphone":{"standard":{"portrait":{\#(rep)"mappingSize":{"width":10,"height":20},"items":\#(overrideItems)}}}}}}
        """#
    }

    static func overrideItems(_ json: String, _ options: Options) throws -> [DeltaSkin.ItemRepresentation] {
        let info = try decode(json, options)
        return info.gameOverrides?["Crazy Taxi"]?["iphone"]?.standard?["portrait"]?.items ?? []
    }

    @Test("Game overrides get the same rules as the base layout")
    func overridesAreCleaned() throws {
        let items = #"""
        [{"inputs":["huge"],"frame":[0,0,1e308,1]},
         {"inputs":{"up":"up","down":"down","left":"left"},"frame":[0,0,1,1]},
         {"inputs":["art"],"frame":[0,0,1,1],"asset":{"normal":3}},
         {"inputs":["a"],"frame":[1,2,3,4],"asset":{"normal":"a.pdf"}}]
        """#
        let json = Self.skinWithOverride(items)
        // Lenient: the bad items go (limits, complete d-pads, a malformed asset), the good one keeps its art and
        // inherits the override representation's edges.
        let kept = try Self.overrideItems(json, .lenient)
        #expect(Self.inputs(kept) == [["a"]])
        #expect(kept[0].asset?.normal == "a.pdf")
        #expect(kept[0].extendedEdges == DeltaSkinEdgeInsets(top: 0, left: 7, bottom: 0, right: 0))
        // The cleaned override is what `representation(for:)` selects for that game.
        let url = try Self.directory(json)
        let skin = try DeltaSkin(fileURL: url, options: .lenient)
        let traits = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .portrait, gameIdentifier: "Crazy Taxi")
        #expect(skin.representation(for: traits)?.items?.count == 1)
        // The rules are the same individual options: without dropsInvalidElements a bad override item is an error.
        #expect(throws: DeltaSkinError.self) { try Self.decode(json, .limitsFrames) }
        // Default: untouched, as always (the huge frame and the partial d-pad are kept; the asset is not read).
        let plain = try Self.overrideItems(Self.skinWithOverride(#"[{"inputs":["huge"],"frame":[0,0,1e308,1]},{"inputs":{"up":"up","down":"down","left":"left"},"frame":[0,0,1,1]},{"inputs":["a"],"frame":[1,2,3,4],"asset":{"normal":"a.pdf"}}]"#), [])
        #expect(plain.count == 3 && plain[0].frame.width == 1e308 && plain[2].asset == nil)
        #expect(plain[2].extendedEdges == nil)
    }

    @Test("Game overrides: wrong shapes are dropped, and an emptied game or device disappears")
    func overrideShapes() throws {
        func overrides(_ body: String, _ options: Options) throws -> [String: [String: DeltaSkin.DeviceRepresentations]]? {
            let json = #"""
            {"name":"N","identifier":"x","gameTypeIdentifier":"public.aoshuang.game.ngc",
             "representations":{"iphone":{"standard":{"portrait":{"mappingSize":{"width":10,"height":20}}}}},
             "gameOverrides":\#(body)}
            """#
            return try Self.decode(json, options).gameOverrides
        }
        #expect(try overrides(#"[1,2]"#, .dropsInvalidElements) == nil)
        #expect(throws: DeltaSkinError.self) { try overrides(#"[1,2]"#, .limitsFrames) }
        #expect(try overrides(#"{"G":"nope"}"#, .dropsInvalidElements)?.isEmpty == true)
        #expect(try overrides(#"{"G":{"iphone":{"standard":{"portrait":{"items":[]}}}}}"#, .dropsInvalidElements)?.isEmpty == true,
                "an override whose only representation is invalid leaves no game behind")
        #expect(try overrides(#"{"G":{"iphone":{"standard":{"portrait":{"mappingSize":{"width":4,"height":5}}}}}}"#, .lenient)?["G"]?["iphone"] != nil)
    }

    @Test("dropsInvalidElements counts recognised devices: an unknown device cannot make an unusable skin look usable")
    func unknownDevicesDoNotCount() throws {
        let json = #"""
        {"name":"N","identifier":"x","gameTypeIdentifier":"public.aoshuang.game.ngc",
         "representations":{"iphone":{"standard":{"portrait":{"items":[]}}},
                            "appletv9":{"standard":{"portrait":{"mappingSize":{"width":10,"height":20}}}}}}
        """#
        #expect(throws: DeltaSkinInfoError.noUsableRepresentation) { try Self.decode(json, .dropsInvalidElements) }
        #expect(throws: DeltaSkinInfoError.noUsableRepresentation) { try Self.decode(json, .lenient) }
        // A usable recognised device alongside the unknown one still loads.
        let usable = json.replacingOccurrences(of: #""items":[]"#, with: #""mappingSize":{"width":1,"height":1}"#)
        #expect(try Self.decode(usable, .lenient).representations[.iphone] != nil)
        // Default: the unknown device is ignored and the skin decodes with whatever it can read (no representations here).
        #expect(throws: (any Error).self) { try Self.decode(json, []) }
    }

    // MARK: - The presets and the whole of it

    @Test("lenient is every option; the maximum magnitude is 100,000")
    func presets() {
        let all: [Options] = [.stripsComments, .dropsInvalidElements, .limitsFrames, .inheritsEdges,
                              .requiresCompleteDirections, .keepsItemAssets, .canonicalGameTypes]
        #expect(Options.lenient == Options(all))
        #expect(Set(all.map(\.rawValue)).count == all.count, "each option is its own bit")
        #expect(Options.maxFrameMagnitude == 100_000)
    }

    @Test("TestCube: iCube's fixture decodes under lenient with comments, inherited edges and per-item art")
    func iCubeFixture() throws {
        let json = """
        // Hand-written test skin: no third-party art.
        {
          "name": "Test Cube", "identifier": "com.joemattiello.icube.testcube", "gameTypeIdentifier": "public.aoshuang.game.ngc",
          "representations": { "iphone": { "edgeToEdge": { "portrait": {
            "assets": { "resizable": "bg.png" }, "mappingSize": { "width": 390, "height": 844 },
            "extendedEdges": { "top": 5, "bottom": 5, "left": 5, "right": 5 }, "translucent": true,
            "screens": [ { "outputFrame": { "x": 0, "y": 60, "width": 390, "height": 292 } } ],
            "items": [
              { "inputs": ["a"], "frame": { "x": 300, "y": 500, "width": 60, "height": 60 }, "extendedEdges": { "left": 20 }, "asset": { "normal": "btn-a.pdf" } },
              { "inputs": ["x", "y"], "frame": { "x": 250, "y": 440, "width": 60, "height": 60 } },
              { "inputs": { "up": "rightThumbstickUp", "down": "rightThumbstickDown", "left": "rightThumbstickLeft", "right": "rightThumbstickRight" },
                "frame": { "x": 220, "y": 600, "width": 140, "height": 140 }, "thumbstick": { "name": "stick.pdf", "width": 60, "height": 60 } }
            ] } } } }
        }
        """
        let url = try Self.directory(json)
        let skin = try DeltaSkin(fileURL: url, options: .lenient)
        let traits = DeltaSkinTraits(device: .iphone, displayType: .edgeToEdge, orientation: .portrait)
        let rep = try #require(skin.representation(for: traits))
        let items = try #require(rep.items)
        #expect(rep.mappingSize == CGSize(width: 390, height: 844))
        #expect(items[0].extendedEdges == DeltaSkinEdgeInsets(top: 5, left: 20, bottom: 5, right: 5))
        #expect(items[1].extendedEdges == DeltaSkinEdgeInsets(top: 5, left: 5, bottom: 5, right: 5))
        #expect(items[0].asset?.normal == "btn-a.pdf")
        #expect(items[2].thumbstick?.name == "stick.pdf")
        #expect(skin.gameType == .gamecube)
    }

    @Test("Every shipped fixture reads the same under lenient as by default (frames, inputs, screens)")
    func shippedSkinsAreUnchanged() throws {
        let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let skins = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "deltaskin" }
        #expect(skins.count > 20)
        for url in skins {
            let plain = try? DeltaSkin(fileURL: url)
            // DS-Test carries `//` comments, which the default path cannot read.
            guard let plain else { _ = try DeltaSkin(fileURL: url, options: .lenient); continue }
            let lenient = try DeltaSkin(fileURL: url, options: .lenient)
            for device in [DeltaSkinDevice.iphone, .ipad] {
                for display in [DeltaSkinDisplayType.standard, .edgeToEdge] {
                    for orientation in [DeltaSkinOrientation.portrait, .landscape] {
                        let traits = DeltaSkinTraits(device: device, displayType: display, orientation: orientation)
                        let before = plain.representation(for: traits)
                        let after = lenient.representation(for: traits)
                        #expect((before == nil) == (after == nil), "\(url.lastPathComponent) \(traits)")
                        #expect(before?.mappingSize == after?.mappingSize)
                        #expect(before?.items?.map(\.frame) == after?.items?.map(\.frame), "\(url.lastPathComponent) \(traits)")
                        #expect(before?.screens?.map(\.outputFrame) == after?.screens?.map(\.outputFrame))
                        #expect(inputs(before) == inputs(after))
                    }
                }
            }
        }
    }

    private func inputs(_ rep: DeltaSkin.RepresentationInfo?) -> [String]? {
        rep?.items?.map {
            switch $0.inputs {
            case let .single(names): return names.joined(separator: ",")
            case let .directional(map): return map.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            }
        }
    }

    @Test("Options apply to an archive as well as a directory")
    func archive() throws {
        let dir = try Self.directory("// c\n" + Self.portrait(#""items":[{"inputs":["x"],"frame":"bad"},{"inputs":["a"],"frame":[1,2,3,4]}]"#))
        let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent("opts-\(UUID().uuidString).deltaskin")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(with: "info.json", relativeTo: dir)
        let skin = try DeltaSkin(fileURL: archiveURL, options: .lenient)
        let traits = DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .portrait)
        #expect(skin.representation(for: traits)?.items?.count == 1)
        #expect(throws: (any Error).self) { try DeltaSkin(fileURL: archiveURL) }
    }
}
