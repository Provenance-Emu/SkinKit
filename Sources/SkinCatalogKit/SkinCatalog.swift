import Foundation

/// The provenance-emu.com skin catalog (`/skins/catalog.json`, schema version 2).
///
/// Decodes the feed as it really is, not as it is documented: nearly every
/// field is nullable, and one malformed entry must never cost the user the
/// other 1,357. `skins` therefore decodes lossily: an entry that fails is
/// counted in `droppedEntryCount` and skipped.
///
/// Decodable only. The service caches the server's bytes verbatim, so there is
/// no second, re-encoded schema to keep in step with the feed.
public struct SkinCatalog: Decodable, Sendable {
    public var version: Int?
    public var lastUpdated: Date?
    public var totalSkins: Int?
    public var skins: [SkinCatalogEntry]
    /// Entries present in the feed that could not be decoded.
    public var droppedEntryCount: Int

    public init(
        version: Int? = nil,
        lastUpdated: Date? = nil,
        totalSkins: Int? = nil,
        skins: [SkinCatalogEntry],
        droppedEntryCount: Int = 0
    ) {
        self.version = version
        self.lastUpdated = lastUpdated
        self.totalSkins = totalSkins
        self.skins = skins
        self.droppedEntryCount = droppedEntryCount
    }

    private enum CodingKeys: String, CodingKey {
        case version, lastUpdated, totalSkins, skins
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try? container.decodeIfPresent(Int.self, forKey: .version)
        lastUpdated = SkinCatalogDates.parse(try? container.decodeIfPresent(String.self, forKey: .lastUpdated))
        totalSkins = try? container.decodeIfPresent(Int.self, forKey: .totalSkins)

        let lossy = try container.decodeIfPresent([LossyEntry].self, forKey: .skins) ?? []
        skins = lossy.compactMap(\.entry)
        droppedEntryCount = lossy.count - skins.count
    }

    /// Decode feed bytes. Shared by the network and disk paths so both apply the
    /// same lossy rules. Throws `SkinCatalogError.decoding` when the bytes are
    /// not a catalog at all.
    public static func decode(_ data: Data) throws -> SkinCatalog {
        do {
            return try JSONDecoder().decode(SkinCatalog.self, from: data)
        } catch {
            throw SkinCatalogError.decoding(error.localizedDescription)
        }
    }

    /// Swallows one entry's decode failure so the array as a whole survives.
    private struct LossyEntry: Decodable {
        let entry: SkinCatalogEntry?

        init(from decoder: Decoder) throws {
            entry = try? SkinCatalogEntry(from: decoder)
        }
    }
}
