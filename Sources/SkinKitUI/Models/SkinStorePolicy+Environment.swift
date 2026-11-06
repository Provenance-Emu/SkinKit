#if canImport(UIKit)
import SkinCatalogKit
import SwiftUI

private struct SkinStorePolicyKey: EnvironmentKey {
    static let defaultValue: SkinStorePolicy? = nil
}

public extension EnvironmentValues {
    /// The host app's store policy, for the views that list a slice of the catalog on their own
    /// (today the creator profile sheet). Set it once on the store's root view:
    /// `.environment(\.skinStorePolicy, .iCube)`.
    ///
    /// `nil` (the default) means "no shelves": only ``SkinContentVisibility`` applies, which is what
    /// the catalog browser shows today. With a policy, the sheet lists only the skins the policy
    /// places on a shelf and can install.
    var skinStorePolicy: SkinStorePolicy? {
        get { self[SkinStorePolicyKey.self] }
        set { self[SkinStorePolicyKey.self] = newValue }
    }
}
#endif
