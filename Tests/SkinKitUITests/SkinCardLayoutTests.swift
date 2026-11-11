#if canImport(UIKit)
import SkinKitCore
import SkinKitManager
import SwiftUI
import Testing
import UIKit
@testable import SkinKitUI

extension UIKitSerial {
    @MainActor @Suite("Skin card layout", .serialized)
    struct SkinCardLayoutTests {
        private let cardWidth: CGFloat = 180

        @Test("Cards reserve their metadata line with and without device badges",
              arguments: [DynamicTypeSize.large, .accessibility3])
        func equalCardHeights(typeSize: DynamicTypeSize) throws {
            let scratch = try TestSupport.makeScratch("SkinCardLayout")
            defer { try? FileManager.default.removeItem(at: scratch) }
            let withBadge = try makeSkin(in: scratch, name: "Short", portrait: true)
            let withoutBadge = try makeSkin(
                in: scratch, name: "Controller Skin With A Long Descriptive Name", portrait: false
            )
            #expect(withBadge.supports(TestSupport.portrait))
            #expect(!withoutBadge.supports(TestSupport.portrait))
            let manager = DeltaSkinManager(configuration: .init(skinsDirectory: scratch, bundledSkinLocations: { [] }))
            let first = height(of: withBadge, manager: manager, typeSize: typeSize)
            let second = height(of: withoutBadge, manager: manager, typeSize: typeSize)
            #expect(abs(first - second) < 0.5, "Card height must not depend on badge availability or title length")
            #expect(first > cardWidth)
        }

        private func height(of skin: DeltaSkin, manager: DeltaSkinManager, typeSize: DynamicTypeSize) -> CGFloat {
            // Ask for the same ideal height that the grid proposes, not a stretched overlay.
            let card = SkinPreviewCell(skin: skin, manager: manager)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.dynamicTypeSize, typeSize)
            return UIHostingController(rootView: card)
                .sizeThatFits(in: CGSize(width: cardWidth, height: .greatestFiniteMagnitude)).height
        }

        private func makeSkin(in directory: URL, name: String, portrait: Bool) throws -> DeltaSkin {
            let id = portrait ? "card.badges" : "card.no-badges"
            var info = TestSupport.gbaInfo(identifier: id, asset: "art.png")
            info["name"] = name
            if !portrait {
                let devices = try #require(info["representations"] as? [String: Any])
                let phone = try #require(devices["iphone"] as? [String: Any])
                let standard = try #require(phone["standard"] as? [String: Any])
                let representation = try #require(standard["portrait"] as? [String: Any])
                info["representations"] = ["iphone": ["standard": ["landscape": representation]]]
            }
            let url = try TestSupport.writeSkin(
                info: info, files: ["art.png": TestSupport.makeOpaquePNG()], in: directory, name: "\(id).deltaskin"
            )
            return try DeltaSkin(fileURL: url)
        }
    }
}
#endif
