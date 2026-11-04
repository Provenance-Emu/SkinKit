import Foundation

/// One skin in the provenance-emu.com catalog.
///
/// Only `id`, `name` and `downloadURL` are required — without them there is
/// nothing to show or fetch. Every other field is decoded with `try?` so a type
/// drift in, say, `rating` drops that field rather than the skin.
public struct SkinCatalogEntry: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var author: String?
    /// The creator this entry belongs to, as the catalog build resolved it (`creator` in the feed):
    /// a hand-set per-entry override first, then the claimed profile whose aliases include `author`,
    /// then the slug of `author`. Nil in catalogs that predate creator profiles; resolve those with
    /// `SkinCreatorIndex.creator(for:)`, which derives the same slug locally.
    public var creatorSlug: String?
    /// Short system codes as the feed writes them (`dreamcast`, `mame`,
    /// `threeDS`). Mixed case in the wild; compare via `normalizedSystems`.
    public var systems: [String]
    public var gameTypeIdentifier: String?
    public var version: String?
    /// Where the skin is fetched from. Mostly third-party hosts — Apps download
    /// from here and never re-host.
    public var downloadURL: URL
    public var thumbnailURL: URL?
    public var screenshotURLs: [URL]
    public var tags: [String]
    public var deviceSupport: [String]
    public var downloadCount: Int?
    public var rating: Double?
    public var lastUpdated: Date?
    /// When the entry's file was first committed to the skins repo (catalog `addedAt`,
    /// `Provenance-Emu/skins#42`). Every entry carries it from that build on; older feeds omit it.
    public var addedAt: Date?
    public var fileSize: Int?
    /// Host attribution (`deltastyles.com`, `delta-skins.github.io`), or sometimes a GitHub
    /// `owner/repo`. Use `sourceHost` for display.
    public var source: String?
    public var description: String?
    public var submittedBy: String?
    public var submittedAt: Date?
    /// Packs (several skins from one upload) share a `groupId` and order by
    /// `groupOrder`. Both are null for standalone skins.
    public var groupId: String?
    public var groupOrder: Int?
    /// The variant's own name inside its `groupId` family ("Doom"), when the catalog has one.
    /// Catalog schema 3 (`Provenance-Emu/skins#26`). Older feeds omit it; use
    /// `SkinFamilyIndex.variantLabel(for:)` for a label that falls back the way the catalog's
    /// backfill derives it.
    public var variantLabel: String?
    /// Variants packed inside this one file (`altRepresentations`, `themes`, `gameOverrides`).
    /// Empty for split-file skins and for entries the catalog has not inspected.
    public var variants: [SkinCatalogVariant]
    /// For a file the catalog built by merging a family's split files into one (`merge_variants.py`,
    /// skin editing tools spec §3): the ids of the member entries it was merged from, base first.
    /// Empty for every other entry, and for feeds that predate merging. The merged entry shares the
    /// family's `groupId` so it sits in the family, but it duplicates the members it was built from,
    /// so ``SkinDownloadPlan`` never fetches it together with them.
    public var mergedFrom: [String]

    /// The date "recent" sorts and "new" markers use: `lastUpdated`, else `addedAt`.
    /// `lastUpdated` is set for a handful of entries; `addedAt` covers the rest (follow creators design §1).
    public var effectiveDate: Date? {
        lastUpdated ?? addedAt
    }

    /// True for a catalog-built merge of other entries (``mergedFrom`` is not empty).
    public var isMerged: Bool {
        !mergedFrom.isEmpty
    }

    /// `systems`, lowercased.
    public var normalizedSystems: [String] {
        systems.map { $0.lowercased() }
    }

    /// The last dot component of `gameTypeIdentifier`, lowercased (`ngc` for
    /// `public.aoshuang.game.ngc`), or nil when the feed has none. From iCube.
    public var gameTypeSuffix: String? {
        guard let identifier = gameTypeIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !identifier.isEmpty,
              let suffix = identifier.split(separator: ".").last
        else {
            return nil
        }
        return suffix.lowercased()
    }

    /// Where the skin is hosted, for the credit line. The feed's `source` is
    /// usually a host but sometimes an `owner/repo`; anything that is not a bare
    /// host falls back to the download URL's host. From iCube.
    public var sourceHost: String? {
        if let source = source?.trimmingCharacters(in: .whitespacesAndNewlines), Self.looksLikeHost(source) {
            return source.lowercased()
        }
        guard let host = downloadURL.host?.lowercased() else { return nil }
        return host.hasPrefix(Self.wwwPrefix) ? String(host.dropFirst(Self.wwwPrefix.count)) : host
    }

    private static let wwwPrefix = "www."

    private static func looksLikeHost(_ value: String) -> Bool {
        !value.isEmpty && value.contains(".") && !value.contains("/") && !value.contains(" ")
    }

    public init(
        id: String,
        name: String,
        author: String? = nil,
        creatorSlug: String? = nil,
        systems: [String],
        gameTypeIdentifier: String? = nil,
        version: String? = nil,
        downloadURL: URL,
        thumbnailURL: URL? = nil,
        screenshotURLs: [URL] = [],
        tags: [String] = [],
        deviceSupport: [String] = [],
        downloadCount: Int? = nil,
        rating: Double? = nil,
        lastUpdated: Date? = nil,
        addedAt: Date? = nil,
        fileSize: Int? = nil,
        source: String? = nil,
        description: String? = nil,
        submittedBy: String? = nil,
        submittedAt: Date? = nil,
        groupId: String? = nil,
        groupOrder: Int? = nil,
        variantLabel: String? = nil,
        variants: [SkinCatalogVariant] = [],
        mergedFrom: [String] = []
    ) {
        self.id = id
        self.name = name
        self.author = author
        self.creatorSlug = creatorSlug
        self.systems = systems
        self.gameTypeIdentifier = gameTypeIdentifier
        self.version = version
        self.downloadURL = downloadURL
        self.thumbnailURL = thumbnailURL
        self.screenshotURLs = screenshotURLs
        self.tags = tags
        self.deviceSupport = deviceSupport
        self.downloadCount = downloadCount
        self.rating = rating
        self.lastUpdated = lastUpdated
        self.addedAt = addedAt
        self.fileSize = fileSize
        self.source = source
        self.description = description
        self.submittedBy = submittedBy
        self.submittedAt = submittedAt
        self.groupId = groupId
        self.groupOrder = groupOrder
        self.variantLabel = variantLabel
        self.variants = variants
        self.mergedFrom = mergedFrom
    }

    private enum CodingKeys: String, CodingKey {
        case creatorSlug = "creator"
        case id, name, author, systems, gameTypeIdentifier, version, downloadURL
        case thumbnailURL, screenshotURLs, tags, deviceSupport, downloadCount, rating
        case lastUpdated, addedAt, fileSize, source, description, submittedBy, submittedAt
        case groupId, groupOrder, variantLabel, variants
        case mergedFrom
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)

        let rawDownload = try container.decode(String.self, forKey: .downloadURL)
        guard let download = Self.url(from: rawDownload) else {
            throw DecodingError.dataCorruptedError(
                forKey: .downloadURL,
                in: container,
                debugDescription: "Unusable downloadURL '\(rawDownload)'"
            )
        }
        downloadURL = download

        func string(_ key: CodingKeys) -> String? {
            try? container.decodeIfPresent(String.self, forKey: key)
        }
        func strings(_ key: CodingKeys) -> [String] {
            (try? container.decodeIfPresent([String].self, forKey: key)) ?? []
        }

        author = string(.author)
        creatorSlug = string(.creatorSlug)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        systems = strings(.systems)
        gameTypeIdentifier = string(.gameTypeIdentifier)
        version = string(.version)
        thumbnailURL = string(.thumbnailURL).flatMap(Self.url(from:))
        screenshotURLs = strings(.screenshotURLs).compactMap(Self.url(from:))
        tags = strings(.tags)
        deviceSupport = strings(.deviceSupport)
        downloadCount = try? container.decodeIfPresent(Int.self, forKey: .downloadCount)
        rating = try? container.decodeIfPresent(Double.self, forKey: .rating)
        lastUpdated = SkinCatalogDates.parse(string(.lastUpdated))
        addedAt = SkinCatalogDates.parse(string(.addedAt))
        fileSize = try? container.decodeIfPresent(Int.self, forKey: .fileSize)
        source = string(.source)
        description = string(.description)
        submittedBy = string(.submittedBy)
        submittedAt = SkinCatalogDates.parse(string(.submittedAt))
        groupId = string(.groupId)
        groupOrder = try? container.decodeIfPresent(Int.self, forKey: .groupOrder)
        variantLabel = string(.variantLabel)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        // Lossy per item: one malformed variant drops that variant, not the skin.
        variants = ((try? container.decodeIfPresent([LossyVariant].self, forKey: .variants)) ?? [])
            .compactMap(\.variant)
        mergedFrom = strings(.mergedFrom).filter { !$0.isEmpty }
    }

    private struct LossyVariant: Decodable {
        let variant: SkinCatalogVariant?

        init(from decoder: Decoder) throws {
            variant = try? SkinCatalogVariant(from: decoder)
        }
    }

    /// Feed URLs are not always valid URL strings: two Donkey Kong panels carry
    /// raw spaces and a stray `\u{00C2}\u{00A0}`. Percent-encode as a fallback
    /// rather than dropping the entry.
    public static func url(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) else {
            return nil
        }
        return URL(string: encoded)
    }
}
