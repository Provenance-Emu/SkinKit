import Foundation
import Testing
import ZIPFoundation
import SkinKitCore
@testable import SkinKitRetroArch

@Suite("RetroArch overlay exporter")
struct RetroArchExporterTests {

    /// A scratch directory per test, removed afterwards by the caller's `defer`.
    private static func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SkinKitRetroArchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// An unpacked skin: the fixture's `info.json` and stand-in artwork files with the given names.
    private static func skinFolder(in root: URL, info: String, assets: [String]) throws -> URL {
        let folder = root.appendingPathComponent("\(info).deltaskin", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Fixture.infoData(info).write(to: folder.appendingPathComponent("info.json"))
        for asset in assets {
            let file = folder.appendingPathComponent(asset)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("art:\(asset)".utf8).write(to: file)
        }
        return folder
    }

    private static let fakePNG = Data([0x89, 0x50, 0x4E, 0x47])

    @Test("Converting a loaded skin gives the same cfg as converting its info.json")
    func convertSkin() throws {
        let root = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try Self.skinFolder(in: root, info: "backbone-gba", assets: ["controller.svg"])
        let skin = try DeltaSkin(fileURL: folder, options: .lenient)
        let converter = try RetroArchConverter.bundled()

        let fromSkin = converter.convert(skin: skin)
        #expect(fromSkin.cfg == (try Fixture.expectedText("backbone-gba", "cfg")))
        #expect(fromSkin.readme == (try Fixture.expectedText("backbone-gba", "README.txt")))
        #expect(RetroArchSkinInfo(skin: skin).gameTypeIdentifier == "com.rileytestut.delta.game.gba")
    }

    @Test("A skin folder becomes <name>/<name>.cfg, README.txt and one PNG per image")
    func exportsFolder() throws {
        let root = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try Self.skinFolder(in: root, info: "n64-comments", assets: ["Landscape.pdf", "Portrait.pdf", "PortraitAlt.pdf", "Art/thumb.pdf"])
        let skin = try DeltaSkin(fileURL: folder, options: .lenient)

        var requests: [RetroArchImageRequest] = []
        let out = root.appendingPathComponent("out", isDirectory: true)
        let export = try RetroArchOverlayExporter.export(skin: skin, into: out) { request in
            requests.append(request)
            return Self.fakePNG
        }

        #expect(export.folder.lastPathComponent == "N64_Comments_Test")
        #expect(export.folder.deletingLastPathComponent().standardizedFileURL == out.standardizedFileURL)
        let files = try FileManager.default.contentsOfDirectory(atPath: export.folder.path).sorted()
        let expectedImages = export.conversion.images.map(\.file)
        #expect(files == (expectedImages + ["N64_Comments_Test.cfg", "README.txt"]).sorted())
        #expect(try String(contentsOf: export.folder.appendingPathComponent("N64_Comments_Test.cfg"), encoding: .utf8)
                == (try Fixture.expectedText("n64-comments", "cfg")))
        #expect(try String(contentsOf: export.folder.appendingPathComponent("README.txt"), encoding: .utf8)
                == (try Fixture.expectedText("n64-comments", "README.txt")))
        for file in expectedImages {
            #expect(try Data(contentsOf: export.folder.appendingPathComponent(file)) == Self.fakePNG)
        }

        // One request per image, artwork resolved case-insensitively out of the folder.
        #expect(requests.map(\.file) == expectedImages)
        let thumb = try #require(requests.first { $0.kind == .thumbstick })
        #expect(thumb.assetName == "Art/thumb.pdf")
        #expect(String(decoding: thumb.assetData, as: UTF8.self) == "art:Art/thumb.pdf")
        #expect(thumb.fileExtension == "pdf")
        #expect(thumb.pixelWidth == 200 && thumb.pixelHeight == 200 && thumb.pixelsPerPoint == 2)
        #expect(thumb.innerWidth == 60 && thumb.innerHeight == 60)
        let landscape = try #require(requests.first { $0.file.hasSuffix("-landscape.png") })
        #expect(landscape.clearRects.count == 1, "the game screen is cleared")
        #expect(landscape.pixelWidth <= 2048 && landscape.pixelHeight <= 2048)
        #expect(Double(landscape.pixelWidth) == (landscape.mappingWidth * landscape.pixelsPerPoint).rounded())
    }

    @Test("Exporting from a .deltaskin archive reads its artwork from the zip")
    func exportsFromArchive() throws {
        let root = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Backbone.deltaskin")
        let archive = try Archive(url: url, accessMode: .create, pathEncoding: nil)
        for (name, data) in [("info.json", try Fixture.infoData("backbone-gba")), ("controller.svg", Data("<svg/>".utf8))] {
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count)) { position, size in
                data.subdata(in: Data.Index(position)..<(Data.Index(position) + size))
            }
        }
        let skin = try DeltaSkin(fileURL: url, options: .lenient)

        var seen: [String] = []
        let export = try RetroArchOverlayExporter.export(skin: skin, into: root.appendingPathComponent("out")) { request in
            seen.append("\(request.assetName)=\(String(decoding: request.assetData, as: UTF8.self))")
            #expect(request.pixelWidth == 1704 && request.pixelHeight == 786)
            return Self.fakePNG
        }
        #expect(seen == ["controller.svg=<svg/>"])
        #expect(export.conversion.cfg == (try Fixture.expectedText("backbone-gba", "cfg")))
    }

    @Test("A layout whose artwork is not in the skin is left out and reported")
    func skipsMissingArtwork() throws {
        let root = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try Self.skinFolder(in: root, info: "n64-comments", assets: ["Portrait.pdf", "PortraitAlt.pdf"])
        let skin = try DeltaSkin(fileURL: folder, options: .lenient)
        let export = try RetroArchOverlayExporter.export(skin: skin, into: root.appendingPathComponent("out")) { _ in Self.fakePNG }
        #expect(export.conversion.preset.overlays.map(\.name) == ["portrait", "portrait-alt"])
        #expect(export.conversion.skipped.map(\.overlayName) == ["landscape"])
    }

    @Test("A skin with no usable artwork throws, with the converter's notes")
    func nothingToConvert() throws {
        let root = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try Self.skinFolder(in: root, info: "backbone-gba", assets: [])
        let skin = try DeltaSkin(fileURL: folder, options: .lenient)
        do {
            _ = try RetroArchOverlayExporter.export(skin: skin, into: root.appendingPathComponent("out")) { _ in Self.fakePNG }
            Issue.record("expected the export to throw")
        } catch RetroArchExportError.nothingToConvert(let notes) {
            #expect(notes.contains { $0.contains("No landscape or portrait layout") })
        }
    }

    @Test("A rasterizer error stops the export and is passed on")
    func rasterizerErrorPropagates() throws {
        struct Boom: Error {}
        let root = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try Self.skinFolder(in: root, info: "backbone-gba", assets: ["controller.svg"])
        let skin = try DeltaSkin(fileURL: folder, options: .lenient)
        #expect(throws: Boom.self) {
            _ = try RetroArchOverlayExporter.export(skin: skin, into: root.appendingPathComponent("out")) { _ in throw Boom() }
        }
    }

    @Test("Exporting again replaces the folder")
    func replacesFolder() throws {
        let root = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try Self.skinFolder(in: root, info: "backbone-gba", assets: ["controller.svg"])
        let skin = try DeltaSkin(fileURL: folder, options: .lenient)
        let out = root.appendingPathComponent("out")
        let first = try RetroArchOverlayExporter.export(skin: skin, into: out) { _ in Self.fakePNG }
        try Data("stale".utf8).write(to: first.folder.appendingPathComponent("stale.txt"))
        let second = try RetroArchOverlayExporter.export(skin: skin, into: out) { _ in Self.fakePNG }
        #expect(second.folder == first.folder)
        #expect(!FileManager.default.fileExists(atPath: second.folder.appendingPathComponent("stale.txt").path))
    }

    @Test("A skin named . or .. exports into its own folder and removes nothing around it", arguments: [".", ".."])
    func dotNamesStayInside(name: String) throws {
        let root = try Self.scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try Self.skinFolder(in: root, info: "backbone-gba", assets: ["controller.svg"])
        let skin = try DeltaSkin(fileURL: folder, options: .lenient)
        let out = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let keepInOut = out.appendingPathComponent("keep.txt")
        let keepInRoot = root.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: keepInOut)
        try Data("keep".utf8).write(to: keepInRoot)

        var options = RetroArchConverter.Options()
        options.name = name
        let export = try RetroArchOverlayExporter.export(skin: skin, options: options, into: out) { _ in Self.fakePNG }
        #expect(export.folder.lastPathComponent == "skin")
        #expect(export.folder.deletingLastPathComponent().standardizedFileURL == out.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: keepInOut.path))
        #expect(FileManager.default.fileExists(atPath: keepInRoot.path))
    }
}
