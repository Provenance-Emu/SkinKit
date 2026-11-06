#if canImport(UIKit)
import SkinKitCore
import SkinKitManager
import SkinCatalogKit
//
//  TVOSSkinCatalogBrowserView.swift
//  PVUIBase
//
//  tvOS-specific skin catalog browser.
//  Uses an App Store–style layout with horizontal scrolling rows for
//  "Popular", "New", and "By System" sections.
//  Focus-based navigation is fully compatible with the Siri Remote.
//
//  Issue: #2518
//

#if os(tvOS)
import SwiftUI

// MARK: - TVOSSkinCatalogBrowserView

/// tvOS skin catalog browser with App Store–style horizontal sections.
///
/// All skins come from the remote catalog — no document picker is available on tvOS.
/// Download and install is handled by `SkinCatalogDetailView` via `DeltaSkinManager`.
public struct TVOSSkinCatalogBrowserView: View {

    private let activationContextSystemIdentifier: DeltaSkinSystem?
    private let activationContextGameId: String?

    // MARK: - State

    @State private var catalog: [SkinCatalogEntry] = []
    /// Family facts over the whole catalog; rows group their entries with it.
    @State private var familyIndex = SkinFamilyIndex(entries: [])
    @State private var availableSystems: [String] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedSystem: String?
    @State private var glowIntensity: CGFloat = 0.5
    @State private var spinnerRotation: Double = 0
    @State private var searchTask: Task<Void, Never>?
    /// The creator directory, once fetched, so the profile is the claimed one. Until then (or
    /// offline) it is the minimal profile from the entry's own `author`/`creator`.
    @State private var creatorIndex: SkinCreatorIndex?
    /// The creator whose profile page is open.
    @State private var profileCreator: SkinCreatorCredit?

    // MARK: - Init

    /// Creates the browser, optionally pre-filtering to a system.
    public init(
        preselectedSystem: String? = nil,
        activationContextSystemIdentifier: DeltaSkinSystem? = nil,
        activationContextGameId: String? = nil
    ) {
        _selectedSystem = State(initialValue: preselectedSystem)
        self.activationContextSystemIdentifier = activationContextSystemIdentifier
        self.activationContextGameId = activationContextGameId
    }

    @ViewBuilder
    private func catalogDetailDestination(for family: SkinFamily) -> some View {
        SkinCatalogDetailView(
            entry: family.primary,
            family: family,
            familyIndex: familyIndex,
            activationContextSystemIdentifier: activationContextSystemIdentifier,
            activationContextGameId: activationContextGameId
        )
    }

    /// "View <creator>'s profile" for a long press on a card. A card is one focus target, so the
    /// credit line on it cannot be a button of its own; the detail view's credit row is the other
    /// way in.
    @ViewBuilder
    private func creatorProfileMenu(for family: SkinFamily) -> some View {
        ForEach((creatorIndex ?? SkinCreatorIndex.empty).credits(in: family)) { credit in
            Button {
                profileCreator = credit
            } label: {
                Label("View \(credit.creator.displayName)'s profile", systemImage: "person.crop.circle")
            }
        }
    }

    // MARK: - Derived data

    /// Expanded system filter codes based on shared skin-layout groups.
    ///
    /// For example, selecting `genesis` also includes `segacd` and `32x`.
    private var selectedSystemFilterCodes: Set<String>? {
        guard let selectedSystem else { return nil }
        return DeltaSkinSystemDirectory.current.relatedCatalogSystemCodes(selectedSystem)
    }

    /// Catalog entries after applying the optional selected-system filter.
    private var filteredCatalog: [SkinCatalogEntry] {
        guard let filterCodes = selectedSystemFilterCodes else { return catalog }
        return catalog.filter { entry in
            let entryCodes = Set(entry.systems.map { $0.lowercased() })
            return !entryCodes.isDisjoint(with: filterCodes)
        }
    }

    /// Complete families with at least one member passing the system filter. Shelves are cut by
    /// family, after grouping, so a card never arrives missing members.
    private var filteredFamilies: [SkinFamily] {
        familyIndex.families(containing: filteredCatalog, in: catalog)
    }

    private var popularFamilies: [SkinFamily] {
        Array(filteredFamilies.sorted { $0.totalDownloadCount > $1.totalDownloadCount }.prefix(12))
    }

    private var newFamilies: [SkinFamily] {
        Array(filteredFamilies.sorted { ($0.effectiveDate ?? .distantPast) > ($1.effectiveDate ?? .distantPast) }.prefix(12))
    }

    private var familiesBySystem: [(system: String, families: [SkinFamily])] {
        // Group by the primary member's first non-legacy system code (normalized to lowercase), so
        // a family spanning systems shows once, whole.
        let grouped = Dictionary(grouping: filteredFamilies) { family -> String in
            family.primary.systems
                .map { $0.lowercased() }
                .first { !SkinCatalogService.isLegacySystemCode($0) }
                ?? "other"
        }
        return grouped
            .filter { !SkinCatalogService.isLegacySystemCode($0.key) }
            .map { (system: $0.key, families: $0.value) }
            .sorted { $0.system < $1.system }
    }

    private var searchResults: [SkinCatalogEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return filteredCatalog.filter {
            $0.name.lowercased().contains(q)
            || ($0.author?.lowercased().contains(q) ?? false)
            || $0.systems.contains(where: { $0.lowercased().contains(q) })
            || $0.tags.contains(where: { $0.lowercased().contains(q) })
        }
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            SkinKitTheme.current.background()
                .ignoresSafeArea()

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(message: error)
            } else if !searchText.isEmpty {
                searchResultsView
            } else {
                catalogContentView
            }
        }
        .navigationTitle("Browse Skins")
        .searchable(text: $searchText, prompt: "Search by name, author, or tag")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowIntensity = 0.8
            }
            Task { await loadCatalog() }
        }
        .skinCreatorProfile(
            $profileCreator,
            activationContextSystemIdentifier: activationContextSystemIdentifier,
            activationContextGameId: activationContextGameId
        )
        .task {
            creatorIndex = try? await SkinCreatorDirectory.shared.index()
        }
        .onChange(of: searchText) { _ in
            scheduleSearchUpdate()
        }
    }

    // MARK: - Main catalog content

    private var catalogContentView: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 40) {
                // System filter chips (horizontal)
                if !availableSystems.isEmpty {
                    systemFilterRow
                }

                // Popular section
                if !popularFamilies.isEmpty {
                    sectionRow(title: "POPULAR", families: popularFamilies)
                }

                // New / Recently Updated section
                if !newFamilies.isEmpty {
                    sectionRow(title: "NEW & UPDATED", families: newFamilies)
                }

                // By System sections
                ForEach(familiesBySystem, id: \.system) { item in
                    if selectedSystem == nil || selectedSystemFilterCodes?.contains(item.system) == true {
                        sectionRow(title: DeltaSkinSystemDirectory.current.displayNameForCatalogCode(item.system), families: item.families)
                    }
                }
            }
            .padding(.vertical, 40)
        }
    }

    // MARK: - System filter row

    private var systemFilterRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("FILTER BY SYSTEM")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    systemChip("All", isSelected: selectedSystem == nil) {
                        withAnimation { selectedSystem = nil }
                    }
                    ForEach(availableSystems, id: \.self) { system in
                        systemChip(DeltaSkinSystemDirectory.current.displayNameForCatalogCode(system), isSelected: selectedSystem == system) {
                            withAnimation { selectedSystem = (selectedSystem == system) ? nil : system }
                        }
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 8)
            }
        }
        .padding(.leading, 60)
    }

    private func systemChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .tracking(1)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .background(
                    Capsule()
                        .fill(isSelected ? Color.black.opacity(0.7) : Color.black.opacity(0.3))
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    isSelected ? AnyShapeStyle(SkinKitTheme.current.gradient) : AnyShapeStyle(Color.white.opacity(0.2)),
                                    lineWidth: isSelected ? 2 : 0.5
                                )
                        )
                )
                .shadow(color: isSelected ? SkinKitTheme.current.pink.opacity(0.5) : .clear, radius: 6)
        }
        .skinKitFocusButtonStyle(focusScale: 1.05, cornerRadius: 30)
    }

    // MARK: - Horizontal section row

    private func sectionRow(title: String, families: [SkinFamily]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title)
                .padding(.leading, 60)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(families) { family in
                        NavigationLink(destination: catalogDetailDestination(for: family)) {
                            TVOSSkinCard(family: family, glowIntensity: glowIntensity)
                        }
                        .skinKitFocusButtonStyle(focusScale: 1.08, cornerRadius: 16)
                        .contextMenu { creatorProfileMenu(for: family) }
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 16)
            }
        }
    }

    // MARK: - Search results

    private var searchResultsView: some View {
        Group {
            if searchResults.isEmpty {
                emptySearchView
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 280, maximum: 320), spacing: 30)],
                        spacing: 30
                    ) {
                        ForEach(familyIndex.families(containing: searchResults, in: catalog)) { family in
                            NavigationLink(destination: catalogDetailDestination(for: family)) {
                                TVOSSkinCard(family: family, glowIntensity: glowIntensity)
                            }
                            .skinKitFocusButtonStyle(focusScale: 1.08, cornerRadius: 16)
                            .contextMenu { creatorProfileMenu(for: family) }
                        }
                    }
                    .padding(60)
                }
            }
        }
    }

    private var emptySearchView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 80))
                .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                .shadow(color: SkinKitTheme.current.pink.opacity(0.5), radius: 6)

            Text("NO RESULTS")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                .tracking(2)

            Text("No skins match \"\(searchText)\".")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Loading view

    private var loadingView: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(SkinKitTheme.current.horizontalGradient, lineWidth: 6)
                    .frame(width: 100, height: 100)
                    .blur(radius: 3 * glowIntensity)

                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(SkinKitTheme.current.horizontalGradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(spinnerRotation))
                    .shadow(color: SkinKitTheme.current.pink.opacity(0.7), radius: 6)
                    .onAppear {
                        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                            spinnerRotation = 360
                        }
                    }
            }

            Text("LOADING CATALOG")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                .tracking(3)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Error view

    private func errorView(message: String) -> some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "wifi.slash")
                .font(.system(size: 80))
                .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                .shadow(color: SkinKitTheme.current.pink.opacity(0.7), radius: 6)

            Text("CATALOG UNAVAILABLE")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                .tracking(2)

            Text(message)
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 80)

            Button {
                Task { await loadCatalog() }
            } label: {
                Text("TRY AGAIN")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(SkinKitTheme.current.gradient, lineWidth: 2)
                            )
                    )
                    .shadow(color: SkinKitTheme.current.pink.opacity(0.5), radius: 8)
            }
            .skinKitFocusButtonStyle()

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .foregroundStyle(SkinKitTheme.current.horizontalGradient)
            .tracking(2)
            .shadow(color: SkinKitTheme.current.pink.opacity(glowIntensity * 0.4), radius: 3)
    }

    // MARK: - Data loading

    private func loadCatalog() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            // Hidden sample/mature entries are dropped before grouping; labels come from the full catalog.
            let skinCatalog = try await SkinCatalogService.shared.visibleCatalog()
            let index = try await SkinCatalogService.shared.familyIndex()
            let systems = try await SkinCatalogService.shared.availableSystems()

            await MainActor.run {
                catalog = skinCatalog.skins
                familyIndex = index
                availableSystems = systems
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func scheduleSearchUpdate() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            // Search filtering is computed from catalog state directly.
        }
    }
}

// MARK: - TVOSSkinCard

/// A large card for the tvOS skin catalog — optimised for 10-foot viewing.
private struct TVOSSkinCard: View {
    let family: SkinFamily
    let glowIntensity: CGFloat

    private var entry: SkinCatalogEntry { family.primary }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailView
                .frame(width: 280, height: 180)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottomLeading) {
                    SkinFamilyBadge(family: family, fontSize: 14)
                        .padding(8)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(family.name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(family.creditLine)
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    // System tags (up to 2, excluding legacy codes)
                    let validSystems = entry.systems
                        .map { $0.lowercased() }
                        .filter { !SkinCatalogService.isLegacySystemCode($0) }
                    ForEach(validSystems.prefix(2), id: \.self) { system in
                        Text(DeltaSkinSystemDirectory.current.displayNameForCatalogCode(system))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .tracking(0.5)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.5))
                                    .overlay(Capsule().strokeBorder(SkinKitTheme.current.gradient, lineWidth: 0.5))
                            )
                            .foregroundColor(.white.opacity(0.8))
                    }

                    Spacer()

                    if family.totalDownloadCount > 0 {
                        let count = family.totalDownloadCount
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 14))
                            Text(formatSkinDownloadCount(count))
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(SkinKitTheme.current.gradient, lineWidth: 1)
                )
                .shadow(color: SkinKitTheme.current.purple.opacity(0.3), radius: 8)
        )
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let url = entry.thumbnailURL {
            AsyncImage(url: url) { phase in
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
                .font(.system(size: 50))
                .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                .shadow(color: SkinKitTheme.current.pink.opacity(0.5), radius: 6)
        }
    }
}

#endif
#endif
