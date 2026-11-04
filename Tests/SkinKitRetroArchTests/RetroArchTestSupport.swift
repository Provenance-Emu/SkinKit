import Foundation
import Testing
@testable import SkinKitRetroArch

/// Shared fixture loading for the SkinKitRetroArch tests.
enum Fixture {
    static var root: URL {
        Bundle.module.resourceURL!.appendingPathComponent("Fixtures", isDirectory: true)
    }

    static func infoData(_ name: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("info/\(name).info.json"))
    }

    static func info(_ name: String) throws -> RetroArchSkinInfo {
        try RetroArchSkinInfo(infoJSON: try infoData(name))
    }

    static func expected(_ id: String, _ ext: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("expected/\(id).\(ext)"))
    }

    static func expectedText(_ id: String, _ ext: String) throws -> String {
        String(decoding: try expected(id, ext), as: UTF8.self)
    }

    /// One row of `Fixtures/cases.json`; `scripts/gen-retroarch-expected.mjs` reads the same file.
    struct Case: Decodable, CustomTestStringConvertible {
        let id: String
        let info: String
        let device: String?
        let displayType: String?
        let screenAspect: Double?
        let name: String?
        let entries: [String]?
        let tvFromIPadStandardLandscape: Bool?

        var testDescription: String { id }

        var options: RetroArchConverter.Options {
            var o = RetroArchConverter.Options()
            if let device { o.device = .init(rawValue: device)! }
            if let displayType { o.displayType = .init(rawValue: displayType)! }
            o.screenAspect = screenAspect
            o.name = name
            o.entries = entries
            return o
        }

        /// The case's skin, with the same edits the generator applies.
        func skinInfo() throws -> RetroArchSkinInfo {
            guard tvFromIPadStandardLandscape == true else { return try Fixture.info(info) }
            let cleaned = RetroArchSkinInfo.stripComments(String(decoding: try Fixture.infoData(info), as: UTF8.self))
            var json = try JSONSerialization.jsonObject(with: Data(cleaned.utf8)) as! [String: Any]
            var reps = json["representations"] as! [String: Any]
            let ipad = reps["ipad"] as! [String: Any]
            let standard = ipad["standard"] as! [String: Any]
            reps["tv"] = ["standard": ["landscape": standard["landscape"]!]]
            json["representations"] = reps
            return RetroArchSkinInfo(json: json)
        }
    }

    static func cases() throws -> [Case] {
        try JSONDecoder().decode([Case].self, from: Data(contentsOf: root.appendingPathComponent("cases.json")))
    }
}
