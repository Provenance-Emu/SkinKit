//
//  TVBezel.swift
//  SkinKitBezels
//
//  The TVs that can surround the game picture on an external display.
//

import CoreGraphics
import Foundation

/// One TV: a cabinet and room drawn from a format 2 skin document, the look of its frame and
/// glass, and the tube look it suggests. Or a picture with a hole in it: a bezel the player
/// imported or downloaded, laid plainly over the game.
///
/// A TV is data. The bundled ones live in the package's `Resources/TVBezels`: `catalog.json`
/// lists them and each names a skin document beside it. The player's own live in `TVBezelLibrary`.
public struct TVBezel: Decodable, Identifiable, Equatable, Sendable {

    /// A bezel that is one image with a see-through screen.
    public struct ImageArtwork: Equatable, Sendable {
        public let fileURL: URL
        /// The image's size in pixels.
        public let size: CGSize
        /// The see-through screen in the image's pixels, origin at the top left.
        public let screen: CGRect

        public init(fileURL: URL, size: CGSize, screen: CGRect) {
            self.fileURL = fileURL
            self.size = size
            self.screen = screen
        }
    }

    /// Where a TV came from.
    @frozen public enum Source: String, Codable, Sendable {
        case builtIn
        /// A file the player brought in.
        case imported
        /// Downloaded from The Bezel Project.
        case bezelProject
    }

    /// A filter and the values it runs with: the tube look a TV suggests.
    public struct Look: Decodable, Equatable, Sendable {
        /// A filter's id: `slang:crt/crt-geom` for a library preset, or an app's own
        /// (`native:…` in Provenance). An app that does not know the id shows clean pixels.
        public let shader: String
        public let values: [String: Float]

        private enum CodingKeys: String, CodingKey { case shader, values }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            shader = try container.decode(String.self, forKey: .shader)
            values = try container.decodeIfPresent([String: Float].self, forKey: .values) ?? [:]
        }
    }

    /// The stored value of `BezelSettingsStore.chosenBezel`.
    public let id: String
    public let name: String
    /// System identifiers this TV is the natural screen for (`BezelEnvironment.System` ids).
    public let preferredSystems: [String]
    /// Parameters of the bezel preset: frame colour and widths, corner radius, curvature,
    /// reflection strength. The tube's place and shape come from the artwork, not from here.
    public let frame: [String: Float]
    /// The tube look used until the player picks a filter for the external display.
    public let look: Look?
    /// The picture may light this TV's room (`TVBezelShader.ambientID`). Off for a TV that
    /// looks wrong or runs too slowly with it.
    public let lightsRoom: Bool
    /// File name of the format 2 skin document that draws the cabinet and the room. Empty for
    /// an image bezel.
    public let artwork: String
    /// The image of a bezel the player imported or downloaded; `nil` for a built-in TV.
    public let image: ImageArtwork?
    /// A standalone shader that draws its own cabinet and screen: a preset id
    /// (`TVBezelShader.presetID(libraryPath:)`), which is also this TV's `id`.
    public let presetID: String?
    public let source: Source
    /// Shown in the picker. Artwork fetched for a single game is on the device without
    /// being listed.
    public let isListed: Bool
    /// The artwork document has a portrait form: on a portrait canvas
    /// (`TVBezelCanvas.portraitSize(display:seat:)`) it puts the TV at the top and carries
    /// the room down to the bottom. Always false for an image bezel.
    public let drawsPortrait: Bool

    private enum CodingKeys: String, CodingKey { case id, name, preferredSystems, frame, look, lightsRoom, artwork, portrait }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        preferredSystems = try container.decodeIfPresent([String].self, forKey: .preferredSystems) ?? []
        frame = try container.decodeIfPresent([String: Float].self, forKey: .frame) ?? [:]
        look = try container.decodeIfPresent(Look.self, forKey: .look)
        lightsRoom = try container.decodeIfPresent(Bool.self, forKey: .lightsRoom) ?? true
        artwork = try container.decode(String.self, forKey: .artwork)
        image = nil
        presetID = nil
        source = .builtIn
        isListed = true
        drawsPortrait = try container.decodeIfPresent(Bool.self, forKey: .portrait) ?? false
    }

    /// A bundled shader bezel that was checked with its own artwork.
    public init(presetID: String, name: String) {
        id = presetID
        self.name = name
        preferredSystems = []
        frame = [:]
        look = nil
        lightsRoom = false
        artwork = ""
        image = nil
        self.presetID = presetID
        source = .builtIn
        isListed = true
        drawsPortrait = false
    }

    /// An image bezel.
    public init(id: String, name: String, preferredSystems: [String], image: ImageArtwork, source: Source, isListed: Bool) {
        self.id = id
        self.name = name
        self.preferredSystems = preferredSystems
        frame = [:]
        look = nil
        lightsRoom = false
        artwork = ""
        self.image = image
        presetID = nil
        self.source = source
        self.isListed = isListed
        drawsPortrait = false
    }
}

/// The TVs that ship with the app.
@frozen public enum TVBezelCatalog {
    /// Folder of the catalogue inside the package's bundle.
    static let folderName = "TVBezels"
    static let catalogFileName = "catalog.json"

    private struct File: Decodable {
        let bezels: [TVBezel]
    }

    /// The bundled catalogue's folder, or `nil` when the resources are missing.
    public static var folderURL: URL? {
        Bundle.module.url(forResource: folderName, withExtension: nil)
    }

    /// Decodes a catalogue file.
    public static func decode(_ data: Data) throws -> [TVBezel] {
        try JSONDecoder().decode(File.self, from: data).bezels
    }

    /// Every bundled TV, in the order the picker shows them. Empty when the catalogue cannot
    /// be read, which leaves the picture alone on the display.
    public static let bundled: [TVBezel] = {
        guard let url = folderURL?.appendingPathComponent(catalogFileName) else {
            BezelLog.error("TV bezels: no catalogue in the bundle")
            return []
        }
        do {
            return try decode(Data(contentsOf: url))
        } catch {
            BezelLog.error("TV bezels: could not read the catalogue: \(error)")
            return []
        }
    }()

    /// Standalone presets that showed a usable picture and frame at both preview sizes and at 1080p.
    private static let checkedShaderPresets: [(path: String, name: String)] = [
        ("bezel/uborder/uborder-bezel-reflections", "uBorder Reflections"),
        ("bezel/uborder/uborder-koko-ambi", "uBorder Ambient"),
        ("bezel/uborder/base_presets/uborder-bezel-reflections/crt/crt-geom", "uBorder CRT Geom"),
        ("bezel/uborder/base_presets/uborder-bezel-reflections/crt/phosphor-persistence", "uBorder Phosphor Persistence"),
        ("bezel/uborder/base_presets/uborder-bezel-reflections/vector/uborder-bezel-reflections-vector", "uBorder Vector"),
        ("bezel/uborder/base_presets/uborder-koko-ambi/crt/crt-geom", "uBorder Ambient CRT Geom")
    ]

    /// The checked standalone presets the app's shader library has
    /// (`BezelEnvironment.hasShaderPreset`): none in an app without a slang runtime.
    public static let shaderPresets: [TVBezel] = {
        let hasPreset = BezelEnvironment.current.hasShaderPreset
        return checkedShaderPresets
            .map { TVBezel(presetID: TVBezelShader.presetID(libraryPath: $0.path), name: $0.name) }
            .filter { hasPreset($0.id) }
    }()

    /// Every TV on the device, including artwork fetched for a single game.
    public static var all: [TVBezel] { bundled + shaderPresets + TVBezelLibrary.shared.bezels }

    public static func bezel(id: String) -> TVBezel? {
        bundled.first { $0.id == id }
            ?? shaderPresets.first { $0.id == id }
            ?? TVBezelLibrary.shared.bezel(id: id)
    }

    /// The catalogue as the selection rules see it. Only a TV shown in the picker can stand
    /// for a system.
    public static var candidates: [ExternalDisplayBezelRules.Candidate] {
        all.map {
            .init(id: $0.id, preferredSystems: $0.isListed ? Set($0.preferredSystems) : [], isUserAdded: $0.source != .builtIn)
        }
    }

    /// What the selection rules decide for a game from the given settings, and the TV to show
    /// (`nil` for the picture alone).
    ///
    /// - Parameters:
    ///   - systemSuitsTV: the system was played on a TV or monitor (see `ExternalDisplayBezelRules.resolve`).
    ///   - pinned: the TV pinned to the game.
    ///   - gameArt: artwork for the game that is on the device, when game artwork is wanted.
    public static func resolve(chosen: String, matchesSystem: Bool, systemID: String?, systemSuitsTV: Bool,
                               pinned: String? = nil, gameArt: String? = nil)
        -> (resolution: ExternalDisplayBezelRules.Resolution, bezel: TVBezel?) {
        let resolution = ExternalDisplayBezelRules.resolve(chosen: chosen, matchesSystem: matchesSystem,
                                                           systemID: systemID, systemSuitsTV: systemSuitsTV,
                                                           candidates: candidates, pinned: pinned, gameArt: gameArt)
        return (resolution, resolution.bezelID.flatMap(bezel(id:)))
    }
}
