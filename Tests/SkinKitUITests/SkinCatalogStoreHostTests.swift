#if canImport(UIKit) && !os(tvOS)
import Foundation
import SkinCatalogKit
import SkinKitManager
import SwiftUI
import Testing
import UIKit
@testable import SkinKitUI

/// The catalog browser scoped to an app's store: what the host answers for the views, and that
/// the screens build with one.
extension UIKitSerial {
    @Suite("Catalog browser as an app's store")
    @MainActor
    struct SkinCatalogStoreHostTests {
        /// Writes an empty file where the installer asked, so the install step runs.
        private struct FakeDownloader: SkinStoreDownloading {
            func download(from url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data().write(to: destination)
                progress(1)
            }
        }

        /// The installed record, kept in memory.
        private final class RecordBox: @unchecked Sendable {
            var value: [String: String] = [:]
        }

        private func entry(_ id: String, systems: [String], ext: String = "deltaskin", groupId: String? = nil) throws -> SkinCatalogEntry {
            try SkinCatalogEntry(
                id: id, name: "Skin \(id)", author: "ann", systems: systems,
                downloadURL: #require(URL(string: "https://example.invalid/\(id).\(ext)")),
                groupId: groupId
            )
        }

        private func host(
            policy: SkinStorePolicy = .iFly,
            sections: inout [String],
            note: @escaping (SkinStoreSection) -> String? = { _ in nil }
        ) -> SkinCatalogStoreHost {
            let box = RecordBox()
            let installer = SkinStoreInstaller(
                policy: policy,
                downloader: FakeDownloader(),
                record: SkinStoreInstalledRecord(load: { box.value }, save: { box.value = $0 }),
                installStep: { file, _ in .installed(identifier: file.deletingPathExtension().lastPathComponent) }
            )
            sections = policy.sections.map(\.id)
            return SkinCatalogStoreHost(policy: policy, installer: installer, categoryNote: note)
        }

        @Test("The host starts on the device the app runs on")
        func defaultDevice() {
            var sections: [String] = []
            let store = host(sections: &sections)
            #expect(store.device == SkinStoreDevice.current)
            #expect(store.device != nil)
        }

        @Test("A family is installed once the host's installer installed one of its members")
        func installedMarkFollowsTheInstaller() async throws {
            var sections: [String] = []
            let store = host(sections: &sections)
            let first = try entry("a", systems: ["dreamcast"], groupId: "g")
            let second = try entry("b", systems: ["dreamcast"], groupId: "g")
            let family = try #require(SkinFamily.families(from: [first, second]).first)
            #expect(family.members.count == 2)
            #expect(!store.isInstalled(family))

            await store.installer.install(second)

            #expect(store.installer.state(for: second) == .installed)
            #expect(store.installer.state(for: first) == .idle)
            #expect(store.isInstalled(family))
        }

        @Test("Install all fetches only the members the policy can install")
        func installAllPlanFollowsThePolicy() throws {
            var sections: [String] = []
            let store = host(sections: &sections)
            let skin = try entry("a", systems: ["dreamcast"], groupId: "g")
            let zip = try entry("b", systems: ["dreamcast"], ext: "zip", groupId: "g")
            let family = try #require(SkinFamily.families(from: [skin, zip]).first)
            #expect(store.installAllPlan(for: family).entries.map(\.id) == ["a"])
        }

        @Test("The note shown for a skin is its shelf's")
        func noteComesFromTheEntrysShelf() throws {
            var sections: [String] = []
            let store = host(sections: &sections) { $0.id == "arcade" ? "Installs as an arcade skin." : nil }
            #expect(try store.note(for: entry("m", systems: ["mame"])) == "Installs as an arcade skin.")
            #expect(try store.note(for: entry("d", systems: ["dreamcast"])) == nil)
            // Not on any shelf: no section, no note.
            #expect(try store.section(for: entry("g", systems: ["gba"])) == nil)
            #expect(try store.note(for: entry("g", systems: ["gba"])) == nil)
        }

        @Test("The browser and the detail view build and lay out with a store")
        func screensBuildWithAStore() throws {
            var sections: [String] = []
            let store = host(policy: .iCube, sections: &sections)
            let skin = try entry("a", systems: ["gamecube"])

            let browser = UIHostingController(rootView: NavigationStack {
                SkinCatalogBrowserView(store: store, preselectedCategory: sections.first)
            })
            browser.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            browser.view.layoutIfNeeded()
            #expect(browser.view.bounds.width == 390)

            let detail = UIHostingController(rootView: NavigationStack {
                SkinCatalogDetailView(entry: skin, store: store)
            })
            detail.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            detail.view.layoutIfNeeded()
            #expect(detail.view.bounds.height == 844)
        }
    }
}
#endif
