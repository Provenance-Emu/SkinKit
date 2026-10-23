// SkinKitManager: Import, install, storage and per-game/per-system skin selection. No UI.
//
// Moved from Provenance (`PVUI/.../DeltaSkins/Models`) and from iFly and iCube's skin store:
//
// - `DeltaSkinManager`: import, scan, list, delete, the persisted path index, and the
//   `skins(for:)` family (in plain values instead of `SystemIdentifier`).
// - `DeltaSkinPreferences` / `DeltaSkinSelectionManager`: per-system and per-game (id, md5, crc)
//   selection, per orientation, plus the in-memory session picks.
// - `SkinSystemOverrideRegistry`: `.skinmeta` sidecars and catalog-derived system overrides.
// - `SkinStoreInstaller`, `SkinStoreInstalledRecord`, `SkinStoreInstallState`, `SkinStorePrefs`:
//   the store's download → install pipeline and its record of what it installed.
// - `DeltaSkinStorage`, `DeltaSkinExporter`.
//
// What differs per app is injected: where skins live (`DeltaSkinManager.Configuration`), how the
// installed record is stored (`SkinStoreInstalledRecord.iFly` / `.iCube`), the store policy
// (`SkinStorePolicy.iFly` / `.iCube` from SkinCatalogKit), the install step, logging
// (`SkinManagerLog.logger`), and the few places Provenance reached into app code (case-controller
// skins, the device idiom).
//
// Not here, for SkinKitUI (#5): `DeltaSkinLoader` (a SwiftUI view model), skin preview-image
// caching, and anything that needs `UIImage`.

public enum SkinKitManager {
    /// Bumped when the module's public API changes.
    public static let version = "0.1.0"
}
