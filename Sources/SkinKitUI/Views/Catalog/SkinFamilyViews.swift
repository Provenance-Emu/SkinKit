#if canImport(UIKit)
import SkinCatalogKit
import SkinKitCore
import SkinKitManager
import SwiftUI

// MARK: - Install model

/// Per-member install state for a variant family in the catalog detail view: install one member,
/// or "Install all" through the family's download plan, one file at a time.
@MainActor
final class SkinFamilyInstallModel: ObservableObject {
    enum MemberState: Equatable {
        case idle
        case downloading(Double)
        case installing
        case installed
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .downloading, .installing: true
            default: false
            }
        }
    }

    @Published private(set) var states: [String: MemberState] = [:]
    @Published private(set) var isInstallingPlan = false

    let family: SkinFamily
    let familyIndex: SkinFamilyIndex?
    /// Shared with the detail view's own "Download & Install": an entry in flight on either path
    /// is skipped by the other.
    let tracker: SkinCatalogInstallTracker
    private var task: Task<Void, Never>?

    init(family: SkinFamily, familyIndex: SkinFamilyIndex?, tracker: SkinCatalogInstallTracker? = nil) {
        self.family = family
        self.familyIndex = familyIndex
        self.tracker = tracker ?? .shared
    }

    func state(for member: SkinCatalogEntry) -> MemberState {
        states[member.id] ?? .idle
    }

    /// Mark members that are already installed (matched the same way as the browser badge).
    func refreshInstalled(from skins: [any DeltaSkinProtocol]) {
        for member in family.members where !(states[member.id]?.isBusy ?? false) {
            if isCatalogSkinInstalled(member, in: skins) {
                states[member.id] = .installed
            } else if states[member.id] == .installed {
                states[member.id] = nil
            }
        }
    }

    var notInstalled: [SkinCatalogEntry] {
        family.members.filter { state(for: $0) != .installed }
    }

    func install(_ member: SkinCatalogEntry) {
        run(family.downloadPlan(for: member))
    }

    /// What "Install all" fetches: the split members not installed yet, never a catalog-built merge of them.
    var installAllMembers: [SkinCatalogEntry] {
        family.installAllMembers(installedIds: Set(family.members.filter { state(for: $0) == .installed }.map(\.id)))
    }

    func installAll() {
        run(family.downloadPlan(memberIds: Set(installAllMembers.map(\.id))))
    }

    func cancel() {
        task?.cancel()
    }

    /// Whether `member` is installing on any path: this model's plan or the detail view's button.
    func isInFlight(_ member: SkinCatalogEntry) -> Bool {
        state(for: member).isBusy || tracker.isInFlight(member.id)
    }

    private func run(_ fullPlan: SkinDownloadPlan) {
        // Members already installing elsewhere stay with that install.
        let plan = SkinDownloadPlan(entries: fullPlan.entries.filter { !tracker.isInFlight($0.id) })
        guard !plan.isEmpty, task == nil else { return }
        isInstallingPlan = true
        for entry in plan.entries {
            states[entry.id] = .downloading(0)
        }
        let index = familyIndex
        task = Task { [weak self] in
            for entry in plan.entries {
                guard let self, !Task.isCancelled else { break }
                let single = SkinDownloadPlan(entries: [entry])
                // Strong for the length of this download only; the loop above already holds it.
                let model = self
                let failures = await DeltaSkinManager.shared.installCatalogPlan(
                    single,
                    familyIndex: index,
                    tracker: model.tracker,
                    progress: { id, fraction in
                        Task { @MainActor in
                            guard case .downloading = model.states[id] else { return }
                            model.states[id] = fraction >= 1 ? .installing : .downloading(fraction)
                        }
                    }
                )
                if let error = failures[entry.id] {
                    // Cancelled, or claimed by another install meanwhile (that one reports it).
                    let quiet = error is CancellationError || error is SkinCatalogInstallError
                    self.states[entry.id] = quiet ? .idle : .failed(error.localizedDescription)
                } else {
                    self.states[entry.id] = .installed
                }
            }
            guard let self else { return }
            for entry in plan.entries where self.states[entry.id]?.isBusy == true {
                self.states[entry.id] = .idle
            }
            self.isInstallingPlan = false
            self.task = nil
        }
    }
}

// MARK: - Variants section

/// The variants of a family in the catalog detail view: each member by label with its own credit,
/// download count and install button, plus "Install all". A single-file skin's packed variants are
/// listed as included in the one download.
struct SkinFamilyVariantsSection: View {
    let family: SkinFamily
    /// The entry the detail view is showing; its row is marked.
    let current: SkinCatalogEntry
    @ObservedObject var model: SkinFamilyInstallModel
    @ObservedObject private var skinManager = DeltaSkinManager.shared
    let destination: (SkinCatalogEntry) -> AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(family.isMultiFile ? "VARIANTS (\(family.members.count))" : "INCLUDES \(current.variants.count) VARIANTS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                if family.isMultiFile {
                    installAllButton
                }
            }

            if family.isMultiFile {
                ForEach(family.members) { member in
                    memberRow(member)
                }
            }
            if !current.variants.isEmpty {
                packedVariants(current)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .task(id: skinManager.loadedSkins.count) {
            model.refreshInstalled(from: skinManager.loadedSkins)
        }
    }

    private var installAllButton: some View {
        let remaining = model.installAllMembers.count
        return Button {
            model.installAll()
        } label: {
            Label(remaining == 0 ? "ALL INSTALLED" : "INSTALL ALL (\(remaining))",
                  systemImage: remaining == 0 ? "checkmark.circle.fill" : "square.and.arrow.down.on.square")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().strokeBorder(SkinKitTheme.current.gradient, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(remaining == 0 || model.isInstallingPlan)
        .accessibilityLabel(remaining == 0 ? "All variants installed" : "Install all \(remaining) variants")
    }

    private func memberRow(_ member: SkinCatalogEntry) -> some View {
        HStack(spacing: 12) {
            NavigationLink(destination: destination(member)) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(family.label(for: member))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if member.id == current.id {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                                .accessibilityLabel("Showing")
                        }
                        if member.hasPackedVariants {
                            Text("+\(member.variants.count)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    // Each variant keeps its own credit and count inside the family.
                    HStack(spacing: 8) {
                        Text("by \(member.author ?? "Unknown")")
                        if let count = member.downloadCount, count > 0 {
                            Label(formatSkinDownloadCount(count), systemImage: "eye")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            SkinFamilyMemberAction(family: family, member: member, model: model)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(member.id == current.id ? 0.55 : 0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(member.id == current.id ? 0.3 : 0.1), lineWidth: 1)
                )
        )
    }

    private func packedVariants(_ entry: SkinCatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if family.isMultiFile {
                Text("\(family.label(for: entry)) also includes:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            ForEach(entry.variants) { variant in
                HStack(spacing: 8) {
                    Image(systemName: Self.icon(for: variant.kind))
                        .frame(width: 18)
                        .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                    Text(variant.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            Text("One download brings all of these.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.45))
        }
    }

    static func icon(for kind: SkinCatalogVariant.Kind) -> String {
        switch kind {
        case .alt: "rectangle.2.swap"
        case .theme: "paintpalette"
        case .game: "gamecontroller"
        case .other: "square.stack"
        }
    }
}

// MARK: - Member install action

/// The trailing control of a family member's row: install, progress, installed check or retry.
/// Shared by the variants section and the creator profile sheet's single-file cards, so both
/// install through the same ``SkinFamilyInstallModel``.
struct SkinFamilyMemberAction: View {
    let family: SkinFamily
    let member: SkinCatalogEntry
    @ObservedObject var model: SkinFamilyInstallModel
    @ObservedObject private var installTracker = SkinCatalogInstallTracker.shared

    var body: some View {
        switch model.state(for: member) {
        case .idle where installTracker.isInFlight(member.id):
            // Installing from the detail view's own button.
            ProgressView()
                .tint(SkinKitTheme.current.pink)
                .accessibilityLabel("Installing \(family.label(for: member))")
        case .idle:
            Button {
                model.install(member)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(SkinKitTheme.current.horizontalGradient)
            }
            .buttonStyle(.plain)
            .disabled(model.isInstallingPlan)
            .accessibilityLabel("Install \(family.label(for: member))")
        case let .downloading(progress):
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .tint(SkinKitTheme.current.pink)
                .accessibilityLabel("Downloading \(family.label(for: member))")
        case .installing:
            ProgressView()
                .tint(SkinKitTheme.current.pink)
                .accessibilityLabel("Installing \(family.label(for: member))")
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(.green)
                .accessibilityLabel("\(family.label(for: member)) installed")
        case .failed:
            Button {
                model.install(member)
            } label: {
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .font(.system(size: 22))
                    .foregroundColor(.orange)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry \(family.label(for: member))")
        }
    }
}

// MARK: - Card badge

/// "N variants" capsule for a family card.
struct SkinFamilyBadge: View {
    let family: SkinFamily
    var fontSize: CGFloat = 9

    var body: some View {
        if family.hasVariants {
            HStack(spacing: 3) {
                Image(systemName: "square.stack.3d.up.fill")
                Text("\(family.variantCount) VARIANTS")
            }
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .tracking(0.5)
            .padding(.horizontal, fontSize * 0.6)
            .padding(.vertical, fontSize * 0.25)
            .foregroundColor(.white)
            .background(Capsule().fill(Color.black.opacity(0.75)))
            .overlay(Capsule().strokeBorder(SkinKitTheme.current.gradient, lineWidth: 0.75))
            .accessibilityLabel("\(family.variantCount) variants")
        }
    }
}

extension SkinFamily {
    /// The credit line for a family card: every distinct author, so grouping never hides one.
    var creditLine: String {
        let names = authors
        switch names.count {
        case 0: return "by Unknown"
        case 1, 2: return "by " + names.joined(separator: " & ")
        default: return "by \(names[0]) & \(names.count - 1) more"
        }
    }
}
#endif
