#if DEBUG && canImport(UIKit)
import SwiftUI
import SkinKitCore
import SkinKitManager

// Previews for the main views, on the fixture skins in Tests/SkinKitUITests/Fixtures
// (see `PreviewFixtures`). Open this file in Xcode with the package checked out.

#Preview("Skin view: GBA portrait") {
    DeltaSkinView(skin: PreviewFixtures.skin("Backbone-GBA"), traits: PreviewFixtures.portrait,
                  inputHandler: DeltaSkinPreviewInputHandler())
        .background(Color.black)
}

#Preview("Skin view: GBA landscape", traits: .landscapeLeft) {
    DeltaSkinView(skin: PreviewFixtures.skin("Backbone-GBA"), traits: PreviewFixtures.landscape,
                  inputHandler: DeltaSkinPreviewInputHandler())
        .background(Color.black)
}

#Preview("Skin view: N64 with debug overlay") {
    DeltaSkinView(skin: PreviewFixtures.skin("Backbone-N64"), traits: PreviewFixtures.portrait,
                  showDebugOverlay: true, showHitTestOverlay: true,
                  inputHandler: DeltaSkinPreviewInputHandler())
        .background(Color.black)
}

#Preview("Skin view: edit mode") {
    DeltaSkinView(skin: PreviewFixtures.skin("Backbone-SNES"), traits: PreviewFixtures.portrait,
                  inputHandler: DeltaSkinPreviewInputHandler(), isEditMode: .constant(true))
        .background(Color.black)
}

#Preview("Screens view") {
    GeometryReader { proxy in
        DeltaSkinScreensView(skin: PreviewFixtures.skin("Backbone-NES"), traits: PreviewFixtures.portrait,
                             containerSize: proxy.size)
    }
}

#Preview("Skin preview") {
    DeltaSkinPreview(skin: PreviewFixtures.skin("PocketTaco-GBA"), traits: PreviewFixtures.portrait)
}

#Preview("Skin test view") {
    NavigationStack {
        DeltaSkinTestView(skin: PreviewFixtures.skin("Backbone-GBA"))
    }
}

#Preview("Theme picker") {
    Form {
        DeltaSkinThemePickerView(skin: PreviewFixtures.themedSkin())
    }
}

#Preview("Skin cell") {
    SkinPreviewCell(skin: PreviewFixtures.skin("Backbone-GBA"), manager: PreviewFixtures.makeManager())
        .frame(width: 180, height: 320)
        .padding()
        .background(Color.black)
}

#Preview("Skin list") {
    NavigationStack {
        DeltaSkinListView(manager: PreviewFixtures.makeManager())
    }
}

#Preview("System picker") {
    // The pickers read the shared manager when they are created, so install the fixtures first.
    let _ = PreviewFixtures.installSharedPreviewEnvironment()
    NavigationStack {
        SystemSkinBrowserView()
    }
}

#Preview("Skin selection: GBA") {
    let _ = PreviewFixtures.installSharedPreviewEnvironment()
    NavigationStack {
        SystemSkinSelectionView(system: PreviewFixtures.systems[0])
    }
}

#Preview("Catalog entry") {
    NavigationStack {
        SkinCatalogDetailView(entry: PreviewFixtures.catalogEntry)
    }
}
#endif
