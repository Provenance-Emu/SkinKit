#if canImport(UIKit)
import SkinCatalogKit
import SkinKitCore
import SkinKitManager
import SwiftUI

/// "Follow" / "Following" toggle for a creator (follow creators spec §3). Reads and writes
/// ``CreatorFollowStore/shared``, so it stays in step with the shelf and with every other button for
/// the same creator, and with the user's other devices through iCloud.
///
/// Used in the creator profile header and on the credit row of the detail view. Deliberately not on
/// every card face.
struct SkinCreatorFollowButton: View {
    /// The creator's slug (`SkinCreator.slug`).
    let slug: String
    /// For the accessibility label ("Follow Starving Artist").
    var displayName: String?

    @ObservedObject private var store = CreatorFollowStore.shared

    private var isFollowing: Bool { store.isFollowing(slug) }

    var body: some View {
        let button = Button {
            if isFollowing {
                store.unfollow(slug)
            } else {
                store.follow(slug)
            }
        } label: {
            label
        }
        .accessibilityLabel(isFollowing ? "Unfollow \(displayName ?? slug)" : "Follow \(displayName ?? slug)")
        .accessibilityAddTraits(isFollowing ? .isSelected : [])
        #if os(tvOS)
        button.skinKitFocusButtonStyle(focusScale: 1.05, cornerRadius: 24)
        #else
        button.buttonStyle(.plain)
        #endif
    }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: isFollowing ? "checkmark" : "plus")
                .font(.system(size: fontSize - 2, weight: .bold))
            Text(isFollowing ? "Following" : "Follow")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
        }
        .foregroundColor(isFollowing ? .white.opacity(0.85) : .white)
        .padding(.horizontal, fontSize * 0.9)
        .padding(.vertical, fontSize * 0.45)
        .background(
            Capsule()
                .fill(Color.black.opacity(isFollowing ? 0.3 : 0.6))
                .overlay(
                    Capsule().strokeBorder(
                        isFollowing ? AnyShapeStyle(Color.white.opacity(0.3)) : AnyShapeStyle(SkinKitTheme.current.gradient),
                        lineWidth: isFollowing ? 0.5 : 1.5
                    )
                )
        )
    }

    #if os(tvOS)
    private let fontSize: CGFloat = 24
    #else
    private let fontSize: CGFloat = 13
    #endif
}

// MARK: - Shelf data

/// Builds the "New from creators you follow" shelf from what the browsers hold. Shared by the iOS and
/// tvOS browsers so both show the same shelf for the same catalog and follow set.
@MainActor
enum SkinFollowShelf {
    /// The shelf for the current follows.
    ///
    /// The shelf ignores the browser's search and filters: it is a property of the catalog, the follow
    /// set and the host's policy, not of what the grid happens to show.
    static func feed(
        catalog: SkinCatalog,
        creators: SkinCreatorIndex?,
        store: CreatorFollowStore,
        policy: SkinStorePolicy?,
        loadedSkins: [any DeltaSkinProtocol]
    ) -> SkinFollowFeed {
        let following = store.followedSlugs
        guard !following.isEmpty else { return SkinFollowFeed(items: []) }
        let directory = creators ?? .empty
        // Only the followed creators' entries can be on the shelf, so only those need the installed
        // check (it scans the loaded skins).
        let installed = Set(catalog.skins.filter { entry in
            guard let slug = directory.slug(for: entry), following.contains(slug) else { return false }
            return isCatalogSkinInstalled(entry, in: loadedSkins)
        }.map(\.id))
        return SkinFollowFeed.make(
            in: catalog,
            creators: directory,
            following: following,
            since: store.shelfSeenThrough,
            installed: installed,
            policy: policy
        )
    }
}
#endif
