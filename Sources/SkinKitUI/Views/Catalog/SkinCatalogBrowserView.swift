#if canImport(UIKit)
import SkinKitCore
import SkinKitManager
import SkinCatalogKit
//
//  SkinCatalogBrowserView.swift
//  PVUIBase
//
//  Created for Provenance (GitHub issue #2545)
//

import SwiftUI

/// View for browsing and downloading skins from the remote skin catalog.
///
/// On tvOS this view redirects to `TVOSSkinCatalogBrowserView`, which provides an
/// App Store–style layout suitable for focus-based navigation.
/// On iOS/iPadOS it displays a searchable, filterable grid of available skins
/// from `SkinCatalogService`. Tapping a skin opens `SkinCatalogDetailView`.
public struct SkinCatalogBrowserView: View {

    #if os(tvOS)
    private let preselectedSystem: String?
    private let activationContextSystemIdentifier: DeltaSkinSystem?
    private let activationContextGameId: String?
    public init(
        preselectedSystem: String? = nil,
        activationContextSystemIdentifier: DeltaSkinSystem? = nil,
        activationContextGameId: String? = nil
    ) {
        self.preselectedSystem = preselectedSystem
        self.activationContextSystemIdentifier = activationContextSystemIdentifier
        self.activationContextGameId = activationContextGameId
    }
    public var body: some View {
        TVOSSkinCatalogBrowserView(
            preselectedSystem: preselectedSystem,
            activationContextSystemIdentifier: activationContextSystemIdentifier,
            activationContextGameId: activationContextGameId
        )
    }
    #else

    private let activationContextSystemIdentifier: DeltaSkinSystem?
    private let activationContextGameId: String?

    // MARK: - State

    @State private var entries: [SkinCatalogEntry] = []
    /// `entries` grouped into variant families (one card each), in `entries` order.
    @State private var families: [SkinFamily] = []
    /// Family facts over the whole catalog, so labels don't change with the filters.
    @State private var familyIndex: SkinFamilyIndex?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedSystem: String?
    @State private var selectedDevice: String?
    @State private var sortOption: SkinSortOption = .popular
    @State private var availableSystems: [String] = []
    @State private var glowIntensity: CGFloat = 0.5
    @State private var showingFilters = false
    @State private var isRefreshing = false
    @State private var spinnerRotation: Double = 0
    @State private var filterTask: Task<Void, Never>?
    /// The creator directory, once fetched, so a credit opens the claimed profile. Until then (or
    /// offline) a credit resolves to the minimal profile from the entry's own `author`/`creator`.
    @State private var creatorIndex: SkinCreatorIndex?
    /// The creator whose profile sheet is open.
    @State private var profileCreator: SkinCreatorCredit?

    /// Observe the skin manager so we can show which catalog skins are already installed.
    @ObservedObject private var skinManager = DeltaSkinManager.shared
    /// The creators the user follows, for the shelf and the Following chip.
    @ObservedObject private var followStore = CreatorFollowStore.shared
    /// The host store's policy, when it sets one (`.environment(\.skinStorePolicy, ...)`): the shelf
    /// lists only what the policy can install.
    @Environment(\.skinStorePolicy) private var storePolicy
    /// "New from creators you follow", independent of the search and filters.
    @State private var followFeed = SkinFollowFeed(items: [])
    /// The Following filter chip: only skins by creators the user follows.
    @State private var followingOnly = false

    // MARK: - Filter Options

    private let deviceOptions: [(label: String, value: String?)] = [
        ("All Devices", nil),
        ("iPhone", "iphone"),
        ("iPad", "ipad"),
        ("Apple TV", "tv")
    ]

    // MARK: - Environment

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: - Init

    /// Create the catalog browser, optionally pre-filtered to a system.
    ///
    /// When `preselectedSystem` is non-nil the filter bar is shown automatically
    /// so the user immediately sees which system is active and can change it.
    /// Pass `activationContextSystemIdentifier` / `activationContextGameId` when presenting from gameplay so “Set as active skin” updates the running session.
    public init(
        preselectedSystem: String? = nil,
        activationContextSystemIdentifier: DeltaSkinSystem? = nil,
        activationContextGameId: String? = nil
    ) {
        self.activationContextSystemIdentifier = activationContextSystemIdentifier
        self.activationContextGameId = activationContextGameId
        _selectedSystem = State(initialValue: preselectedSystem)
        _showingFilters = State(initialValue: preselectedSystem != nil)
        // Pre-select the device filter that matches the current hardware so
        // iPad users see iPad skins and iPhone users see iPhone skins by default.
        let defaultDevice: String? = {
            #if os(tvOS)
            return "tv"
            #else
            return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
            #endif
        }()
        _selectedDevice = State(initialValue: defaultDevice)
    }

    @ViewBuilder
    private func catalogDetailDestination(for entry: SkinCatalogEntry, family: SkinFamily? = nil) -> some View {
        SkinCatalogDetailView(
            entry: entry,
            family: family,
            familyIndex: familyIndex,
            activationContextSystemIdentifier: activationContextSystemIdentifier,
            activationContextGameId: activationContextGameId
        )
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            SkinKitTheme.current.background()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerView
                searchBarView
                filterBarView

                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(message: error)
                } else if entries.isEmpty {
                    emptyView
                } else {
                    catalogGridView
                }
            }
        }
        .skinKitBackdropColorScheme()
        .skinAchievementToasts()
        .navigationTitle("Skin Catalog")
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if !os(tvOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingFilters.toggle()
                } label: {
                    Image(systemName: showingFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                }
                .accessibilityLabel(showingFilters ? "Hide filters" : "Show filters")
                .transaction { $0.animation = nil }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refreshCatalog() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .none, value: isRefreshing)
                }
                .disabled(isRefreshing)
                .accessibilityLabel("Refresh catalog")
                .transaction { $0.animation = nil }
            }
        }
        #endif
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowIntensity = 0.8
            }
            Task { await loadCatalog() }
            // Ensure local skins are scanned so we can show installed badges.
            // The scan is deferred by default, so loadedSkins may be empty.
            if !skinManager.skinsAreLoaded {
                Task {
                    _ = try? await skinManager.availableSkins(forceRescan: false)
                }
            }
        }
        .skinCreatorProfile(
            $profileCreator,
            activationContextSystemIdentifier: activationContextSystemIdentifier,
            activationContextGameId: activationContextGameId
        )
        .task {
            creatorIndex = try? await SkinCreatorDirectory.shared.index()
        }
        .task(id: followShelfKey) {
            await refreshFollowShelf()
        }
        .onChange(of: followingOnly) { _, _ in
            scheduleFilterUpdate()
        }
        .onChange(of: followStore.followedSlugs) { _, _ in
            if followingOnly { scheduleFilterUpdate() }
        }
        .onChange(of: creatorIndex?.creators.count) { _, _ in
            if followingOnly { scheduleFilterUpdate() }
        }
        .onChange(of: searchText) { _, _ in
            scheduleFilterUpdate()
        }
        .onChange(of: selectedSystem) { _, _ in
            scheduleFilterUpdate()
        }
        .onChange(of: selectedDevice) { _, _ in
            scheduleFilterUpdate()
        }
        .onChange(of: sortOption) { _, _ in
            scheduleFilterUpdate()
        }
    }

    // MARK: - UI Components

    private var headerView: some View {
        VStack(spacing: 6) {
            Text("BROWSE SKINS")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                .padding(.top, 16)
                .shadow(color: SkinKitTheme.current.pink.opacity(glowIntensity * 0.5), radius: 3)

            Text("Download skins from the community catalog")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .background(
            Rectangle()
                .fill(Color.black.opacity(0.3))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                        .blur(radius: 0.5)
                        .opacity(glowIntensity),
                    alignment: .bottom
                )
        )
    }

    private var searchBarView: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SkinKitTheme.current.horizontalGradient)

            TextField("Search by name, author, or tag...", text: $searchText)
                .foregroundColor(.white)
                .tint(SkinKitTheme.current.pink)
            #if !os(tvOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            #endif

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(SkinKitTheme.current.gradient, lineWidth: 1)
                )
        )
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var filterBarView: some View {
        if showingFilters {
            VStack(spacing: 8) {
                // System filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip("All Systems", isSelected: selectedSystem == nil) {
                            selectedSystem = nil
                        }
                        ForEach(availableSystems, id: \.self) { system in
                            filterChip(DeltaSkinSystemDirectory.current.displayNameForCatalogCode(system), isSelected: selectedSystem == system) {
                                selectedSystem = (selectedSystem == system) ? nil : system
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Device filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(deviceOptions, id: \.label) { option in
                            filterChip(option.label, isSelected: selectedDevice == option.value) {
                                selectedDevice = option.value
                            }
                        }
                        // Only creators the user follows. Shown once they follow someone (or while it is on).
                        if followingOnly || !followStore.followedSlugs.isEmpty {
                            filterChip("Following", isSelected: followingOnly) {
                                followingOnly.toggle()
                                if followingOnly { markShelfSeen() }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Sort picker
                HStack {
                    Text("SORT:")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(1)

                    ForEach(SkinSortOption.allCases, id: \.self) { option in
                        filterChip(option.displayName, isSelected: sortOption == option) {
                            sortOption = option
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.3))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func filterChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.5)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .background(
                    Capsule()
                        .fill(isSelected ? Color.black.opacity(0.7) : Color.black.opacity(0.3))
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    isSelected ? AnyShapeStyle(SkinKitTheme.current.gradient) : AnyShapeStyle(Color.white.opacity(0.2)),
                                    lineWidth: isSelected ? 1.5 : 0.5
                                )
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var catalogGridView: some View {
        ScrollView {
            if showsFollowShelf {
                followShelfView
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 200 : 160), spacing: 16)],
                spacing: 20
            ) {
                ForEach(families) { family in
                    let entry = family.primary
                    let isInstalled = family.members.contains(where: isSkinInstalled)
                    CatalogSkinCard(
                        entry: entry,
                        family: family,
                        glowIntensity: glowIntensity,
                        isInstalled: isInstalled,
                        creators: (creatorIndex ?? .empty).credits(in: family),
                        onOpenCreator: { profileCreator = $0 },
                        destination: { catalogDetailDestination(for: entry, family: family) }
                    )
                }
            }
            .padding()

            SkinAchievementsCard()
                .padding(.horizontal)
                .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Follow shelf

    /// The shelf sits above the grid while nothing narrows it: no search, system or Following filter.
    private var showsFollowShelf: Bool {
        !followFeed.isEmpty && !followingOnly && selectedSystem == nil
            && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var followShelfView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("NEW FROM CREATORS YOU FOLLOW")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                if followFeed.unseenCount > 0 {
                    Text("\(followFeed.unseenCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(SkinKitTheme.current.pink))
                        .accessibilityLabel("\(followFeed.unseenCount) new")
                }
                Spacer()
                Button("See all") {
                    showingFilters = true
                    followingOnly = true
                    markShelfSeen()
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(followFeed.items.prefix(12)) { item in
                        let family = item.family
                        CatalogSkinCard(
                            entry: family.primary,
                            family: family,
                            glowIntensity: glowIntensity,
                            isInstalled: family.members.contains(where: isSkinInstalled),
                            creators: (creatorIndex ?? .empty).credits(in: family),
                            onOpenCreator: { profileCreator = $0 },
                            destination: {
                                // Opening a card from the shelf counts as having looked at it.
                                catalogDetailDestination(for: family.primary, family: family)
                                    .onAppear { markShelfSeen() }
                            }
                        )
                        .frame(width: 170)
                        .overlay(alignment: .topLeading) {
                            if item.isUnseen {
                                Circle()
                                    .fill(SkinKitTheme.current.pink)
                                    .frame(width: 10, height: 10)
                                    .padding(8)
                                    .accessibilityLabel("New")
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 12)
    }

    /// Everything the shelf depends on, so `.task(id:)` rebuilds it when any of it changes.
    private struct FollowShelfKey: Hashable {
        var followed: Set<String>
        var seenThrough: Date?
        var installedCount: Int
        var skinsAreLoaded: Bool
        var creatorCount: Int
        var isLoading: Bool
        var isRefreshing: Bool
        var policyShelves: [String]
    }

    private var followShelfKey: FollowShelfKey {
        FollowShelfKey(
            followed: followStore.followedSlugs,
            seenThrough: followStore.shelfSeenThrough,
            installedCount: skinManager.loadedSkins.count,
            skinsAreLoaded: skinManager.skinsAreLoaded,
            creatorCount: creatorIndex?.creators.count ?? -1,
            isLoading: isLoading,
            isRefreshing: isRefreshing,
            policyShelves: storePolicy?.sections.map(\.id) ?? []
        )
    }

    @MainActor
    private func refreshFollowShelf() async {
        guard !followStore.followedSlugs.isEmpty else {
            followFeed = SkinFollowFeed(items: [])
            return
        }
        // Until the local skins are scanned the shelf can't tell what is installed.
        guard skinManager.skinsAreLoaded else { return }
        guard let catalog = try? await SkinCatalogService.shared.catalog() else { return }
        followFeed = SkinFollowShelf.feed(
            catalog: catalog,
            creators: creatorIndex,
            store: followStore,
            policy: storePolicy,
            loadedSkins: skinManager.loadedSkins
        )
    }

    /// The user opened the shelf: the badge clears. Not called on appear, or it could never show.
    private func markShelfSeen() {
        if let newest = followFeed.newestDate {
            followStore.markShelfSeen(through: newest)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(SkinKitTheme.current.horizontalGradient, lineWidth: 4)
                    .frame(width: 70, height: 70)
                    .blur(radius: 2 * glowIntensity)

                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(SkinKitTheme.current.horizontalGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(spinnerRotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                            spinnerRotation = 360
                        }
                    }
            }

            Text("LOADING CATALOG")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                .tracking(2)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "wifi.slash")
                .font(.system(size: 50))
                .foregroundStyle(SkinKitTheme.current.horizontalGradient)

            Text("CATALOG UNAVAILABLE")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                .tracking(2)

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Button {
                Task { await loadCatalog() }
            } label: {
                Text("TRY AGAIN")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 24)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(SkinKitTheme.current.gradient, lineWidth: 1)
                            )
                    )
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "gamecontroller")
                .font(.system(size: 50))
                .foregroundStyle(SkinKitTheme.current.horizontalGradient)

            Text("NO SKINS FOUND")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                .tracking(2)

            Text(searchText.isEmpty ? "The catalog has no skins matching your filters." : "No skins match \"\(searchText)\".")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            if !searchText.isEmpty || selectedSystem != nil || selectedDevice != nil || followingOnly {
                Button {
                    searchText = ""
                    selectedSystem = nil
                    selectedDevice = nil
                    followingOnly = false
                    Task { await applyFilters() }
                } label: {
                    Text("CLEAR FILTERS")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 24)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(SkinKitTheme.current.gradient, lineWidth: 1)
                                )
                        )
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Installed Check

    /// Delegates to the shared `isCatalogSkinInstalled` helper so the
    /// matching logic is defined in one place.
    private func isSkinInstalled(_ entry: SkinCatalogEntry) -> Bool {
        isCatalogSkinInstalled(entry, in: skinManager.loadedSkins)
    }

    // MARK: - Data Loading

    private func loadCatalog() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let systems = try await SkinCatalogService.shared.availableSystems()
            await MainActor.run {
                availableSystems = systems
            }

            await applyFilters()

            await MainActor.run {
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func refreshCatalog() async {
        await MainActor.run { isRefreshing = true }
        do {
            _ = try await SkinCatalogService.shared.catalog(forceRefresh: true)
            // The directory is refreshed with the catalog.
            let refreshedCreators = try? await SkinCreatorDirectory.shared.index(forceRefresh: true)
            await MainActor.run { creatorIndex = refreshedCreators ?? creatorIndex }
            let systems = try await SkinCatalogService.shared.availableSystems()
            await MainActor.run {
                availableSystems = systems
            }
            await applyFilters()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
        await MainActor.run { isRefreshing = false }
    }

    private func scheduleFilterUpdate() {
        filterTask?.cancel()
        filterTask = Task {
            // Debounce rapid changes (e.g., typing) to avoid flooding the service.
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            guard !Task.isCancelled else { return }
            await applyFilters()
        }
    }

    private func sortLocally(_ entries: [SkinCatalogEntry], by option: SkinSortOption) -> [SkinCatalogEntry] {
        switch option {
        case .popular:      return entries.sorted { ($0.downloadCount ?? 0) > ($1.downloadCount ?? 0) }
        case .recent:       return entries.sorted { ($0.effectiveDate ?? .distantPast) > ($1.effectiveDate ?? .distantPast) }
        case .alphabetical: return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .rating:       return entries.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        }
    }

    private func applyFilters() async {
        do {
            var results: [SkinCatalogEntry]

            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let deviceFilter = selectedDevice.map { [$0] }
                results = try await SkinCatalogService.shared.filterSkins(
                    system: selectedSystem,
                    deviceSupport: deviceFilter,
                    sortBy: sortOption
                )
            } else {
                results = try await SkinCatalogService.shared.searchSkins(
                    query: searchText,
                    system: selectedSystem
                )
                /// Apply device filter and sort locally on search results.
                /// Treat an omitted or empty `deviceSupport` list as unrestricted support.
                /// Use prefix matching so "iphone" matches catalog variants like "iphone-x".
                if let device = selectedDevice {
                    let lowerFilter = device.lowercased()
                    results = results.filter { entry in
                        let entryDevices = entry.deviceSupport
                        guard !entryDevices.isEmpty else { return true }
                        return entryDevices.contains { d in
                            let dl = d.lowercased()
                            return dl == lowerFilter || dl.hasPrefix(lowerFilter + "-") || lowerFilter.hasPrefix(dl + "-")
                        }
                    }
                }
                results = sortLocally(results, by: sortOption)
            }

            // The Following chip keeps the creators the user follows, resolved the way the profile
            // sheet and the shelf resolve them.
            if followingOnly {
                let following = await MainActor.run { followStore.followedSlugs }
                let directory = await MainActor.run { creatorIndex ?? .empty }
                results = results.filter { directory.slug(for: $0).map(following.contains) ?? false }
            }

            guard !Task.isCancelled else { return }

            // A card shows its complete family (every visible member, not only the ones that matched
            // the search or filter), so "Install all" never installs a subset. Hidden sample/mature
            // entries never reach a family; labels come from the whole catalog.
            let index = try await SkinCatalogService.shared.familyIndex()
            let visible = try await SkinCatalogService.shared.visibleCatalog().skins
            let grouped = index.families(containing: results, in: visible)

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    entries = results
                    families = grouped
                    familyIndex = index
                }
            }
        } catch {
            ELOG("SkinCatalogBrowserView: Filter error: \(error)")
            guard !Task.isCancelled else { return }
            await MainActor.run {
                errorMessage = error.localizedDescription
                withAnimation(.easeOut(duration: 0.2)) {
                    entries = []
                    families = []
                }
            }
        }
    }
    #endif // os(tvOS)
}

// MARK: - CatalogSkinCard (iOS/iPadOS only)

#if !os(tvOS)

/// A grid card for one variant family (a standalone entry is a family of one).
///
/// The card is not one big link: the credit line is a button of its own (it opens the creator's
/// profile), and a button inside a `NavigationLink`'s label is unreliable, so the thumbnail, the
/// title and the footer are each a link to the detail view and the credit sits between them.
private struct CatalogSkinCard<Destination: View>: View {
    let entry: SkinCatalogEntry
    var family: SkinFamily?
    let glowIntensity: CGFloat
    var isInstalled: Bool = false
    /// The creators behind the family's members, in member order. Empty for an uncredited family.
    var creators: [SkinCreatorCredit] = []
    let onOpenCreator: (SkinCreatorCredit) -> Void
    @ViewBuilder let destination: () -> Destination

    private var title: String { family?.name ?? entry.name }
    private var credit: String { family?.creditLine ?? "by \(entry.author ?? "Unknown")" }
    private var downloads: Int { family?.totalDownloadCount ?? entry.downloadCount ?? 0 }

    private func displayName(forSystemCode code: String) -> String {
        DeltaSkinSystemDirectory.current.displayNameForCatalogCode(code)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail with installed badge overlay
            NavigationLink(destination: destination()) {
                thumbnailView
                    .aspectRatio(1.4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .bottomLeading) {
                        if let family {
                            SkinFamilyBadge(family: family)
                                .padding(6)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isInstalled {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                                .background(Color.black.opacity(0.7).clipShape(Circle()))
                                .padding(6)
                        }
                    }
            }
            .buttonStyle(PlainButtonStyle())

            // Info
            VStack(alignment: .leading, spacing: 4) {
                NavigationLink(destination: destination()) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())

                creditView

                NavigationLink(destination: destination()) {
                    HStack(spacing: 6) {
                        // System tags (max 2, excluding legacy codes like "unofficial")
                        let validSystems = entry.systems.filter { !SkinCatalogService.isLegacySystemCode($0) }
                        ForEach(validSystems.prefix(2), id: \.self) { system in
                            Text(displayName(forSystemCode: system))
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(0.5)
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.5))
                                        .overlay(Capsule().strokeBorder(SkinKitTheme.current.gradient, lineWidth: 0.5))
                                )
                                .foregroundColor(.white.opacity(0.8))
                        }

                        Spacer()

                        // Download count (a family's members summed; each keeps its own in the detail view)
                        if downloads > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "eye")
                                    .font(.system(size: 9))
                                Text(formatSkinDownloadCount(downloads))
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .skinKitCard()
    }

    /// The credit line. One creator: a button that opens the profile. Several (a family mixing
    /// authors): a menu to pick which. None (no author, no `creator`): plain text.
    @ViewBuilder
    private var creditView: some View {
        let label = Text(credit)
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.6))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        switch creators.count {
        case 0:
            label
        case 1:
            Button {
                onOpenCreator(creators[0])
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityLabel(credit)
            .accessibilityHint("Opens \(creators[0].creator.displayName)'s profile")
        default:
            Menu {
                ForEach(creators) { creator in
                    Button(creator.creator.displayName) { onOpenCreator(creator) }
                }
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityLabel(credit)
            .accessibilityHint("Choose a creator's profile to open")
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnailURL = entry.thumbnailURL {
            AsyncImage(url: thumbnailURL) { phase in
                switch phase {
                case .empty:
                    placeholderThumbnail
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholderThumbnail
                @unknown default:
                    placeholderThumbnail
                }
            }
        } else {
            placeholderThumbnail
        }
    }

    private var placeholderThumbnail: some View {
        ZStack {
            Color.black.opacity(0.3)
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 32))
                .foregroundStyle(SkinKitTheme.current.horizontalGradient)
        }
    }

}
#endif // !os(tvOS)

// MARK: - Shared Helpers

// `matchingInstalledSkin(for:in:)` and `isCatalogSkinInstalled(_:in:)` live in SkinKitManager.

/// Formats a download/play count into a compact string (e.g. 1200 → "1.2k").
func formatSkinDownloadCount(_ count: Int) -> String {
    if count >= 1_000 {
        return String(format: "%.1fk", Double(count) / 1_000.0)
    }
    return "\(count)"
}

// MARK: - SkinSortOption Display (iOS only — used by filterBarView)

#if !os(tvOS)
private extension SkinSortOption {
    var displayName: String {
        switch self {
        case .popular:     return "Most viewed"
        case .recent:      return "Recent"
        case .alphabetical: return "A–Z"
        case .rating:      return "Rating"
        }
    }
}
#endif // !os(tvOS)
#endif
