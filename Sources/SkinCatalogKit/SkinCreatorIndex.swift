import Foundation

/// The decoded `creators.json` (`{ "version": 1, "updated": ..., "creators": [...] }`), plus the
/// resolution rules that map a catalog entry to a creator.
///
/// Decodes the way ``SkinCatalog`` does: a creator record that fails is counted in
/// `droppedCreatorCount` and skipped. Everything here is synchronous and pure, so it is what the
/// tests exercise; ``SkinCreatorDirectory`` adds the fetching and caching.
public struct SkinCreatorIndex: Decodable, Sendable {
    public var version: Int?
    public var updated: Date?
    /// Read-only, so the list and the lookups built from it in `init` cannot disagree.
    public private(set) var creators: [SkinCreator]
    /// Records present in the file that could not be decoded.
    public var droppedCreatorCount: Int

    private let creatorsBySlug: [String: SkinCreator]
    private let slugsByAlias: [String: String]

    /// An index with no creators. Resolution then falls back to the local slug of each `author`,
    /// which is what a shipped app does against a catalog that predates creator profiles.
    public static let empty = SkinCreatorIndex(creators: [])

    public init(
        version: Int? = nil,
        updated: Date? = nil,
        creators: [SkinCreator],
        droppedCreatorCount: Int = 0
    ) {
        self.version = version
        self.updated = updated
        self.creators = creators
        self.droppedCreatorCount = droppedCreatorCount

        var bySlug: [String: SkinCreator] = [:]
        var byAlias: [String: String] = [:]
        for creator in creators {
            // The build rejects duplicates; if one slips through, the first record wins so
            // resolution is stable.
            if bySlug[creator.slug] == nil {
                bySlug[creator.slug] = creator
            }
            for alias in creator.aliases where byAlias[alias] == nil {
                byAlias[alias] = creator.slug
            }
        }
        creatorsBySlug = bySlug
        slugsByAlias = byAlias
    }

    private enum CodingKeys: String, CodingKey {
        case version, updated, creators
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lossy = try container.decodeIfPresent([Lossy<SkinCreator>].self, forKey: .creators) ?? []
        let decoded = lossy.compactMap(\.value)
        self.init(
            version: try? container.decodeIfPresent(Int.self, forKey: .version),
            updated: SkinCatalogDates.parse(try? container.decodeIfPresent(String.self, forKey: .updated)),
            creators: decoded,
            droppedCreatorCount: lossy.count - decoded.count
        )
    }

    /// Decode `creators.json` bytes. Throws `SkinCatalogError.decoding` when they are not a
    /// creator directory at all.
    public static func decode(_ data: Data) throws -> SkinCreatorIndex {
        do {
            return try JSONDecoder().decode(SkinCreatorIndex.self, from: data)
        } catch {
            throw SkinCatalogError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Lookup

    /// The directory's record for `slug`, or nil.
    public func creator(for slug: String) -> SkinCreator? {
        creatorsBySlug[slug]
    }

    /// The slug an entry resolves to, in this order (creator profiles spec §6 and §7):
    ///
    /// 1. The catalog's own `creator` (``SkinCatalogEntry/creatorSlug``). It already carries the
    ///    per-entry override, so it wins even when the entry's `author` is a claimed alias of a
    ///    different creator: "ClearDoom by NostromoCrew01" credits `starvingartist` but belongs
    ///    to `nostromocrew01`.
    /// 2. The creator whose `aliases` contain the entry's `author` exactly.
    /// 3. ``SkinCreatorSlug/make(from:)`` of the `author`.
    ///
    /// Nil when the entry has no `creator` and no author that slugs to anything.
    public func slug(for entry: SkinCatalogEntry) -> String? {
        if let slug = entry.creatorSlug {
            return slug
        }
        guard let raw = entry.author else { return nil }
        let author = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !author.isEmpty else { return nil }
        if let slug = slugsByAlias[raw] ?? slugsByAlias[author] {
            return slug
        }
        let local = SkinCreatorSlug.make(from: author)
        return local.isEmpty ? nil : local
    }

    /// The creator an entry belongs to, always a record the profile sheet can show.
    ///
    /// When the directory has no record for the resolved slug (an old or missing `creators.json`,
    /// or an author nobody has claimed and the build has not listed yet) this is a minimal record
    /// named after the entry's `author`, so tapping a credit never dead-ends. Nil only when
    /// ``slug(for:)`` is nil.
    public func creator(for entry: SkinCatalogEntry) -> SkinCreator? {
        guard let slug = slug(for: entry) else { return nil }
        if let known = creatorsBySlug[slug] {
            return known
        }
        let name = entry.author?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .minimal(slug: slug, displayName: (name?.isEmpty == false ? name : nil) ?? slug)
    }

    /// The catalog entries that resolve to `creator`, in catalog order.
    ///
    /// Resolves each entry rather than reading `skinIds`, so the override is honoured and an
    /// unclaimed author's skins are found without the build having listed them.
    public func skins(by creator: SkinCreator, in catalog: SkinCatalog) -> [SkinCatalogEntry] {
        skins(bySlug: creator.slug, in: catalog)
    }

    public func skins(bySlug slug: String, in catalog: SkinCatalog) -> [SkinCatalogEntry] {
        catalog.skins.filter { self.slug(for: $0) == slug }
    }
}
