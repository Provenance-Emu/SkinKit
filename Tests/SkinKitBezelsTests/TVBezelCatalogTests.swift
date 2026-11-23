//
//  TVBezelCatalogTests.swift
//  SkinKitBezels
//
//  The TVs that ship with the app: the catalogue file and each TV's artwork.
//

import CoreGraphics
import Foundation
import Testing
@testable import SkinKitBezels

@Suite("TVBezelCatalog")
struct TVBezelCatalogTests {

    private let bezels = TVBezelCatalog.bundled

    @Test("The bundled catalogue has TVs with distinct ids, none of them the 'no TV' value")
    func catalogueDecodes() {
        #expect(!bezels.isEmpty)
        #expect(Set(bezels.map(\.id)).count == bezels.count)
        #expect(!bezels.contains { $0.id == ExternalDisplayBezelRules.noBezelID })
        #expect(!bezels.contains { $0.name.isEmpty })
    }

    @Test("Preferred systems are system identifiers, and no two TVs claim the same one")
    func preferredSystems() {
        var claimed: Set<String> = []
        for bezel in bezels {
            for system in bezel.preferredSystems {
                #expect(system.hasPrefix("com.provenance."), "\(bezel.id) lists \(system), which is not a system identifier")
                #expect(claimed.insert(system).inserted, "\(system) is claimed by two TVs")
            }
        }
    }

    @Test("Every TV's own look names a filter by a well-formed id")
    func looks() throws {
        for bezel in bezels {
            guard let look = bezel.look else { continue }
            let path = try #require(TVBezelShader.libraryPath(ofPresetID: look.shader), "\(bezel.id): '\(look.shader)' is not a preset id")
            #expect(!path.isEmpty)
            // A TV cannot suggest a filter that brings a frame of its own.
            #expect(!path.hasPrefix("bezel/") && !path.hasPrefix("border/"))
        }
    }

    @Test("A TV cannot place or shape its tube through the frame's values")
    func frameValuesLeaveGeometryAlone() {
        let geometry = Set(TVBezelShader.geometryValues(tubeAspect: 1, tubeHeightFraction: 1).keys)
        for bezel in bezels {
            #expect(geometry.isDisjoint(with: bezel.frame.keys), "\(bezel.id) sets tube geometry in its frame values")
        }
    }

    @Test("Every TV's artwork loads, with one centred 4:3 tube that leaves room for a cabinet")
    func artwork() throws {
        for bezel in bezels {
            let artwork = try TVBezelArtwork(bezel: bezel)
            let tube = artwork.tubeRect
            let canvas = TVBezelArtwork.canvas
            #expect(abs(tube.midX - canvas.width / 2) < 0.5, "\(bezel.id): tube is not centred across")
            #expect(abs(tube.midY - canvas.height / 2) < 0.5, "\(bezel.id): tube is not centred down")
            #expect(abs(artwork.tubeAspect - 4.0 / 3.0) < 0.001, "\(bezel.id): tube is not 4:3")
            #expect(artwork.tubeHeightFraction > 0.4 && artwork.tubeHeightFraction < 0.9)
        }
    }

    /// Displays at the ends and the middle of the supported range.
    private static let shapes = [CGSize(width: 4, height: 3), CGSize(width: 16, height: 9), CGSize(width: 12, height: 5)]
    /// Each built-in TV's cabinet node and the floor it stands on.
    private static let furniture = ["living-room-tv": (cabinet: "cabinet", floor: "carpet"),
                                    "studio-monitor": (cabinet: "body", floor: "shelf"),
                                    "computer-monitor": (cabinet: "case", floor: "desk"),
                                    "flat-tube-tv": (cabinet: "cabinet", floor: "floor"),
                                    "dorm-tv": (cabinet: "cabinet", floor: "desk"),
                                    "vga-monitor": (cabinet: "case", floor: "desk")]

    @Test("Every built-in TV keeps a centred tube of one size at every shape, inside the canvas")
    func tubeAcrossShapes() throws {
        for bezel in bezels where bezel.presetID == nil {
            for seat in TVBezelSeat.allCases {
                var sizes = Set<String>()
                for shape in Self.shapes {
                    let canvas = TVBezelCanvas.size(display: shape, seat: seat)
                    let tube = try TVBezelArtwork(bezel: bezel, canvas: canvas).tubeRect
                    let where_ = Comment(rawValue: "\(bezel.id) \(seat) \(shape)")
                    #expect(abs(tube.midX - canvas.width / 2) < 0.5 && abs(tube.midY - canvas.height / 2) < 0.5, where_)
                    #expect(CGRect(origin: .zero, size: canvas).contains(tube), where_)
                    sizes.insert("\(Int(tube.width))x\(Int(tube.height))")
                }
                #expect(sizes.count == 1, "\(bezel.id) \(seat): \(sizes)")
            }
        }
    }

    @Test("From the back at 16:9 the tubes are where they were")
    func backSixteenNineUnchanged() throws {
        let expected = ["living-room-tv": CGRect(x: 480, y: 180, width: 960, height: 720),
                        "studio-monitor": CGRect(x: 456, y: 162, width: 1008, height: 756),
                        "computer-monitor": CGRect(x: 456, y: 162, width: 1008, height: 756),
                        "flat-tube-tv": CGRect(x: 440, y: 150, width: 1040, height: 780),
                        "dorm-tv": CGRect(x: 480, y: 180, width: 960, height: 720),
                        "vga-monitor": CGRect(x: 432, y: 144, width: 1056, height: 792),
                        "candy-cabinet": CGRect(x: 440, y: 150, width: 1040, height: 780)]
        for (id, tube) in expected {
            let bezel = try #require(TVBezelCatalog.bezel(id: id))
            #expect(try TVBezelArtwork(bezel: bezel).tubeRect == tube, "\(id)")
        }
    }

    @Test("From the back the cabinet fits every shape with wall beside it, on a floor as wide as the canvas")
    func cabinetFits() throws {
        for (id, nodes) in Self.furniture {
            let bezel = try #require(TVBezelCatalog.bezel(id: id))
            for shape in Self.shapes {
                let canvas = TVBezelCanvas.size(display: shape)
                let artwork = try TVBezelArtwork(bezel: bezel, canvas: canvas)
                let where_ = Comment(rawValue: "\(id) \(shape)")
                let cabinet = try #require(artwork.frame(ofNode: nodes.cabinet), where_)
                #expect(cabinet.minX >= 20 && cabinet.maxX <= canvas.width - 20, where_)
                #expect(abs(cabinet.midX - canvas.width / 2) < 0.5, where_)
                let floor = try #require(artwork.frame(ofNode: nodes.floor), where_)
                #expect(floor.minX <= 0 && floor.maxX >= canvas.width, where_)
                #expect(floor.minY < cabinet.maxY + 80 && floor.maxY >= canvas.height, where_)
            }
        }
    }

    @Test("The Living Room TV has its speakers only where they fit")
    func livingRoomSpeakers() throws {
        let bezel = try #require(TVBezelCatalog.bezel(id: "living-room-tv"))
        let narrow = try TVBezelArtwork(bezel: bezel, canvas: TVBezelCanvas.size(display: CGSize(width: 4, height: 3)))
        #expect(narrow.frame(ofNode: "cloth-left") == nil && narrow.frame(ofNode: "cloth-right") == nil)
        let wide = try TVBezelArtwork(bezel: bezel)
        #expect(wide.frame(ofNode: "cloth-left") == CGRect(x: 186, y: 138, width: 252, height: 806))
        #expect(wide.frame(ofNode: "cabinet") == CGRect(x: 150, y: 84, width: 1620, height: 922))
        let flat = try #require(TVBezelCatalog.bezel(id: "flat-tube-tv"))
        #expect(try TVBezelArtwork(bezel: flat, canvas: narrow.canvasSize).frame(ofNode: "speaker-left") == nil)
        #expect(try TVBezelArtwork(bezel: flat).frame(ofNode: "cabinet") == CGRect(x: 196, y: 80, width: 1528, height: 912))
    }

    @Test("Artwork drawn for a canvas has that canvas's proportions")
    func artworkImageProportions() throws {
        let bezel = try #require(TVBezelCatalog.bezel(id: "studio-monitor"))
        let artwork = try TVBezelArtwork(bezel: bezel, canvas: CGSize(width: 1440, height: 1080))
        let image = try #require(artwork.image(pixelWidth: 480))
        #expect(image.width == 480 && image.height == 360)
        #expect(artwork.tubeHeightOverCanvasWidth == artwork.tubeRect.height / 1440)
    }

    @Test("Artwork renders at the size asked for")
    func artworkRenders() throws {
        let bezel = try #require(bezels.first)
        let artwork = try TVBezelArtwork(bezel: bezel)
        let image = try #require(artwork.image(pixelWidth: 480))
        #expect(image.width == 480 && image.height == 270)
        #expect(artwork.image(pixelWidth: 0) == nil)
        let png = try #require(artwork.pngData(pixelWidth: 480))
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test("A document needs exactly one screen to be a TV")
    func artworkScreenCount() {
        func document(screens: Int) -> Data {
            let nodes = (0 ..< screens).map { #"{"type":"screen","id":"s\#($0)","layout":{"frame":[\#($0 * 10),0,8,6]}}"# }
            let json = #"{"formatVersion":"2.0","requires":[],"identifier":"t","name":"t","gameTypes":["t"],"#
                + #""reference":{"shortSide":1080,"minScale":1,"maxScale":1},"#
                + #""root":{"type":"group","id":"root","children":[\#(nodes.joined(separator: ","))]}}"#
            return Data(json.utf8)
        }
        #expect(throws: TVBezelArtwork.ArtworkError.screenCount(0)) { try TVBezelArtwork(data: document(screens: 0)) }
        #expect(throws: TVBezelArtwork.ArtworkError.screenCount(2)) { try TVBezelArtwork(data: document(screens: 2)) }
        #expect(throws: Never.self) { try TVBezelArtwork(data: document(screens: 1)) }
    }

    @Test("The catalogue resolves the stored choice through the selection rules")
    func resolvesChoice() throws {
        let first = try #require(bezels.first)
        func tv(_ chosen: String, matches: Bool) -> TVBezel? {
            TVBezelCatalog.resolve(chosen: chosen, matchesSystem: matches, systemID: nil, systemSuitsTV: true).bezel
        }
        #expect(tv(first.id, matches: false) == first)
        #expect(tv(ExternalDisplayBezelRules.noBezelID, matches: true) == nil)
        #expect(tv("not-a-tv", matches: true) == nil)
    }

    @Test("The catalogue holds the TV Automatic falls back to")
    func automaticDefaultExists() {
        #expect(TVBezelCatalog.bezel(id: ExternalDisplayBezelRules.automaticDefaultBezelID) != nil)
        let console = TVBezelCatalog.resolve(chosen: ExternalDisplayBezelRules.automaticBezelID, matchesSystem: true,
                                             systemID: "com.provenance.snes", systemSuitsTV: true)
        #expect(console.bezel?.id == "living-room-tv")
        #expect(console.resolution.isAutomatic)
        let handheld = TVBezelCatalog.resolve(chosen: ExternalDisplayBezelRules.automaticBezelID, matchesSystem: true,
                                              systemID: "com.provenance.gba", systemSuitsTV: false)
        #expect(handheld.bezel == nil)
        #expect(handheld.resolution.outcome == .noneForSystem)
    }

    @Test("Automatic gives a Dreamcast-era console the flat-tube TV and an arcade board the cabinet")
    func eraDefaults() {
        func automatic(_ system: String) -> String? {
            TVBezelCatalog.resolve(chosen: ExternalDisplayBezelRules.automaticBezelID, matchesSystem: true,
                                   systemID: system, systemSuitsTV: true).bezel?.id
        }
        for system in ["com.provenance.dreamcast", "com.provenance.ps2", "com.provenance.gamecube"] {
            #expect(automatic(system) == "flat-tube-tv", "\(system)")
        }
        for system in ["com.provenance.naomi", "com.provenance.naomi2", "com.provenance.atomiswave"] {
            #expect(automatic(system) == "candy-cabinet", "\(system)")
        }
        // The two that no system asks for are still there to choose.
        #expect(TVBezelCatalog.bezel(id: "dorm-tv") != nil)
        #expect(TVBezelCatalog.bezel(id: "vga-monitor") != nil)
    }

    @Test("Every bundled TV's artwork renders")
    func everyArtworkRenders() throws {
        for bezel in bezels {
            let image = try #require(try TVBezelArtwork(bezel: bezel).image(pixelWidth: 320), "\(bezel.id)")
            #expect(image.width == 320 && image.height == 180)
        }
    }

    @Test("A catalogue entry needs only an id, a name and artwork")
    func decodesMinimalEntry() throws {
        let data = Data(#"{"bezels":[{"id":"a","name":"A","artwork":"a.skin.json"}]}"#.utf8)
        let bezel = try #require(try TVBezelCatalog.decode(data).first)
        #expect(bezel.lightsRoom)
        #expect(bezel.look == nil)
        #expect(bezel.frame.isEmpty && bezel.preferredSystems.isEmpty)
    }
}
