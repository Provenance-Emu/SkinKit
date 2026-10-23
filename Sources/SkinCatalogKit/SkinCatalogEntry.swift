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
        fileSize: Int? = nil,
        source: String? = nil,
        description: String? = nil,
        submittedBy: String? = nil,
        submittedAt: Date? = nil,
        groupId: String? = nil,
        groupOrder: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.author = author
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
        self.fileSize = fileSize
        self.source = source
        self.description = description
        self.submittedBy = submittedBy
        self.submittedAt = submittedAt
        self.groupId = groupId
        self.groupOrder = groupOrder
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, author, systems, gameTypeIdentifier, version, downloadURL
        case thumbnailURL, screenshotURLs, tags, deviceSupport, downloadCount, rating
        case lastUpdated, fileSize, source, description, submittedBy, submittedAt
        case groupId, groupOrder
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
        fileSize = try? container.decodeIfPresent(Int.self, forKey: .fileSize)
        source = string(.source)
        description = string(.description)
        submittedBy = string(.submittedBy)
        submittedAt = SkinCatalogDates.parse(string(.submittedAt))
        groupId = string(.groupId)
        groupOrder = try? container.decodeIfPresent(Int.self, forKey: .groupOrder)
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
