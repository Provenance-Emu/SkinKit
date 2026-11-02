import Foundation
import Testing
@testable import SkinKitCore

/// `sanitizeJSON` strips `//` comments, but only outside string literals. A skin whose `info.json` carries a URL
/// (`"https://..."`) must decode: the old line-based cut turned that value into an unterminated string.
@Suite("sanitizeJSON comments and strings")
struct DeltaSkinSanitizeJSONTests {

    private static func skinJSON(name: String, extra: String = "") -> String {
        #"""
        {
          "name": "\#(name)", "identifier": "com.example.sanitize", "gameTypeIdentifier": "com.rileytestut.delta.game.gba",
          \#(extra)
          "representations": { "iphone": { "standard": { "portrait": {
            "assets": { "resizable": "skin.pdf" }, "mappingSize": { "width": 10, "height": 20 }, "items": []
          } } } }
        }
        """#
    }

    private static func sanitized(_ json: String) throws -> String {
        String(decoding: try sanitizeJSON(Data(json.utf8)), as: UTF8.self)
    }

    private static func object(_ json: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    // MARK: - Strings are left alone

    @Test("An info.json with a URL value decodes from disk")
    func urlValueDecodesFromDisk() throws {
        let json = Self.skinJSON(name: "https://example.com/skins/a", extra: #""website": "https://example.com/about", "_comment": "see https://example.com // not a comment","#)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkinKitCoreTests-\(UUID().uuidString).deltaskin", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(json.utf8).write(to: dir.appendingPathComponent("info.json"))

        let skin = try DeltaSkin(fileURL: dir)
        #expect(skin.info.name == "https://example.com/skins/a")
        #expect(skin.jsonRepresentation["website"] as? String == "https://example.com/about")
        #expect(skin.mappingSize(for: DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .portrait)) == CGSize(width: 10, height: 20))
    }

    @Test("A URL value decodes through the default Info.decode path")
    func urlValueDecodesViaInfo() throws {
        let info = try DeltaSkin.Info.decode(Data(Self.skinJSON(name: "http://a.example//b").utf8))
        #expect(info.name == "http://a.example//b")
    }

    @Test("A string that is exactly // survives sanitizeJSON")
    func slashSlashStringSurvives() throws {
        let out = try Self.sanitized(Self.skinJSON(name: "//", extra: #""note": "//","#))
        let object = try Self.object(out)
        #expect(object["name"] as? String == "//")
        #expect(object["note"] as? String == "//")
    }

    @Test("An escaped quote does not end the string early")
    func escapedQuoteKeepsStringOpen() throws {
        // The string is: say "hi" // there. The \" must not close it, or the // would be cut.
        let json = #"{ "name": "say \"hi\" // there", "tail": "x" }"#
        let object = try Self.object(try Self.sanitized(json))
        #expect(object["name"] as? String == #"say "hi" // there"#)
        #expect(object["tail"] as? String == "x")
    }

    @Test("A backslash before the closing quote does not hide the next comment")
    func escapedBackslashClosesString() throws {
        // "C:\\" ends at its second quote, so the // after it is a real comment.
        let json = "{ \"path\": \"C:\\\\\", // trailing\n  \"n\": 1 }"
        let object = try Self.object(try Self.sanitized(json))
        #expect(object["path"] as? String == "C:\\")
        #expect(object["n"] as? Int == 1)
    }

    // MARK: - Real comments still go

    @Test("Whole-line and trailing comments are removed and the rest decodes")
    func commentsAreStripped() throws {
        let json = """
        // header comment
        {
          // whole-line comment
          "name": "Annotated", // trailing comment
          "identifier": "com.example.comments", "gameTypeIdentifier": "com.rileytestut.delta.game.gba",
          "representations": { "iphone": { "standard": { "portrait": {
            "assets": { "resizable": "skin.pdf" }, "mappingSize": { "width": 10, "height": 20 }, "items": [] // none yet
          } } } }
        }
        """
        let out = try Self.sanitized(json)
        #expect(!out.contains("//"))
        let decoder = JSONDecoder()
        let info = try decoder.decode(DeltaSkin.Info.self, from: Data(out.utf8))
        #expect(info.name == "Annotated")
    }

    @Test("A comment may contain quotes and URLs, and a string after it still survives")
    func commentContentIsIgnored() throws {
        let json = """
        {
          "a": 1, // it's "quoted" and has https://example.com in it
          "b": "https://example.com/b"
        }
        """
        let object = try Self.object(try Self.sanitized(json))
        #expect(object["a"] as? Int == 1)
        #expect(object["b"] as? String == "https://example.com/b")
    }

    @Test("CRLF line endings: the comment ends at the line break")
    func crlfComment() throws {
        let object = try Self.object(try Self.sanitized("{ \"a\": 1, // note\r\n \"b\": 2 }"))
        #expect(object["a"] as? Int == 1)
        #expect(object["b"] as? Int == 2)
    }

    @Test("A single slash is not a comment")
    func singleSlashKept() throws {
        let object = try Self.object(try Self.sanitized(#"{ "a": "x/y", "b": 1 }"#))
        #expect(object["a"] as? String == "x/y")
    }

    @Test("Data that is not UTF-8 is rejected")
    func nonUTF8Rejected() {
        #expect(throws: DeltaSkinError.self) { _ = try sanitizeJSON(Data([0xFF, 0xFE, 0x00])) }
    }
}
