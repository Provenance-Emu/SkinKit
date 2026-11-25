#if canImport(UIKit)
import SwiftUI

/// Where the catalog screens (browser, skin page, store pieces) look their strings up.
///
/// The default is what a plain `Text("…")` does: the main bundle's `Localizable` table. An app
/// that keeps its strings elsewhere points this at its table once at launch (iCube: the `Core`
/// table). Keys are the English strings; a key the table lacks is shown as it is.
@MainActor
@frozen public enum SkinKitLocalization {
    public static var bundle: Bundle = .main
    /// `nil` is the bundle's default table, `Localizable`.
    public static var tableName: String?
}

extension Text {
    /// A catalog-screen string, looked up through ``SkinKitLocalization``.
    @MainActor
    init(catalog key: LocalizedStringKey) {
        self.init(key, tableName: SkinKitLocalization.tableName, bundle: SkinKitLocalization.bundle)
    }
}
#endif
