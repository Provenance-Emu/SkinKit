#if canImport(UIKit)
import Foundation
import SkinKitCore
import SkinKitManager
import SwiftUI
import Testing
import UIKit
@testable import SkinKitUI

/// The skin theme picker: where it is shown, that choosing a theme redraws a skin that is already on
/// screen, and that the choice is stored. Uses `Themes/Themed-GBA.deltaskin`: a base layout drawn in solid
/// red and two themes ("neon" green, "ocean" blue) that swap only the artwork.
extension UIKitSerial {
    @Suite("Theme picker", .serialized)
    @MainActor
    struct ThemePickerTests {

        static let themeIDs = ["neon", "ocean"]

        init() {
            TestSupport.disableDefaultSkinFallback()
            TestSupport.clearDiskRasterCache()
        }

        private func themedSkin() throws -> DeltaSkin {
            let skin = try DeltaSkin(fileURL: TestSupport.fixtureURL("Themes/Themed-GBA.deltaskin"))
            // A choice left in UserDefaults by an earlier run would change the starting artwork.
            DeltaSkinThemeSelection.setSelectedThemeId(nil, for: skin.identifier)
            return skin
        }

        /// A view kept in a window, so one test can look at it before and after a change.
        @MainActor
        private final class HostedWindow {
            let window: UIWindow
            let host: UIHostingController<AnyView>

            init<V: View>(_ view: V, size: CGSize = CGSize(width: 390, height: 844)) {
                host = UIHostingController(rootView: AnyView(view.frame(width: size.width, height: size.height).background(Color.black)))
                window = UIWindow(frame: CGRect(origin: .zero, size: size))
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.frame = window.bounds
                host.view.layoutIfNeeded()
            }

            deinit { window.isHidden = true }

            func capture() -> UIImage {
                host.view.layoutIfNeeded()
                // drawHierarchy needs a render server; the layer tree is the fallback when it returns blank.
                let viaHierarchy = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                if dominantChannel(of: viaHierarchy) != .none { return viaHierarchy }
                return UIGraphicsImageRenderer(bounds: window.bounds).image { ctx in
                    host.view.layer.render(in: ctx.cgContext)
                }
            }

            /// Waits until the window's dominant colour is `channel`; returns what it ended on.
            func waitForDominantChannel(_ channel: Channel, timeout: TimeInterval = 20) async -> Channel {
                let deadline = Date().addingTimeInterval(timeout)
                var latest = Channel.none
                while Date() < deadline {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    latest = dominantChannel(of: capture())
                    if latest == channel { break }
                }
                return latest
            }

            /// Every `UISegmentedControl` under the hosted view (SwiftUI's segmented `Picker`).
            var segmentedControls: [UISegmentedControl] {
                var found: [UISegmentedControl] = []
                func walk(_ view: UIView) {
                    if let control = view as? UISegmentedControl { found.append(control) }
                    view.subviews.forEach(walk)
                }
                walk(host.view)
                return found
            }

            func waitForSegmentedControl(timeout: TimeInterval = 10) async -> UISegmentedControl? {
                let deadline = Date().addingTimeInterval(timeout)
                while Date() < deadline {
                    host.view.layoutIfNeeded()
                    if let control = segmentedControls.first { return control }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                return nil
            }
        }

        private let traits = TestSupport.portrait

        // MARK: - Model

        @Test("The fixture declares two themes that only swap the artwork")
        func fixtureHasThemes() throws {
            let skin = try themedSkin()
            #expect(skin.availableThemes.map(\.id) == Self.themeIDs)
            #expect(skin.availableThemes.map(\.name) == ["Neon", "Ocean"])
            let rep = try #require(skin.representation(for: traits))
            #expect(rep.assets.candidates().contains { $0.contains("base") })
        }

        // MARK: - Rendering

        @Test("Choosing a theme redraws a DeltaSkinView that is already on screen, and Default restores the base art")
        func selectingAThemeChangesTheDrawnArtwork() async throws {
            let skin = try themedSkin()
            defer { DeltaSkinThemeSelection.setSelectedThemeId(nil, for: skin.identifier) }
            let hosted = HostedWindow(DeltaSkinView(skin: skin, traits: traits, isInEmulator: true, inputHandler: DeltaSkinPreviewInputHandler()))

            #expect(await hosted.waitForDominantChannel(.red) == .red, "the base layout is drawn in red")

            DeltaSkinThemeSelection.setSelectedThemeId("neon", for: skin.identifier)
            #expect(await hosted.waitForDominantChannel(.green) == .green, "the neon theme is drawn in green")

            DeltaSkinThemeSelection.setSelectedThemeId("ocean", for: skin.identifier)
            #expect(await hosted.waitForDominantChannel(.blue) == .blue, "the ocean theme is drawn in blue")

            DeltaSkinThemeSelection.setSelectedThemeId(nil, for: skin.identifier)
            #expect(await hosted.waitForDominantChannel(.red) == .red, "Default goes back to the base art")
        }

        @Test("A stored theme is applied when the skin is shown, and another skin's choice is ignored")
        func storedThemeAppliesOnAppear() async throws {
            let skin = try themedSkin()
            defer { DeltaSkinThemeSelection.setSelectedThemeId(nil, for: skin.identifier) }
            DeltaSkinThemeSelection.setSelectedThemeId("ocean", for: "com.skinkit.test.some-other-skin")
            defer { DeltaSkinThemeSelection.setSelectedThemeId(nil, for: "com.skinkit.test.some-other-skin") }
            DeltaSkinThemeSelection.setSelectedThemeId("neon", for: skin.identifier)

            let hosted = HostedWindow(DeltaSkinView(skin: skin, traits: traits, isInEmulator: true, inputHandler: DeltaSkinPreviewInputHandler()))
            #expect(await hosted.waitForDominantChannel(.green) == .green)

            // Not this skin's selection: nothing may redraw.
            DeltaSkinThemeSelection.setSelectedThemeId("ocean", for: "com.skinkit.test.some-other-skin-2")
            defer { DeltaSkinThemeSelection.setSelectedThemeId(nil, for: "com.skinkit.test.some-other-skin-2") }
            try await Task.sleep(nanoseconds: 750_000_000)
            #expect(dominantChannel(of: hosted.capture()) == .green)
        }

        @Test("Preview thumbnails are keyed by the selected theme, so a stale one is never reused")
        func thumbnailKeyIncludesTheme() throws {
            let skin = try themedSkin()
            defer { DeltaSkinThemeSelection.setSelectedThemeId(nil, for: skin.identifier) }
            let base = SkinPreviewThumbnailCache.key(for: skin.identifier, traits: traits)
            DeltaSkinThemeSelection.setSelectedThemeId("neon", for: skin.identifier)
            let neon = SkinPreviewThumbnailCache.key(for: skin.identifier, traits: traits)
            DeltaSkinThemeSelection.setSelectedThemeId("ocean", for: skin.identifier)
            let ocean = SkinPreviewThumbnailCache.key(for: skin.identifier, traits: traits)
            #expect(Set([base, neon, ocean]).count == 3)
            DeltaSkinThemeSelection.setSelectedThemeId(nil, for: skin.identifier)
            #expect(SkinPreviewThumbnailCache.key(for: skin.identifier, traits: traits) == base)
        }

        @Test("A theme choice changes the preview thumbnail's artwork")
        func selectingAThemeChangesTheThumbnail() async throws {
            let skin = try themedSkin()
            defer { DeltaSkinThemeSelection.setSelectedThemeId(nil, for: skin.identifier) }
            let base = try await SkinPreviewThumbnailCache.preview(of: skin, traits: traits)
            DeltaSkinThemeSelection.setSelectedThemeId("neon", for: skin.identifier)
            let themed = try await SkinPreviewThumbnailCache.preview(of: skin, traits: traits)
            #expect(dominantChannel(of: base) == .red)
            #expect(dominantChannel(of: themed) == .green)
        }

        // MARK: - The picker

        @Test("A stored theme persists across skin objects, and a new picker starts on it")
        func pickerStartsOnTheStoredChoice() async throws {
            let skin = try themedSkin()
            defer { DeltaSkinThemeSelection.setSelectedThemeId(nil, for: skin.identifier) }

            let hosted = HostedWindow(DeltaSkinThemePickerView(skin: skin))
            let control = try #require(await hosted.waitForSegmentedControl())
            // Default, Neon, Ocean
            #expect(control.numberOfSegments == 3)
            #expect(control.selectedSegmentIndex == 0)

            // The picker writes through `DeltaSkinPreferences`, which stores in `DeltaSkinThemeSelection`.
            DeltaSkinPreferences.shared.setSelectedThemeId("ocean", for: skin.identifier)
            #expect(UserDefaults.standard.string(forKey: "com.provenance.deltaskin.theme." + skin.identifier) == "ocean")
            // A picker that is already showing follows the change...
            let followed = Date().addingTimeInterval(5)
            while control.selectedSegmentIndex != 2, Date() < followed {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            #expect(control.selectedSegmentIndex == 2)

            // ...a skin loaded afresh, as after a relaunch, reports it...
            let reloaded = try DeltaSkin(fileURL: TestSupport.fixtureURL("Themes/Themed-GBA.deltaskin"))
            #expect(reloaded.selectedThemeId == "ocean")
            // ...and so does a new picker.
            let second = HostedWindow(DeltaSkinThemePickerView(skin: reloaded))
            let secondControl = try #require(await second.waitForSegmentedControl())
            let deadline = Date().addingTimeInterval(5)
            while secondControl.selectedSegmentIndex != 2, Date() < deadline {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            #expect(secondControl.selectedSegmentIndex == 2)

            DeltaSkinPreferences.shared.setSelectedThemeId(nil, for: skin.identifier)
            #expect(DeltaSkinThemeSelection.selectedThemeId(for: skin.identifier) == nil)
        }

        @Test("A skin without themes shows no picker")
        func noPickerWithoutThemes() async throws {
            let plain = try TestSupport.loadFixture("Backbone-GBA.deltaskin")
            let hosted = HostedWindow(DeltaSkinThemePickerView(skin: plain))
            try await Task.sleep(nanoseconds: 500_000_000)
            hosted.host.view.layoutIfNeeded()
            #expect(hosted.segmentedControls.isEmpty)
        }

        // MARK: - Where the picker is shown

        @Test("The fullscreen pager shows the picker for a themed skin only")
        func pagerShowsPicker() async throws {
            let themed = try themedSkin()
            let pager = HostedWindow(DeltaSkinFullscreenPagerView(skins: [themed], traits: traits))
            let control = await pager.waitForSegmentedControl()
            #expect(control?.numberOfSegments == 3)

            let plain = try TestSupport.loadFixture("Backbone-GBA.deltaskin")
            let plainTraits = try #require(TestSupport.declaredTraits(of: plain).first)
            let plainPager = HostedWindow(DeltaSkinFullscreenPagerView(skins: [plain], traits: plainTraits))
            try await Task.sleep(nanoseconds: 1_000_000_000)
            #expect(plainPager.segmentedControls.isEmpty)
        }

        @Test("The fullscreen preview shows the picker for a themed skin")
        func fullscreenPreviewShowsPicker() async throws {
            let skin = try themedSkin()
            let hosted = HostedWindow(DeltaSkinFullscreenPreview(skin: skin, traits: traits, filters: []))
            let control = try #require(await hosted.waitForSegmentedControl())
            #expect(control.numberOfSegments == 3)
        }
    }
}
#endif
