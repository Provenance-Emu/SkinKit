// SkinKitUI: SwiftUI skin rendering and store/picker views for iOS and tvOS.
//
// Everything that draws or lays out UIKit/SwiftUI is behind `#if canImport(UIKit)`, so the package still
// builds on the macOS test host (where this module is empty apart from `SkinKitUI.version`).
//
// What the host app plugs in (all set once at launch; none has a Provenance-only default):
// - `DeltaSkinRenderable`: the refining protocol `DeltaSkin` conforms to for image(for:), thumbnail and thumbstick art.
// - `DeltaSkinRendering.defaultSkinProvider`: the skin to fall back to when a skin's artwork cannot be read.
// - `DeltaSkinInputHandling`: where button, stick and DS-touch events go (the emulator, in an app).
// - `DeltaSkinInteractionSettings`: vibration, sound, turbo, sticky and multi-button-touch settings.
// - `DeltaSkinSystemDirectory`: the systems the app knows, for names, catalog codes and families.
// - `SkinKitTheme`: colors, metrics, alerts and focus styling for the picker and store views.

#if canImport(SwiftUI)
import SwiftUI
#endif

public enum SkinKitUI {
    /// Bumped when the module's public API changes.
    public static let version = "0.2.0"
}
