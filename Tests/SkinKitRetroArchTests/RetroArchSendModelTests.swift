import Foundation
import Testing
import ZIPFoundation
import SkinKitCore
@testable import SkinKitRetroArch

@Suite("Send to RetroArch: report, route and model")
struct RetroArchSendModelTests {

    private static func conversion(_ info: String) throws -> RetroArchConversion {
        try RetroArchConverter.bundled().convert(infoJSON: Fixture.infoData(info))
    }

    /// Writes a fake `SkinKitRetroArch-<uuid>/<name>/` export, like the real exporter's temporary output.
    private static func fakeFolder(name: String = "My_Skin") throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SkinKitRetroArch-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("overlays = 1".utf8).write(to: folder.appendingPathComponent("\(name).cfg"))
        try Data([0x89]).write(to: folder.appendingPathComponent("\(name)-landscape.png"))
        return folder
    }

    private static func report(folderName: String = "My_Skin") throws -> RetroArchSendReport {
        var report = RetroArchSendReport(conversion: try conversion("backbone-gba"))
        report.folderName = folderName
        return report
    }

    // MARK: Report

    @Test("The report names the folder, system, overlay count and the core the buttons assume")
    func reportBasics() throws {
        let conv = try Self.conversion("backbone-gba")
        let report = RetroArchSendReport(conversion: conv, inputMap: try RetroArchInputMap.bundled())
        #expect(report.folderName == conv.name)
        #expect(report.system == "gba")
        #expect(report.overlayCount == conv.layouts.count && report.overlayCount > 0)
        #expect(report.assumes?.isEmpty == false)
        #expect(RetroArchSendReport(conversion: conv).assumes == nil)
    }

    @Test("Unconvertible inputs are listed, and grouped once per input across layouts")
    func reportUnmapped() throws {
        let conv = try Self.conversion("n64-comments")
        let report = RetroArchSendReport(conversion: conv)
        #expect(report.unmapped.count == conv.unconvertible.count)
        #expect(report.unmapped.contains { $0.input.hasPrefix("touchScreen") })
        let grouped = report.unmappedByInput
        #expect(Set(grouped.map(\.input)).count == grouped.count, "each input appears once")
        #expect(grouped.allSatisfy { !$0.reason.isEmpty && !$0.locations.isEmpty })
        #expect(grouped.count <= report.unmapped.count)
        #expect(report.hasIssues)
    }

    @Test("Notes and skipped layouts become warnings, without repeats")
    func reportWarnings() throws {
        var conv = try Self.conversion("backbone-gba")
        conv.notes = ["No iphone layouts; using ipad.", "No iphone layouts; using ipad."]
        conv.skipped = [.init(overlayName: "portrait", displayType: "standard", asset: "p.pdf", reason: "p.pdf is not in the skin.")]
        let report = RetroArchSendReport(conversion: conv)
        #expect(report.warnings == ["No iphone layouts; using ipad.", "portrait (standard) was left out: p.pdf is not in the skin."])
    }

    @Test("A clean conversion has no issues")
    func reportClean() throws {
        var conv = try Self.conversion("backbone-gba")
        conv.notes = []
        conv.skipped = []
        conv.unconvertible = []
        #expect(!RetroArchSendReport(conversion: conv).hasIssues)
    }

    // MARK: Text

    @Test("Destination text names the Files path and the menu taps carry the folder name")
    func text() {
        #expect(RetroArchSendText.destination == "On My iPhone › RetroArch › RetroArch › overlays")
        #expect(RetroArchSendText.destinationHint.contains(RetroArchSendText.destination))
        let taps = RetroArchSendText.menuTaps(folderName: "Foo")
        #expect(taps.count == 3)
        #expect(taps[1].contains("Foo/Foo.cfg") && !taps.joined().contains("<name>"))
    }

    // MARK: Availability

    @Test("Offered when the input map has a row for the game type")
    func availability() throws {
        #expect(RetroArchSendAvailability.isSupported(gameTypeIdentifier: "com.rileytestut.delta.game.gba"))
        #expect(RetroArchSendAvailability.isSupported(gameTypeIdentifier: "com.rileytestut.delta.game.n64"))
        #expect(!RetroArchSendAvailability.isSupported(gameTypeIdentifier: "com.example.game.unheardof"))
        #expect(!RetroArchSendAvailability.isSupported(gameTypeIdentifier: nil))
        #expect(!RetroArchSendAvailability.isSupported(gameTypeIdentifier: ""))
        let nes = try Fixture.info("pockettaco-nes")
        #expect(RetroArchSendAvailability.isSupported(gameTypeIdentifier: nes.gameTypeIdentifier))
    }

    // MARK: Route

    @Test("The provenance://skins/retroarch route and its skin parameter")
    func route() throws {
        func parse(_ s: String) -> RetroArchSendRoute.Route? { RetroArchSendRoute.parse(URL(string: s)!) }
        #expect(parse("provenance://skins/retroarch") != nil)
        #expect(parse("provenance://skins/retroarch")?.skinIdentifier == nil)
        #expect(parse("provenance://skins/retroarch/?skin=com.example.skin")?.skinIdentifier == "com.example.skin")
        #expect(parse("Provenance://Skins/retroarch?skin=a%20b")?.skinIdentifier == "a b")
        #expect(parse("provenance://skins/retroarch?skin=")?.skinIdentifier == nil)
        #expect(parse("provenance://skins/other") == nil)
        #expect(parse("provenance://games/retroarch") == nil)
        #expect(parse("provenance-ecosystem://skins/retroarch") == nil)
        #expect(parse("https://emuskins.com/skins/retroarch") == nil)

        #expect(RetroArchSendRoute.url(forSkinIdentifier: nil).absoluteString == "provenance://skins/retroarch")
        let url = RetroArchSendRoute.url(forSkinIdentifier: "a b&c=d")
        #expect(RetroArchSendRoute.parse(url)?.skinIdentifier == "a b&c=d", "ids survive the round trip")
    }

    // MARK: Model

    @Test("start() exports once and publishes the folder and report")
    @MainActor
    func modelSuccess() async throws {
        let folder = try Self.fakeFolder()
        let report = try Self.report()
        let model = RetroArchSendModel { RetroArchSendResult(folder: folder, report: report) }
        #expect(model.state == .idle && model.folder == nil)
        await model.start()
        #expect(model.state == .ready(RetroArchSendResult(folder: folder, report: report)))
        #expect(model.folder == folder)
        await model.start()  // no second run
        model.cleanUp()
        #expect(!FileManager.default.fileExists(atPath: folder.deletingLastPathComponent().path))
    }

    @Test("A failing export becomes a readable message")
    @MainActor
    func modelFailure() async throws {
        let model = RetroArchSendModel { throw RetroArchExportError.nothingToConvert(notes: ["The skin has no layouts with artwork."]) }
        await model.start()
        guard case .failed(let message) = model.state else { Issue.record("expected failure"); return }
        #expect(message.contains("no layout") && message.contains("no layouts with artwork"))
        #expect(model.folder == nil)
        #expect(throws: (any Error).self) { try model.shareArchive() }
    }

    @Test("Error messages cover each exporter error")
    func errorMessages() {
        #expect(RetroArchSendModel.message(for: RetroArchExportError.missingAsset("a.pdf")).contains("a.pdf"))
        #expect(RetroArchSendModel.message(for: RetroArchExportError.unreadableSkin(URL(fileURLWithPath: "/x"))).contains("could not be read"))
        #expect(RetroArchSendModel.message(for: RetroArchExportError.unsafeFolderName("..")).contains(".."))
    }

    @Test("reset() deletes the files and lets start() run again")
    @MainActor
    func modelReset() async throws {
        let counter = Counter()
        let report = try Self.report()
        let model = RetroArchSendModel {
            counter.increment()
            return RetroArchSendResult(folder: try Self.fakeFolder(), report: report)
        }
        await model.start()
        let first = try #require(model.folder)
        model.reset()
        #expect(model.state == .idle)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        await model.start()
        #expect(counter.value == 2)
        model.cleanUp()
    }

    @Test("The share archive is <name>.zip holding <name>/<name>.cfg, next to the folder")
    @MainActor
    func shareArchive() async throws {
        let folder = try Self.fakeFolder(name: "Zip_Me")
        let report = try Self.report(folderName: "Zip_Me")
        let model = RetroArchSendModel { RetroArchSendResult(folder: folder, report: report) }
        await model.start()
        let zip = try model.shareArchive()
        #expect(zip.lastPathComponent == "Zip_Me.zip")
        #expect(zip.deletingLastPathComponent().standardizedFileURL == folder.deletingLastPathComponent().standardizedFileURL)
        #expect(try model.shareArchive() == zip, "made once")
        let archive = try Archive(url: zip, accessMode: .read, pathEncoding: nil)
        let names = Set(archive.map(\.path).filter { !$0.hasSuffix("/") })
        #expect(names == ["Zip_Me/Zip_Me.cfg", "Zip_Me/Zip_Me-landscape.png"])
        model.cleanUp()
        #expect(!FileManager.default.fileExists(atPath: zip.path))
    }

    @Test("Scratch cleanup only removes SkinKitRetroArch-* directories")
    func scratchSafety() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("KeepMe-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("Skin", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        RetroArchSendModel.removeScratch(for: folder)
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }

    @Test("End to end: the real exporter's folder flows through the model")
    @MainActor
    func realExporter() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SendModelTests-\(UUID().uuidString)", isDirectory: true)
        let skinFolder = root.appendingPathComponent("Skin.deltaskin", isDirectory: true)
        try FileManager.default.createDirectory(at: skinFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Fixture.infoData("backbone-gba").write(to: skinFolder.appendingPathComponent("info.json"))
        try Data("<svg/>".utf8).write(to: skinFolder.appendingPathComponent("controller.svg"))
        let out = root.appendingPathComponent("out")
        let model = RetroArchSendModel {
            let skin = try DeltaSkin(fileURL: skinFolder, options: .lenient)
            let map = try RetroArchInputMap.bundled()
            return RetroArchSendResult(
                export: try RetroArchOverlayExporter.export(skin: skin, into: out) { _ in Data([0x89, 0x50, 0x4E, 0x47]) },
                inputMap: map)
        }
        await model.start()
        guard case .ready(let result) = model.state else { Issue.record("state \(model.state)"); return }
        #expect(FileManager.default.fileExists(atPath: result.folder.appendingPathComponent("\(result.report.folderName).cfg").path))
        #expect(result.report.system == "gba" && result.report.assumes != nil)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
