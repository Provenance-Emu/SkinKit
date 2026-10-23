// SkinCatalogKit: Catalog models, the catalog service and store sections/policy. No UI.
//
// Moved from iFly's `Sources/Core/Skins/Store/` (lenient decoding, groupId) with iCube's additions
// (`gameTypeSuffix`, `sourceHost`, game-type-implied system codes) folded in. Per-app behaviour
// (which shelves exist, which systems land on them, how each retargets) is `SkinStorePolicy`
// configuration; `SkinStorePolicy.iFly` and `SkinStorePolicy.iCube` are the two presets.
//
// Not here: the installer, installed-record and install-state types. They need the skin library and
// belong to SkinKitManager.

public enum SkinCatalogKit {
    /// Bumped when the module's public API changes.
    public static let version = "0.1.0"
}
