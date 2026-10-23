import Foundation

/// UserDefaults keys owned by the skin store.
public enum SkinStorePrefs {
    /// `[catalog entry id: installed skin identifier]` for skins installed from
    /// the store, so the store can show "Installed" and notice a deleted skin.
    /// iFly's key; it is stored as a plist dictionary, not JSON.
    public static let installedIds = "iFly.skinStore.installedIds"
}

/// Persists which catalog entries the store has installed.
///
/// Keyed by catalog id, valued by the installed skin's identifier, so a skin
/// the user later deletes can be noticed (`SkinStoreInstaller.reconcileInstalled`)
/// instead of showing "Installed" forever.
///
/// The two apps stored this differently and each keeps reading its existing record unchanged:
/// - iFly: a `[String: String]` dictionary in `UserDefaults` under `SkinStorePrefs.installedIds`
///   (`init(defaults:)` / `.iFly(defaults:)`).
/// - iCube: a JSON object in `store.json`, beside the skin library's `selection.json`
///   (`init(fileURL:)` / `.iCube(rootURL:)`).
public struct SkinStoreInstalledRecord {
    /// File name of iCube's record inside the skin library's root folder
    /// (`SkinLibrary.storeRecordFileName`).
    public static let iCubeFileName = "store.json"

    private let loadRecord: () -> [String: String]
    private let saveRecord: ([String: String]) -> Void

    /// A record kept anywhere: `load` returns what is stored and `save` replaces it.
    public init(load: @escaping () -> [String: String], save: @escaping ([String: String]) -> Void) {
        loadRecord = load
        saveRecord = save
    }

    /// iFly's storage: a dictionary in `defaults`. Tests pass an isolated suite.
    public init(defaults: UserDefaults = .standard, key: String = SkinStorePrefs.installedIds) {
        self.init(
            load: { (defaults.dictionary(forKey: key) as? [String: String]) ?? [:] },
            save: { defaults.set($0, forKey: key) }
        )
    }

    /// iCube's storage: a JSON file.
    public init(fileURL: URL) {
        self.init(
            load: {
                guard let data = try? Data(contentsOf: fileURL) else { return [:] }
                return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
            },
            save: { record in
                try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let data = try? JSONEncoder().encode(record) else { return }
                try? data.write(to: fileURL, options: .atomic)
            }
        )
    }

    /// iFly's preset: `UserDefaults`, key `SkinStorePrefs.installedIds`.
    public static func iFly(defaults: UserDefaults = .standard) -> SkinStoreInstalledRecord {
        SkinStoreInstalledRecord(defaults: defaults)
    }

    /// iCube's preset: `<rootURL>/store.json`. `rootURL` is the skin library's root
    /// (`SkinLibrary.defaultRootURL()`).
    public static func iCube(rootURL: URL) -> SkinStoreInstalledRecord {
        SkinStoreInstalledRecord(fileURL: rootURL.appendingPathComponent(iCubeFileName))
    }

    public func load() -> [String: String] {
        loadRecord()
    }

    public func markInstalled(catalogId: String, skinIdentifier: String) {
        var current = load()
        current[catalogId] = skinIdentifier
        saveRecord(current)
    }

    public func remove(catalogIds: Set<String>) {
        guard !catalogIds.isEmpty else { return }
        var current = load()
        for id in catalogIds {
            current[id] = nil
        }
        saveRecord(current)
    }
}
