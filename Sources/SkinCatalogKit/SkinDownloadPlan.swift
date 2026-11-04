import Foundation

/// What to fetch to install a chosen set of family members: one download per member file.
///
/// A split-file member is one URL. A single-file member is also one URL, and that one file brings
/// all of its own `variants`, so a mixed family needs exactly one request per member file. Two
/// members that point at the same URL download once. "Install all" is a client-side loop over
/// `entries` (spec §2/§3): no server-built zip, and every file keeps its own download count.
///
/// Run the plan sequentially: most multi-file families are hosted on deltastyles.com, which
/// rate-limits.
///
/// **A merged file is never fetched with the members it was merged from.** The catalog can publish
/// one extra entry per family that packs all the split members into a single file
/// (``SkinCatalogEntry/mergedFrom``).
/// Installing it beside the members it came from gives the player the same skin twice, so the
/// plan drops a merged entry whenever any of its source members is also in the plan: "Install all"
/// fetches the N split files, never N+1. A merged entry is kept when it is alone (the user picked
/// it) or when none of its sources survived the policy filter (it is the only choice).
public struct SkinDownloadPlan: Sendable, Hashable {
    /// The entries to download, in family order, one per distinct URL.
    public let entries: [SkinCatalogEntry]

    /// - Parameters:
    ///   - entries: the chosen members, in the order to fetch them.
    ///   - policy: when given, members the policy can't install (a `.zip`, an extensionless link,
    ///     a hidden or tag-hidden entry) are dropped. Provenance, which imports zips, passes `nil`.
    public init(entries: [SkinCatalogEntry], policy: SkinStorePolicy? = nil) {
        let installable = entries.filter { entry in
            guard let policy else { return true }
            return policy.section(for: entry) != nil
        }
        let ids = Set(installable.map(\.id))
        var seen = Set<URL>()
        self.entries = installable.filter { entry in
            if entry.isMerged, !ids.isDisjoint(with: entry.mergedFrom.filter { $0 != entry.id }) {
                return false
            }
            return seen.insert(entry.downloadURL).inserted
        }
    }

    /// The URLs to fetch, one per entry.
    public var urls: [URL] { entries.map(\.downloadURL) }

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    /// The plan without the entries in `installedIds` (catalog ids already installed).
    public func excluding(installedIds: Set<String>) -> SkinDownloadPlan {
        SkinDownloadPlan(entries: entries.filter { !installedIds.contains($0.id) })
    }
}

public extension SkinFamily {
    /// The plan for the members whose ids are in `memberIds`, or for every member when `nil`
    /// ("Install all"). Members keep family order whatever order the ids came in.
    ///
    /// A merged member (``SkinCatalogEntry/mergedFrom``) is left out when the choice also holds a
    /// member it was merged from, so "Install all" fetches the split files only. It is the whole
    /// plan when it is chosen alone, or when it is the only installable member.
    func downloadPlan(memberIds: Set<String>? = nil, policy: SkinStorePolicy? = nil) -> SkinDownloadPlan {
        let chosen = memberIds.map { ids in members.filter { ids.contains($0.id) } } ?? members
        return SkinDownloadPlan(entries: chosen, policy: policy)
    }

    /// The plan for one member.
    func downloadPlan(for member: SkinCatalogEntry, policy: SkinStorePolicy? = nil) -> SkinDownloadPlan {
        downloadPlan(memberIds: [member.id], policy: policy)
    }
}
