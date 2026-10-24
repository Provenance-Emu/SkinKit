#if canImport(UIKit)
import SwiftUI

/// The look of the store and picker views.
///
/// Provenance styled these views with its RetroWave chrome (`RetroTheme`, `RetroPauseChrome`, `.retroAlert`,
/// `.retroFocusButtonStyle`, `.retroPauseSectionHeaderTypography`), which lives in app UI code. The views
/// read this value instead. The default has the same palette and metrics as RetroWave and plain system
/// alerts, buttons and type, so the module looks right on its own; an app that has a richer chrome sets
/// ``current`` once at launch (Provenance: map `RetroTheme` and `.retroAlert` onto the closures).
public struct SkinKitTheme: @unchecked Sendable {
    // MARK: Colors
    public var pink = Color(red: 0.94, green: 0.49, blue: 0.71)
    public var purple = Color(red: 0.69, green: 0.55, blue: 0.91)
    public var blue = Color(red: 0.40, green: 0.80, blue: 0.90)
    public var darkBlue = Color(red: 0.14, green: 0.12, blue: 0.20)
    public var black = Color(red: 0.08, green: 0.07, blue: 0.11)
    /// `Color.retroCyan`.
    public var cyan = Color(red: 0.40, green: 0.80, blue: 0.90)

    // MARK: Gradients (pink, purple, blue)
    public var gradient: LinearGradient {
        LinearGradient(colors: [pink, purple, blue], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    public var horizontalGradient: LinearGradient {
        LinearGradient(colors: [pink, purple, blue], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: Chrome metrics (`RetroPauseChrome`)
    public var radiusSM: CGFloat = 6
    public var menuCellFillOpacityUnfocused: Double = 0.10
    public var menuCellFillOpacityFocused: Double = 0.22
    public var menuCellStrokeOpacityUnfocused: Double = 0.35
    public var menuCellStrokeOpacityFocused: Double = 0.85
    public var menuCellStrokeWidthUnfocused: CGFloat = 1
    public var menuCellStrokeWidthFocused: CGFloat = 2
    public var sectionTitleMutedOpacity: Double = 0.45
    public var panelCornerRadius: CGFloat = 10
    public var panelStrokeLineWidth: CGFloat = 1.5
    public var panelFillOpacityDark: Double = 0.88
    public var panelFillOpacityLight: Double = 0.9

    // MARK: Styling hooks

    /// Full-screen backdrop behind the pickers (`RetroTheme.retroBackground`).
    public var background: @MainActor () -> AnyView = { AnyView(Color(red: 0.08, green: 0.07, blue: 0.11).ignoresSafeArea()) }

    /// Presents an alert (`.retroAlert(title, message:, isPresented:, actions)`). Arguments: the content, the
    /// title, the message, the presentation binding and the actions. The default is a system alert.
    public var alert: @MainActor (_ content: AnyView, _ title: String, _ message: String, _ isPresented: Binding<Bool>, _ actions: AnyView) -> AnyView = {
        content, title, message, isPresented, actions in
        AnyView(content.alert(title, isPresented: isPresented, actions: { actions }, message: { Text(message) }))
    }

    /// Focus styling for tvOS buttons (`.retroFocusButtonStyle(focusScale:cornerRadius:)`). The default is a plain button.
    public var focusButtonStyle: @MainActor (_ content: AnyView, _ focusScale: CGFloat, _ cornerRadius: CGFloat, _ showBorder: Bool) -> AnyView = {
        content, _, _, _ in AnyView(content.buttonStyle(.plain))
    }

    /// Typography of section headers (`.retroPauseSectionHeaderTypography()`).
    public var sectionHeaderTypography: @MainActor (_ content: AnyView) -> AnyView = { content in
        #if os(tvOS)
        AnyView(content.font(.system(size: 13, weight: .heavy)).tracking(2.5))
        #else
        AnyView(content.font(.system(size: 9, weight: .heavy)).tracking(1.5))
        #endif
    }

    public init() {}

    private static let lock = NSLock()
    private static var _current = SkinKitTheme()

    /// The theme in effect. Set once at launch.
    public static var current: SkinKitTheme {
        get { lock.withLock { _current } }
        set { lock.withLock { _current = newValue } }
    }
}

extension View {
    /// `.retroAlert(_:message:isPresented:actions:)`, through ``SkinKitTheme/alert``.
    @MainActor
    func skinKitAlert<Actions: View>(
        _ title: String,
        message: String,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        SkinKitTheme.current.alert(AnyView(self), title, message, isPresented, AnyView(actions()))
    }

    /// `.retroFocusButtonStyle(focusScale:cornerRadius:)`, through ``SkinKitTheme/focusButtonStyle``.
    @MainActor
    func skinKitFocusButtonStyle(focusScale: CGFloat = 1.08, cornerRadius: CGFloat = 12, showBorder: Bool = true) -> some View {
        SkinKitTheme.current.focusButtonStyle(AnyView(self), focusScale, cornerRadius, showBorder)
    }

    /// `.retroPauseSectionHeaderTypography()`, through ``SkinKitTheme/sectionHeaderTypography``.
    @MainActor
    func skinKitSectionHeaderTypography() -> some View {
        SkinKitTheme.current.sectionHeaderTypography(AnyView(self))
    }
}

/// Panel backdrop (`RetroPausePanelBackground`), drawn from the theme's tokens.
struct SkinKitPanelBackground: View {
    let isDark: Bool

    var body: some View {
        let theme = SkinKitTheme.current
        RoundedRectangle(cornerRadius: theme.panelCornerRadius)
            .fill(isDark ? Color.black.opacity(theme.panelFillOpacityDark) : Color.white.opacity(theme.panelFillOpacityLight))
            .overlay(
                RoundedRectangle(cornerRadius: theme.panelCornerRadius)
                    .strokeBorder(
                        LinearGradient(colors: [theme.purple.opacity(0.65), theme.pink.opacity(0.65)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: theme.panelStrokeLineWidth)
            )
    }
}

/// Small count pill (`RetroPauseInsetPillBackground`), drawn from the theme's tokens.
struct SkinKitInsetPillBackground: View {
    let isDark: Bool

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(isDark ? 0.06 : 0.12))
            .overlay(Capsule().strokeBorder(SkinKitTheme.current.cyan.opacity(0.55), lineWidth: 1))
    }
}

/// Debug flags for the skin touch view.
public enum DeltaSkinInputDiagnostics {
    /// Set once the first multi-touch after a resume has been logged. The app resets it on resume
    /// (Provenance: `InputDiagnostics.hasLoggedMultiTouch`).
    public static var hasLoggedMultiTouch = false
}
#endif
