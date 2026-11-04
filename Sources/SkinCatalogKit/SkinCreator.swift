import Foundation

/// One creator in `https://emuskins.com/creators.json` (creator profiles spec §2 and §7).
///
/// The directory carries a record for every author, claimed or not. An unclaimed author is a
/// minimal record: `slug`, `displayName`, `aliases: [author]`, `claimed: false`, and sometimes an
/// `avatarURL`. A claimed creator adds a bio, links and socials from their hand-edited
/// `creators/<slug>.json`.
///
/// Decoding is lenient in the same way as ``SkinCatalogEntry``: only `slug` is required, and a
/// field of the wrong type drops that field rather than the creator. Profile text is plain text.
/// Show `bio` and `displayName` as `Text`, never as Markdown or HTML.
public struct SkinCreator: Decodable, Sendable, Hashable, Identifiable {
    /// The stable id: the file name under `creators/` and the value of an entry's `creator` key.
    public var slug: String
    public var displayName: String
    /// The exact catalog `author` strings that belong to this creator.
    public var aliases: [String]
    /// True once the creator proved ownership of the profile. False for the minimal record the
    /// build writes for every unclaimed author.
    public var isClaimed: Bool
    /// The GitHub account that proved the claim, when the build publishes it.
    public var githubLogin: String?
    /// Plain text, 500 characters at most upstream.
    public var bio: String?
    /// The mirrored copy the build publishes, never the creator's original URL. `https` only.
    public var avatarURL: URL?
    public var bannerURL: URL?
    /// At most 6 upstream. `https` only.
    public var links: [SkinCreatorLink]
    /// Handles keyed by platform, in ``SkinCreatorSocial/Platform`` declaration order. Keys outside
    /// the fixed set are dropped.
    public var socials: [SkinCreatorSocial]
    public var stats: SkinCreatorStats?
    public var badges: [SkinCreatorBadge]
    /// Catalog entry ids the build attributed to this creator. Informational: the apps resolve a
    /// creator's skins through ``SkinCreatorIndex/skins(by:in:)`` so an old catalog still works.
    public var skinIds: [String]

    public var id: String {
        slug
    }

    public init(
        slug: String,
        displayName: String? = nil,
        aliases: [String] = [],
        isClaimed: Bool = false,
        githubLogin: String? = nil,
        bio: String? = nil,
        avatarURL: URL? = nil,
        bannerURL: URL? = nil,
        links: [SkinCreatorLink] = [],
        socials: [SkinCreatorSocial] = [],
        stats: SkinCreatorStats? = nil,
        badges: [SkinCreatorBadge] = [],
        skinIds: [String] = []
    ) {
        self.slug = slug
        self.displayName = displayName ?? slug
        self.aliases = aliases
        self.isClaimed = isClaimed
        self.githubLogin = githubLogin
        self.bio = bio
        self.avatarURL = avatarURL
        self.bannerURL = bannerURL
        self.links = links
        self.socials = socials
        self.stats = stats
        self.badges = badges
        self.skinIds = skinIds
    }

    /// The record the apps show for an author the directory has no entry for: name and skins only.
    public static func minimal(slug: String, displayName: String? = nil) -> SkinCreator {
        SkinCreator(slug: slug, displayName: displayName, aliases: displayName.map { [$0] } ?? [])
    }

    private enum CodingKeys: String, CodingKey {
        case slug, displayName, aliases, claimed, githubLogin, bio, avatarURL, bannerURL
        case links, socials, stats, badges, skinIds, hidden
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawSlug = try container.decode(String.self, forKey: .slug).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawSlug.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .slug, in: container, debugDescription: "Empty slug")
        }
        slug = rawSlug

        func string(_ key: CodingKeys) -> String? {
            (try? container.decodeIfPresent(String.self, forKey: key))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }
        }

        displayName = string(.displayName) ?? rawSlug
        aliases = ((try? container.decodeIfPresent([String].self, forKey: .aliases)) ?? [])
            .filter { !$0.isEmpty }
        githubLogin = string(.githubLogin)
        stats = try? container.decodeIfPresent(SkinCreatorStats.self, forKey: .stats)
        badges = ((try? container.decodeIfPresent([Lossy<SkinCreatorBadge>].self, forKey: .badges)) ?? [])
            .compactMap(\.value)
        skinIds = (try? container.decodeIfPresent([String].self, forKey: .skinIds)) ?? []

        // `claimed` is written for unclaimed records; a claimed record may omit it, in which case
        // the stats block or the verifying GitHub account says so.
        let claimed = (try? container.decodeIfPresent(Bool.self, forKey: .claimed))
            ?? stats?.claimed
            ?? (githubLogin != nil)

        // A moderation hold (`hidden: true`) publishes nothing but the minimal record upstream. If a
        // build ever leaks the flag through, honour it here rather than show the held text.
        if (try? container.decodeIfPresent(Bool.self, forKey: .hidden)) == true {
            isClaimed = false
            bio = nil
            avatarURL = nil
            bannerURL = nil
            links = []
            socials = []
            return
        }

        isClaimed = claimed
        bio = string(.bio)
        avatarURL = string(.avatarURL).flatMap(Self.httpsURL(from:))
        bannerURL = string(.bannerURL).flatMap(Self.httpsURL(from:))
        links = ((try? container.decodeIfPresent([Lossy<SkinCreatorLink>].self, forKey: .links)) ?? [])
            .compactMap(\.value)

        let handles = (try? container.decodeIfPresent([String: String].self, forKey: .socials)) ?? [:]
        socials = SkinCreatorSocial.Platform.allCases.compactMap { platform in
            handles[platform.rawValue].flatMap { SkinCreatorSocial(platform: platform, handle: $0) }
        }
    }

    /// `https` URLs only (spec §1): the build mirrors images and allow-lists links, and the apps
    /// refuse anything else even if a file slips through.
    static func httpsURL(from raw: String) -> URL? {
        guard let url = SkinCatalogEntry.url(from: raw),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty
        else {
            return nil
        }
        return url
    }
}

/// Swallows one element's decode failure so the array as a whole survives.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// A `{label, url}` pair from a creator's `links` (at most 6 upstream, `https` only).
public struct SkinCreatorLink: Decodable, Sendable, Hashable {
    public var label: String
    public var url: URL

    public init(label: String, url: URL) {
        self.label = label
        self.url = url
    }

    private enum CodingKeys: String, CodingKey {
        case label, url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawURL = try container.decode(String.self, forKey: .url)
        guard let url = SkinCreator.httpsURL(from: rawURL) else {
            throw DecodingError.dataCorruptedError(
                forKey: .url,
                in: container,
                debugDescription: "Link URL must be https: '\(rawURL)'"
            )
        }
        self.url = url
        let label = (try? container.decodeIfPresent(String.self, forKey: .label))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = (label?.isEmpty == false ? label : nil) ?? url.host ?? url.absoluteString
    }
}

/// A social handle. The file holds handles, never URLs (spec §1), so the apps build the link from a
/// fixed table and a creator cannot dress an arbitrary URL up as a Discord icon.
public struct SkinCreatorSocial: Sendable, Hashable, Identifiable {
    /// The fixed key set from creator profiles spec §1. Raw values are the JSON keys.
    public enum Platform: String, CaseIterable, Sendable, Hashable {
        case github, discord, x, bluesky, mastodon, instagram, youtube, twitch, tiktok
        case kofi, patreon, buymeacoffee, deltastyles, reddit

        /// A short display name for accessibility labels.
        public var title: String {
            switch self {
            case .github: "GitHub"
            case .discord: "Discord"
            case .x: "X"
            case .bluesky: "Bluesky"
            case .mastodon: "Mastodon"
            case .instagram: "Instagram"
            case .youtube: "YouTube"
            case .twitch: "Twitch"
            case .tiktok: "TikTok"
            case .kofi: "Ko-fi"
            case .patreon: "Patreon"
            case .buymeacoffee: "Buy Me a Coffee"
            case .deltastyles: "DeltaStyles"
            case .reddit: "Reddit"
            }
        }

        /// An SF Symbol that exists on iOS 17 and tvOS 17. SF Symbols has no brand glyphs, so these
        /// are the closest generic ones; an app that ships brand icons keys off ``rawValue``.
        public var symbolName: String {
            switch self {
            case .github: "chevron.left.forwardslash.chevron.right"
            case .discord: "bubble.left.and.bubble.right"
            case .x: "at"
            case .bluesky: "cloud"
            case .mastodon: "at.circle"
            case .instagram: "camera"
            case .youtube, .twitch: "play.rectangle"
            case .tiktok: "music.note"
            case .kofi, .buymeacoffee: "cup.and.saucer"
            case .patreon: "heart"
            case .deltastyles: "gamecontroller"
            case .reddit: "bubble.left"
            }
        }
    }

    public var platform: Platform
    /// The handle as published, without a leading `@`. For Mastodon it is `user@host`.
    public var handle: String

    public var id: String {
        platform.rawValue
    }

    /// Nil when the handle is empty after trimming.
    public init?(platform: Platform, handle: String) {
        var trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("@") {
            trimmed.removeFirst()
        }
        guard !trimmed.isEmpty else { return nil }
        self.platform = platform
        self.handle = trimmed
    }

    public var title: String {
        platform.title
    }

    public var symbolName: String {
        platform.symbolName
    }

    /// The profile URL built from the handle, or nil when the platform has none (Discord handles
    /// have no stable URL) or the handle does not fit the platform.
    ///
    /// Each handle is percent-encoded to unreserved characters, so it can only ever fill the path
    /// segment it was meant for.
    public var url: URL? {
        switch platform {
        case .discord:
            return nil
        case .mastodon:
            let parts = handle.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
                  let user = Self.encode(String(parts[0])), let host = Self.hostName(String(parts[1]))
            else {
                return nil
            }
            return URL(string: "https://\(host)/@\(user)")
        default:
            guard let encoded = Self.encode(handle) else { return nil }
            let template: String = switch platform {
            case .github: "https://github.com/"
            case .x: "https://x.com/"
            case .bluesky: "https://bsky.app/profile/"
            case .instagram: "https://www.instagram.com/"
            case .youtube: "https://www.youtube.com/@"
            case .twitch: "https://www.twitch.tv/"
            case .tiktok: "https://www.tiktok.com/@"
            case .kofi: "https://ko-fi.com/"
            case .patreon: "https://www.patreon.com/"
            case .buymeacoffee: "https://www.buymeacoffee.com/"
            // The profile URL shape is unverified (creator profiles spec, "What exists today").
            case .deltastyles: "https://deltastyles.com/user/"
            case .reddit: "https://www.reddit.com/user/"
            case .discord, .mastodon: ""
            }
            return URL(string: template + encoded)
        }
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func encode(_ value: String) -> String? {
        value.addingPercentEncoding(withAllowedCharacters: unreserved)
    }

    /// A hostname of letters, digits, dots and hyphens, or nil.
    private static func hostName(_ value: String) -> String? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.")
        guard value.contains("."), value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return value.lowercased()
    }
}

/// The numbers the build computes per creator (gamification spec §2). Every field is optional so an
/// older or newer `creators.json` decodes; a field of the wrong type is nil.
public struct SkinCreatorStats: Decodable, Sendable, Hashable {
    /// Families plus ungrouped entries.
    public var releases: Int?
    /// Visible entries.
    public var files: Int?
    public var variantsCompleted: Int?
    /// Distinct system codes. Accepts a count or a list of codes.
    public var systems: Int?
    public var dualScreen: Int?
    public var firstAddedAt: Date?
    public var lastAddedAt: Date?
    /// 0 none, 1 at least 1k, 2 at least 10k, 3 at least 100k. Coarse by design.
    public var reachTier: Int?
    public var claimed: Bool?

    public init(
        releases: Int? = nil,
        files: Int? = nil,
        variantsCompleted: Int? = nil,
        systems: Int? = nil,
        dualScreen: Int? = nil,
        firstAddedAt: Date? = nil,
        lastAddedAt: Date? = nil,
        reachTier: Int? = nil,
        claimed: Bool? = nil
    ) {
        self.releases = releases
        self.files = files
        self.variantsCompleted = variantsCompleted
        self.systems = systems
        self.dualScreen = dualScreen
        self.firstAddedAt = firstAddedAt
        self.lastAddedAt = lastAddedAt
        self.reachTier = reachTier
        self.claimed = claimed
    }

    private enum CodingKeys: String, CodingKey {
        case releases, files, variantsCompleted, systems, dualScreen
        case firstAddedAt, lastAddedAt, reachTier, claimed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ key: CodingKeys) -> Int? {
            try? container.decodeIfPresent(Int.self, forKey: key)
        }
        releases = int(.releases)
        files = int(.files)
        variantsCompleted = int(.variantsCompleted)
        systems = int(.systems) ?? (try? container.decodeIfPresent([String].self, forKey: .systems))?.count
        dualScreen = int(.dualScreen)
        firstAddedAt = SkinCatalogDates.parse(try? container.decodeIfPresent(String.self, forKey: .firstAddedAt))
        lastAddedAt = SkinCatalogDates.parse(try? container.decodeIfPresent(String.self, forKey: .lastAddedAt))
        reachTier = int(.reachTier)
        claimed = try? container.decodeIfPresent(Bool.self, forKey: .claimed)
    }
}

/// A creator badge as labelled by the build (gamification spec §1 and §2). An id the app does not
/// know still has a `title` and `symbol` to show; with neither, show a generic icon and the id.
public struct SkinCreatorBadge: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String?
    public var detail: String?
    /// An SF Symbol name.
    public var symbol: String?
    public var tier: Int?
    public var earnedAt: Date?

    public init(
        id: String,
        title: String? = nil,
        detail: String? = nil,
        symbol: String? = nil,
        tier: Int? = nil,
        earnedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.tier = tier
        self.earnedAt = earnedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, description, symbol, tier, earnedAt
    }

    /// Accepts an object, or a bare id string.
    public init(from decoder: Decoder) throws {
        if let bare = try? decoder.singleValueContainer().decode(String.self) {
            guard !bare.isEmpty else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Empty badge id")
                )
            }
            self = SkinCreatorBadge(id: bare)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = try SkinCreatorBadge(
            id: container.decode(String.self, forKey: .id),
            title: try? container.decodeIfPresent(String.self, forKey: .title),
            detail: try? container.decodeIfPresent(String.self, forKey: .description),
            symbol: try? container.decodeIfPresent(String.self, forKey: .symbol),
            tier: try? container.decodeIfPresent(Int.self, forKey: .tier),
            earnedAt: SkinCatalogDates.parse(try? container.decodeIfPresent(String.self, forKey: .earnedAt))
        )
    }
}
