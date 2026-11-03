import Foundation
import SkinCatalogKit

/// UserDefaults keys owned by the skin store.
public enum SkinStorePrefs {
    /// `[catalog entry id: installed skin identifier]` for skins installed from
    /// the store, so the store can show "Installed" and notice a deleted skin.
    /// iFly's key; it is stored as a plist dictionary, not JSON.
    public static let installedIds = "iFly.skinStore.installedIds"

    /// `[catalog entry id: SkinFamilyMembership]` as JSON data: the variant family of each skin
    /// installed from the store. Kept beside `installedIds`, not inside it, so builds from before
    /// families still read `installedIds` as `[String: String]`.
    public static let installedFamilies = "iFly.skinStore.installedFamilies"
}

/// Persists which catalog entries the store has installed, and the variant family each belongs to.
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
///
/// Family memberships (`groupId`, `groupOrder`, `variantLabel`) live in a parallel store
/// (`SkinStorePrefs.installedFamilies`, iCube's `store-families.json`). A catalog id with no
/// membership was installed before families existed; `memberships(migratingWith:)` fills it in
/// from the catalog.
public struct SkinStoreInstalledRecord {
    /// File name of iCube's record inside the skin library's root folder
    /// (`SkinLibrary.storeRecordFileName`).
    public static let iCubeFileName = "store.json"
    /// File name of iCube's family memberships, beside `store.json`.
    public static let iCubeFamiliesFileName = "store-families.json"

    private let loadRecord: () -> [String: String]
    private let saveRecord: ([String: String]) -> Void
    private let loadFamilies: () -> [String: SkinFamilyMembership]
    private let saveFamilies: ([String: SkinFamilyMembership]) -> Void

    /// A record kept anywhere: `load` returns what is stored and `save` replaces it. Family
    /// memberships go through `loadFamilies` / `saveFamilies`; without them they are kept in memory
    /// for the life of this value's storage only.
    public init(
        load: @escaping () -> [String: String],
        save: @escaping ([String: String]) -> Void,
        loadFamilies: (() -> [String: SkinFamilyMembership])? = nil,
        saveFamilies: (([String: SkinFamilyMembership]) -> Void)? = nil
    ) {
        loadRecord = load
        saveRecord = save
        if let loadFamilies, let saveFamilies {
            self.loadFamilies = loadFamilies
            self.saveFamilies = saveFamilies
        } else {
            let box = MembershipBox()
            self.loadFamilies = { box.value }
            self.saveFamilies = { box.value = $0 }
        }
    }

    /// iFly's storage: a dictionary in `defaults`, and the memberships as JSON data under
    /// `familiesKey`. Tests pass an isolated suite.
    public init(
        defaults: UserDefaults = .standard,
        key: String = SkinStorePrefs.installedIds,
        familiesKey: String = SkinStorePrefs.installedFamilies
    ) {
        self.init(
            load: { (defaults.dictionary(forKey: key) as? [String: String]) ?? [:] },
            save: { defaults.set($0, forKey: key) },
            loadFamilies: { Self.decodeFamilies(defaults.data(forKey: familiesKey)) },
            saveFamilies: { defaults.set(Self.encodeFamilies($0), forKey: familiesKey) }
        )
    }

    /// iCube's storage: a JSON file, and the memberships in `familiesFileURL` (default: beside it,
    /// named `store-families.json`).
    public init(fileURL: URL, familiesFileURL: URL? = nil) {
        let familiesURL = familiesFileURL
            ?? fileURL.deletingLastPathComponent().appendingPathComponent(Self.iCubeFamiliesFileName)
        self.init(
            load: {
                guard let data = try? Data(contentsOf: fileURL) else { return [:] }
                return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
            },
            save: { record in
                try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let data = try? JSONEncoder().encode(record) else { return }
                try? data.write(to: fileURL, options: .atomic)
            },
            loadFamilies: { Self.decodeFamilies(try? Data(contentsOf: familiesURL)) },
            saveFamilies: { families in
                try? FileManager.default.createDirectory(at: familiesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let data = Self.encodeFamilies(families) else { return }
                try? data.write(to: familiesURL, options: .atomic)
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

    /// Record an install from the store together with its family membership.
    ///
    /// - Parameter index: the whole catalog's family index, so the stored label is the one the
    ///   store showed.
    public func markInstalled(entry: SkinCatalogEntry, skinIdentifier: String, index: SkinFamilyIndex? = nil) {
        markInstalled(catalogId: entry.id, skinIdentifier: skinIdentifier)
        var families = loadFamilies()
        families[entry.id] = SkinFamilyMembership(entry: entry, index: index)
        saveFamilies(families)
    }

    public func remove(catalogIds: Set<String>) {
        guard !catalogIds.isEmpty else { return }
        var current = load()
        for id in catalogIds {
            current[id] = nil
        }
        saveRecord(current)

        var families = loadFamilies()
        let before = families.count
        for id in catalogIds {
            families[id] = nil
        }
        if families.count != before {
            saveFamilies(families)
        }
    }

    // MARK: - Families

    /// Stored memberships by catalog id, as they are (no migration).
    public func storedMemberships() -> [String: SkinFamilyMembership] {
        loadFamilies()
    }

    /// Memberships for every installed catalog id, migrating records from before families.
    ///
    /// A catalog id with no stored membership is matched by id against `catalog`: found, it takes
    /// that entry's family; not found, it is stored as standalone. Either way the result is saved,
    /// so it is looked up once. With no catalog nothing is saved and the id is left out (standalone
    /// for now, retried next time).
    public func memberships(migratingWith catalog: SkinCatalog?) -> [String: SkinFamilyMembership] {
        let installed = load()
        var families = loadFamilies()
        let missing = installed.keys.filter { families[$0] == nil }
        if !missing.isEmpty, let catalog {
            let index = catalog.familyIndex
            let byId = Dictionary(catalog.skins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for id in missing {
                families[id] = byId[id].map { SkinFamilyMembership(entry: $0, index: index) } ?? .standalone
            }
            saveFamilies(families)
        }
        return families.filter { installed[$0.key] != nil }
    }

    /// Memberships keyed by installed skin identifier, for grouping a picker. Standalone skins are
    /// left out. See `memberships(migratingWith:)`.
    public func membershipsBySkinIdentifier(migratingWith catalog: SkinCatalog?) -> [String: SkinFamilyMembership] {
        let installed = load()
        var result: [String: SkinFamilyMembership] = [:]
        for (catalogId, membership) in memberships(migratingWith: catalog) where !membership.isStandalone {
            if let identifier = installed[catalogId] {
                result[identifier] = membership
            }
        }
        return result
    }

    // MARK: - Coding

    private static func decodeFamilies(_ data: Data?) -> [String: SkinFamilyMembership] {
        guard let data else { return [:] }
        return (try? JSONDecoder().decode([String: SkinFamilyMembership].self, from: data)) ?? [:]
    }

    private static func encodeFamilies(_ families: [String: SkinFamilyMembership]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(families)
    }
}

/// In-memory family store for a record built from bare `load`/`save` closures.
private final class MembershipBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: [String: SkinFamilyMembership] = [:]

    var value: [String: SkinFamilyMembership] {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
