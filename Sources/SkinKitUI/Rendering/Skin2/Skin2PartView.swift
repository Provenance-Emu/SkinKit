#if canImport(UIKit)
import SkinKit2Core
import SkinKit2Render
import SwiftUI

/// One part of the format 2 parts library drawn by itself, filling the view: `Skin2PartView(part: "std.vmu")`.
///
/// It wraps the part in a minimal skin and draws it with `Skin2SkinView`, so the part looks and behaves exactly
/// as it does inside a controller skin. An app can use it as its own floating accessory in place of hand-written
/// drawing; a TV bezel mounts a panel's part with it. An unknown part, or arguments the part rejects, draws
/// nothing.
public struct Skin2PartView: View {
    private let document: Skin2Document?
    private let capabilities: Set<String>
    private let pictures: Skin2PictureStore?

    /// The id of the part's instance; its inner nodes are `part.<id>` (`part.lcd`).
    public static let instanceID = "part"

    public init(part: String, with arguments: [String: Skin2JSON] = [:], capabilities: Set<String> = [],
                pictures: Skin2PictureStore? = nil) {
        document = Self.document(part: part, with: arguments)
        self.capabilities = capabilities
        self.pictures = pictures
    }

    public var body: some View {
        if let document {
            Skin2SkinView(document: document, screenPlaceholders: pictures == nil, playsHaptics: false,
                          safeAreaOverride: .zero, capabilities: capabilities, pictures: pictures, extendsIntoSafeArea: false)
        }
    }

    /// The skin that holds one instance of `part` filling the canvas, listing the features that instance uses.
    static func source(part: String, with arguments: [String: Skin2JSON]) -> Skin2JSON? {
        func skin(requires: [String]) -> Skin2JSON {
            [
                "formatVersion": "2.0",
                "requires": .array(requires.map { .string($0) }),
                "identifier": .string("skinkit.part." + part),
                "name": .string(part),
                "gameTypes": ["skinkit.part"],
                "reference": ["shortSide": 390, "minScale": 1, "maxScale": 1],
                "root": ["type": "group", "children": [
                    ["use": .string(part), "id": .string(instanceID), "with": .object(arguments), "layout": ["inset": 0]],
                ]],
            ]
        }
        let bare = skin(requires: [])
        guard let document = try? Skin2Document.load(json: bare) else { return nil }
        return skin(requires: Skin2Features.used(source: bare, documents: [document]).sorted())
    }

    static func document(part: String, with arguments: [String: Skin2JSON]) -> Skin2Document? {
        guard let source = source(part: part, with: arguments), let document = try? Skin2Document.load(json: source),
              SkinKit2Render.supports(document.requires) else { return nil }
        return document
    }
}
#endif
