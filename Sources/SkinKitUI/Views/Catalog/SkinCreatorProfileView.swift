#if canImport(UIKit)
import SkinCatalogKit
import SkinKitCore
import SkinKitManager
import SwiftUI

// MARK: - Model

/// Loads what the profile sheet shows: the creator's record from the directory and their skins as
/// variant families, cut by the host's store policy. The sheet draws the creator it was opened with
/// at once (a minimal record is always enough: name and skins), then upgrades it when the directory
/// answers, so a slow or missing `creators.json` never leaves the sheet empty.
@MainActor
final class SkinCreatorProfileModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded
        /// The catalog could not be read. The creator header still shows.
        case failed(String)
    }

    @Published private(set) var creator: SkinCreator
    @Published private(set) var families: [SkinFamily] = []
    /// Family facts over the whole catalog, so install labels match the store's.
    @Published private(set) var familyIndex: SkinFamilyIndex?
    @Published private(set) var phase: Phase = .loading

    private let directory: SkinCreatorDirectory
    private let service: SkinCatalogService
    private let isPreloaded: Bool
    /// The credit the sheet was opened from, so the creator can be resolved again once the
    /// directory loads (an alias author's local slug is not the claimed creator's slug).
    private let credit: SkinCreatorCredit?

    init(
        credit: SkinCreatorCredit,
        directory: SkinCreatorDirectory = .shared,
        service: SkinCatalogService = .shared
    ) {
        self.credit = credit
        self.creator = credit.creator
        self.directory = directory
        self.service = service
        isPreloaded = false
    }

    /// Fixture data for previews: nothing is fetched.
    init(creator: SkinCreator, families: [SkinFamily], familyIndex: SkinFamilyIndex?) {
        self.credit = nil
        self.creator = creator
        self.families = families
        self.familyIndex = familyIndex
        directory = .shared
        service = .shared
        isPreloaded = true
        phase = .loaded
    }

    var summary: SkinCreatorProfileSummary {
        SkinCreatorProfileSummary(families: families)
    }

    func load(policy: SkinStorePolicy?) async {
        guard !isPreloaded else { return }
        phase = .loading

        var index = SkinCreatorIndex.empty
        if let fetched = try? await directory.index() {
            index = fetched
        } else if let cached = await directory.cachedIndex() {
            index = cached
        }
        if let credit {
            creator = index.resolve(credit)
        } else if let known = index.creator(for: creator.slug) {
            creator = known
        }

        do {
            let catalog = try await service.catalog()
            families = index.families(by: creator, in: catalog, policy: policy)
            familyIndex = catalog.familyIndex
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

// MARK: - View

/// A creator's profile (creator profiles spec §7): banner, avatar, name with a check mark when the
/// profile is claimed, bio, links, and the creator's skins as installable variant families.
///
/// Opened from a credit line in the store (see ``View/skinCreatorProfile(_:activationContextSystemIdentifier:activationContextGameId:)``):
/// a sheet on iOS, a full-screen page on tvOS. An author nobody has claimed gets the minimal
/// profile (name, an initial for an avatar, skins), so the sheet never dead-ends.
///
/// - iOS opens links and socials in an in-app Safari sheet. tvOS has no browser, so it shows the
///   handle or URL as text.
/// - The skins are limited by the `skinStorePolicy` environment value, when the host sets one.
/// - Installing goes through ``SkinFamilyInstallModel`` and `DeltaSkinManager.installCatalogPlan`,
///   the same path as the catalog detail view.
public struct SkinCreatorProfileView: View {
    @StateObject private var model: SkinCreatorProfileModel
    private let activationContextSystemIdentifier: DeltaSkinSystem?
    private let activationContextGameId: String?

    @Environment(\.skinStorePolicy) private var policy
    @Environment(\.dismiss) private var dismiss
    @State private var safariLink: SkinCreatorSafariLink?
    @ObservedObject private var followStore = CreatorFollowStore.shared

    /// Opens the profile for `credit`, loading the directory record and the skins.
    ///
    /// Pass the credit the store resolved for the line that was tapped
    /// (`SkinCreatorIndex.credits(in:)`); a minimal record is fine.
    public init(
        credit: SkinCreatorCredit,
        activationContextSystemIdentifier: DeltaSkinSystem? = nil,
        activationContextGameId: String? = nil
    ) {
        _model = StateObject(wrappedValue: SkinCreatorProfileModel(credit: credit))
        self.activationContextSystemIdentifier = activationContextSystemIdentifier
        self.activationContextGameId = activationContextGameId
    }

    /// A profile with its skins already chosen. Previews use this; the apps use ``init(credit:activationContextSystemIdentifier:activationContextGameId:)``.
    init(creator: SkinCreator, families: [SkinFamily], familyIndex: SkinFamilyIndex? = nil) {
        _model = StateObject(wrappedValue: SkinCreatorProfileModel(
            creator: creator, families: families, familyIndex: familyIndex
        ))
        activationContextSystemIdentifier = nil
        activationContextGameId = nil
    }

    #if os(tvOS)
    private let horizontalInset: CGFloat = 80
    private let avatarSize: CGFloat = 140
    #else
    private let horizontalInset: CGFloat = 20
    private let avatarSize: CGFloat = 76
    #endif

    public var body: some View {
        NavigationStack {
            ZStack {
                SkinKitTheme.current.background()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        followSlot
                        bioSection
                        linksSection
                        badgesSlot
                        skinsSection
                    }
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
            .skinKitBackdropColorScheme()
            .navigationTitle(model.creator.displayName)
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
        }
        #if os(iOS)
        .sheet(item: $safariLink) { link in
            SafariWebView(url: link.url)
                .ignoresSafeArea()
        }
        #endif
        .task { await model.load(policy: policy) }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            banner
            HStack(alignment: .center, spacing: 14) {
                SkinCreatorAvatar(creator: model.creator, size: avatarSize)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(verbatim: model.creator.displayName)
                            .font(.system(size: avatarSize * 0.34, weight: .bold, design: .rounded))
                            .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                            .lineLimit(2)
                        if model.creator.isClaimed {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(SkinKitTheme.current.cyan)
                                .accessibilityLabel("Claimed profile")
                        }
                    }
                    summaryLine
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, horizontalInset)
        }
    }

    @ViewBuilder
    private var banner: some View {
        if let url = model.creator.bannerURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                default:
                    bannerPlaceholder
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(3, contentMode: .fit)
            .clipped()
            .accessibilityHidden(true)
        } else {
            bannerPlaceholder
                .frame(maxWidth: .infinity)
                .frame(height: avatarSize * 0.6)
        }
    }

    private var bannerPlaceholder: some View {
        SkinKitTheme.current.gradient.opacity(0.35)
    }

    @ViewBuilder
    private var summaryLine: some View {
        let summary = model.summary
        if !summary.isEmpty {
            let systems = summary.systemCodes.count
            Text(verbatim: [
                summary.skinCount == 1 ? "1 skin" : "\(summary.skinCount) skins",
                systems == 1 ? "1 system" : "\(systems) systems",
                summary.downloadCount > 0 ? "\(formatSkinDownloadCount(summary.downloadCount)) views" : nil,
            ].compactMap(\.self).joined(separator: " · "))
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Slots for sibling features

    /// The Follow toggle (follow creators spec §3), with the empty-state line until the user follows.
    private var followSlot: some View {
        HStack(spacing: 12) {
            SkinCreatorFollowButton(slug: model.creator.slug, displayName: model.creator.displayName)
            if !followStore.isFollowing(model.creator.slug) {
                Text("Follow to see new skins here")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, horizontalInset)
    }

    /// Where the creator's badges row goes (gamification design, SkinKit#69 and #70). `creator.badges`
    /// and `creator.stats` are already decoded. Empty until that lands.
    @ViewBuilder
    private var badgesSlot: some View {
        EmptyView()
    }

    // MARK: - Bio, socials and links

    @ViewBuilder
    private var bioSection: some View {
        if let bio = model.creator.bio {
            // Plain text, never Markdown or HTML (spec §1).
            Text(verbatim: bio)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, horizontalInset)
        }
    }

    @ViewBuilder
    private var linksSection: some View {
        let creator = model.creator
        if !creator.socials.isEmpty || !creator.links.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("LINKS")
                #if os(tvOS)
                // No browser on tvOS: show where to find them.
                ForEach(creator.socials) { social in
                    Label {
                        Text(verbatim: "\(social.title): \(social.handle)")
                    } icon: {
                        Image(systemName: social.symbolName)
                    }
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.8))
                }
                ForEach(creator.links, id: \.url) { link in
                    Label {
                        Text(verbatim: "\(link.label): \(link.url.absoluteString)")
                    } icon: {
                        Image(systemName: "link")
                    }
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.8))
                }
                #else
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 8) {
                    ForEach(creator.socials) { social in
                        linkChip(title: social.handle, symbol: social.symbolName, url: social.url,
                                 accessibilityLabel: "\(social.title): \(social.handle)")
                    }
                    ForEach(creator.links, id: \.url) { link in
                        linkChip(title: link.label, symbol: "link", url: link.url,
                                 accessibilityLabel: link.label)
                    }
                }
                .padding(.horizontal, horizontalInset)
                #endif
            }
        }
    }

    #if !os(tvOS)
    /// A pill that opens `url` in Safari, or just shows the text when the platform has no URL
    /// (Discord handles have none).
    @ViewBuilder
    private func linkChip(title: String, symbol: String, url: URL?, accessibilityLabel: String) -> some View {
        let label = HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12))
            Text(verbatim: title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(.white.opacity(url == nil ? 0.6 : 0.9))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.4))
                .overlay(Capsule().strokeBorder(SkinKitTheme.current.gradient, lineWidth: url == nil ? 0.5 : 1))
        )
        if let url {
            Button {
                safariLink = SkinCreatorSafariLink(url: url)
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Opens in Safari")
        } else {
            label.accessibilityLabel(accessibilityLabel)
        }
    }
    #endif

    // MARK: - Skins

    private var skinsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("SKINS")
            switch model.phase {
            case .loading:
                HStack {
                    Spacer()
                    ProgressView().tint(SkinKitTheme.current.pink)
                    Spacer()
                }
                .padding(.vertical, 24)
            case let .failed(message):
                VStack(spacing: 10) {
                    Text("Couldn't load this creator's skins.")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                    Text(verbatim: message)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task { await model.load(policy: policy) }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, horizontalInset)
            case .loaded where model.families.isEmpty:
                Text("No skins from this creator are available in this store.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, horizontalInset)
                    .padding(.vertical, 16)
            case .loaded:
                LazyVStack(spacing: 14) {
                    ForEach(model.families) { family in
                        SkinCreatorFamilyCard(
                            family: family,
                            familyIndex: model.familyIndex,
                            activationContextSystemIdentifier: activationContextSystemIdentifier,
                            activationContextGameId: activationContextGameId
                        )
                        .id(family.members.map(\.id))
                    }
                }
                .padding(.horizontal, horizontalInset)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(2)
            .foregroundColor(.white.opacity(0.4))
            .padding(.horizontal, horizontalInset)
    }
}

// MARK: - Pieces

/// An Identifiable URL for `.sheet(item:)`.
private struct SkinCreatorSafariLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// The creator's mirrored avatar, or an initial on the theme gradient while it loads, when there is
/// none, or when it fails.
private struct SkinCreatorAvatar: View {
    let creator: SkinCreator
    let size: CGFloat

    var body: some View {
        Group {
            if let url = creator.avatarURL {
                AsyncImage(url: url) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        initial
                    }
                }
            } else {
                initial
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(SkinKitTheme.current.gradient, lineWidth: 2))
        .accessibilityHidden(true)
    }

    private var initial: some View {
        ZStack {
            SkinKitTheme.current.gradient.opacity(0.6)
            Text(verbatim: String(creator.displayName.first(where: { !$0.isWhitespace }) ?? "?").uppercased())
                .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

/// One family in the profile: its header opens the catalog detail view, and the install controls
/// are the ones the detail view uses (``SkinFamilyVariantsSection`` for a family with several
/// files or packed variants, one install button for a single file).
private struct SkinCreatorFamilyCard: View {
    let family: SkinFamily
    let familyIndex: SkinFamilyIndex?
    let activationContextSystemIdentifier: DeltaSkinSystem?
    let activationContextGameId: String?

    @StateObject private var model: SkinFamilyInstallModel
    @ObservedObject private var skinManager = DeltaSkinManager.shared

    init(
        family: SkinFamily,
        familyIndex: SkinFamilyIndex?,
        activationContextSystemIdentifier: DeltaSkinSystem?,
        activationContextGameId: String?
    ) {
        self.family = family
        self.familyIndex = familyIndex
        self.activationContextSystemIdentifier = activationContextSystemIdentifier
        self.activationContextGameId = activationContextGameId
        _model = StateObject(wrappedValue: SkinFamilyInstallModel(family: family, familyIndex: familyIndex))
    }

    private var hasVariantsSection: Bool {
        family.isMultiFile || family.primary.hasPackedVariants
    }

    private func detail(for member: SkinCatalogEntry) -> some View {
        SkinCatalogDetailView(
            entry: member,
            family: family,
            familyIndex: familyIndex,
            activationContextSystemIdentifier: activationContextSystemIdentifier,
            activationContextGameId: activationContextGameId
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                NavigationLink(destination: detail(for: family.primary)) {
                    headerLabel
                }
                .skinKitFocusButtonStyle(focusScale: 1.03, cornerRadius: 12)

                // A multi-file family installs from its variants section; every other family (a
                // single file, packed variants or not) has this one button.
                if !family.isMultiFile {
                    SkinFamilyMemberAction(family: family, member: family.primary, model: model)
                }
            }

            if hasVariantsSection {
                SkinFamilyVariantsSection(
                    family: family,
                    current: family.primary,
                    model: model,
                    destination: { AnyView(detail(for: $0)) }
                )
                .padding(.horizontal, -20)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.4))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(SkinKitTheme.current.gradient, lineWidth: 1))
        )
        .task(id: skinManager.loadedSkins.count) {
            // The variants section does this itself for a multi-file family.
            if !family.isMultiFile {
                model.refreshInstalled(from: skinManager.loadedSkins)
            }
        }
    }

    private var headerLabel: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 84, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottomLeading) {
                    SkinFamilyBadge(family: family, fontSize: 8)
                        .padding(3)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: family.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(verbatim: systemsLine)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                if family.totalDownloadCount > 0 {
                    Label(formatSkinDownloadCount(family.totalDownloadCount), systemImage: "eye")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var systemsLine: String {
        let codes = family.members.flatMap(\.normalizedSystems)
            .filter { !SkinCatalogService.isLegacySystemCode($0) }
        var seen = Set<String>()
        return codes.filter { seen.insert($0).inserted }
            .map { DeltaSkinSystemDirectory.current.displayNameForCatalogCode($0) }
            .joined(separator: ", ")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = family.primary.thumbnailURL {
            AsyncImage(url: url) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.black.opacity(0.3)
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 20))
                .foregroundStyle(SkinKitTheme.current.horizontalGradient)
        }
    }
}

// MARK: - Presentation

public extension View {
    /// Presents the creator profile for `credit` when it is non-nil: a sheet on iOS, a full-screen
    /// page on tvOS. The browsers and the detail view use this for their credit lines; an app that
    /// shows a credit of its own can too.
    func skinCreatorProfile(
        _ credit: Binding<SkinCreatorCredit?>,
        activationContextSystemIdentifier: DeltaSkinSystem? = nil,
        activationContextGameId: String? = nil
    ) -> some View {
        modifier(SkinCreatorProfilePresentation(
            credit: credit,
            activationContextSystemIdentifier: activationContextSystemIdentifier,
            activationContextGameId: activationContextGameId
        ))
    }
}

private struct SkinCreatorProfilePresentation: ViewModifier {
    @Binding var credit: SkinCreatorCredit?
    let activationContextSystemIdentifier: DeltaSkinSystem?
    let activationContextGameId: String?

    func body(content: Content) -> some View {
        #if os(tvOS)
        content.fullScreenCover(item: $credit) { credit in
            SkinCreatorProfileView(
                credit: credit,
                activationContextSystemIdentifier: activationContextSystemIdentifier,
                activationContextGameId: activationContextGameId
            )
        }
        #else
        content.sheet(item: $credit) { credit in
            SkinCreatorProfileView(
                credit: credit,
                activationContextSystemIdentifier: activationContextSystemIdentifier,
                activationContextGameId: activationContextGameId
            )
        }
        #endif
    }
}
#endif
