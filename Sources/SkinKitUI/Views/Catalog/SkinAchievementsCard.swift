#if canImport(UIKit)
import SkinCatalogKit
import SkinKitCore
import SkinKitManager
import SwiftUI

// MARK: - Options

/// Host switches for the achievements UI (gamification spec §3).
@MainActor
public enum SkinKitAchievements {
    /// Show a brief banner when a badge is earned. Off by default: the spec's choice is no popups, and
    /// a host that finds the card too quiet can turn this on per app without touching the data.
    public static var showsToasts = false
}

private struct SkinStoreInstalledRecordKey: EnvironmentKey {
    static let defaultValue: SkinStoreInstalledRecord? = nil
}

public extension EnvironmentValues {
    /// The app's record of installed catalog skins (`SkinStoreInstalledRecord.iFly()` or `.iCube(rootURL:)`),
    /// which the "Your skins" card counts installs from. Set it once on the store's root view. `nil`
    /// (the default) counts the loaded skins whose identifier is a catalog id instead, which misses
    /// skins an app names differently.
    var skinStoreInstalledRecord: SkinStoreInstalledRecord? {
        get { self[SkinStoreInstalledRecordKey.self] }
        set { self[SkinStoreInstalledRecordKey.self] = newValue }
    }
}

// MARK: - Card

/// The "Your skins" card (gamification spec §3): live stats from what the app stores, and the user's
/// badges, earned ones lit and locked ones greyed with what earns them.
///
/// It sits at the bottom of the store browser (iOS) and as the last row on tvOS; an app can also show
/// it from its skin settings. It refreshes the shared ``SkinAchievementTracker`` itself, so showing it
/// anywhere is enough. Nothing leaves the device except through the user's own iCloud.
public struct SkinAchievementsCard: View {
    @ObservedObject private var tracker = SkinAchievementTracker.shared
    @ObservedObject private var skinManager = DeltaSkinManager.shared
    @ObservedObject private var preferences = DeltaSkinPreferences.shared
    @ObservedObject private var follows = CreatorFollowStore.shared
    @Environment(\.skinStoreInstalledRecord) private var installedRecord

    @State private var catalog: SkinCatalog?
    @State private var creators: SkinCreatorIndex?
    @State private var themeChanges = 0

    public init() {}

    /// What the card's numbers depend on, so `.task(id:)` recomputes when any of it changes.
    private struct RefreshKey: Hashable {
        var installedCount: Int
        var selectedSkins: [SkinSystemID: [SkinOrientation: String]]
        var gameSpecificSkins: [String: [SkinOrientation: String]]
        var altRepresentations: [String: Set<String>]
        var followed: Set<String>
        var themeChanges: Int
        var catalogLoaded: Bool
        var creatorsLoaded: Bool
    }

    private var refreshKey: RefreshKey {
        RefreshKey(
            installedCount: skinManager.loadedSkins.count,
            selectedSkins: preferences.selectedSkins,
            gameSpecificSkins: preferences.gameSpecificSkins,
            altRepresentations: preferences.gameAltRepresentations,
            followed: follows.followedSlugs,
            themeChanges: themeChanges,
            catalogLoaded: catalog != nil,
            creatorsLoaded: creators != nil
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text("YOUR SKINS")
                .font(.system(size: titleSize, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(SkinKitTheme.current.horizontalGradient)

            statsGrid

            VStack(spacing: badgeSpacing) {
                ForEach(tracker.achievements()) { achievement in
                    badgeRow(achievement)
                }
            }
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.4))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(SkinKitTheme.current.gradient, lineWidth: 1))
        )
        #if os(tvOS)
        // A static card is not a focus target, so the remote could not scroll down to it.
        .focusable()
        #endif
        .accessibilityElement(children: .contain)
        .task {
            catalog = try? await SkinCatalogService.shared.visibleCatalog()
        }
        .task {
            creators = try? await SkinCreatorDirectory.shared.index()
        }
        .task(id: refreshKey) {
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: DeltaSkinThemeSelection.didChangeNotification)) { _ in
            themeChanges += 1
        }
    }

    private func refresh() {
        let fallback = Set(skinManager.loadedSkins.map(\.identifier))
        let inputs = tracker.currentInputs(
            installedRecord: installedRecord,
            installedFallbackIdentifiers: fallback,
            catalog: catalog,
            creators: creators ?? .empty,
            preferences: preferences,
            follows: follows
        )
        tracker.refresh(inputs)
    }

    // MARK: Stats

    private var statsGrid: some View {
        let stats = tracker.stats
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: statWidth), spacing: 10)], alignment: .leading, spacing: 10) {
            stat(stats.installed, "Installed")
            stat(stats.systemsTried, "Systems tried")
            stat(stats.creatorsFollowed, "Following")
            stat(stats.creatorsInstalledFrom, "Creators installed")
            stat(stats.familiesCompleted, "Sets completed")
            stat(stats.gamesCustomised, "Games customised")
            stat(stats.themesUsed, "Themes used")
            stat(stats.altLayoutsUsed, "Alt layouts")
        }
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: valueSize, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: labelSize))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Badges

    private func badgeRow(_ achievement: SkinAchievement) -> some View {
        let definition = achievement.definition
        let earned = achievement.isEarned
        return HStack(spacing: 12) {
            Image(systemName: definition.symbol ?? SkinBadgeCatalog.genericSymbol)
                .font(.system(size: symbolSize))
                .frame(width: symbolSize * 1.6)
                .foregroundStyle(earned ? AnyShapeStyle(SkinKitTheme.current.horizontalGradient) : AnyShapeStyle(Color.white.opacity(0.3)))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: definition.title)
                    .font(.system(size: labelSize + 2, weight: .semibold, design: .rounded))
                    .foregroundColor(earned ? .white : .white.opacity(0.5))
                if let detail = definition.detail {
                    Text(verbatim: detail)
                        .font(.system(size: labelSize))
                        .foregroundColor(.white.opacity(earned ? 0.7 : 0.4))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if let date = achievement.earnedAt {
                Text(date, style: .date)
                    .font(.system(size: labelSize - 1))
                    .foregroundColor(.white.opacity(0.5))
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: labelSize))
                    .foregroundColor(.white.opacity(0.3))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(earned ? "\(definition.title), earned" : "\(definition.title), locked")
    }

    // MARK: Metrics

    #if os(tvOS)
    private let spacing: CGFloat = 24
    private let badgeSpacing: CGFloat = 16
    private let cardPadding: CGFloat = 32
    private let titleSize: CGFloat = 28
    private let valueSize: CGFloat = 40
    private let labelSize: CGFloat = 22
    private let symbolSize: CGFloat = 30
    private let statWidth: CGFloat = 220
    #else
    private let spacing: CGFloat = 14
    private let badgeSpacing: CGFloat = 10
    private let cardPadding: CGFloat = 16
    private let titleSize: CGFloat = 13
    private let valueSize: CGFloat = 22
    private let labelSize: CGFloat = 11
    private let symbolSize: CGFloat = 18
    private let statWidth: CGFloat = 100
    #endif
}

// MARK: - Toasts

public extension View {
    /// Shows a short banner when a badge is earned, if the host turned ``SkinKitAchievements/showsToasts``
    /// on. With the flag off (the default) this does nothing.
    func skinAchievementToasts() -> some View {
        modifier(SkinAchievementToastModifier())
    }
}

private struct SkinAchievementToastModifier: ViewModifier {
    @ObservedObject private var tracker = SkinAchievementTracker.shared
    @State private var shown: [SkinBadgeDefinition] = []

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let badge = shown.first {
                    HStack(spacing: 10) {
                        Image(systemName: badge.symbol ?? SkinBadgeCatalog.genericSymbol)
                        Text(shown.count > 1 ? "\(badge.title) and \(shown.count - 1) more earned" : "\(badge.title) earned")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.85)).overlay(Capsule().strokeBorder(SkinKitTheme.current.gradient, lineWidth: 1)))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isStaticText)
                }
            }
            .onChange(of: tracker.recentlyEarned) { _, earned in
                guard SkinKitAchievements.showsToasts, !earned.isEmpty else { return }
                withAnimation { shown = earned }
                tracker.acknowledgeRecentlyEarned()
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    withAnimation { shown = [] }
                }
            }
    }
}
#endif
