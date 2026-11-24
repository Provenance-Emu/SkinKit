#if canImport(UIKit) && !os(tvOS)
import SkinCatalogKit
import SkinKitManager
import SwiftUI

// The pieces of the catalog browser and detail view that differ when a host scopes them to its
// store (``SkinCatalogStoreHost``): everything that installs goes through the host's
// `SkinStoreInstaller` instead of `DeltaSkinManager.shared`.

// MARK: - Installer observation

/// Rebuilds its content when the store's installer publishes, so a view that only sometimes has a
/// store doesn't need an optional `@ObservedObject`.
struct SkinStoreInstallerReader<Content: View>: View {
    @ObservedObject var installer: SkinStoreInstaller
    @ViewBuilder let content: (SkinStoreInstaller) -> Content

    var body: some View {
        content(installer)
    }
}

// MARK: - Shared chrome

private struct SkinStorePanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.5))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(SkinKitTheme.current.gradient, lineWidth: 1))
            )
    }
}

/// A line of host copy about a shelf (what installing from it does).
struct SkinStoreCategoryNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(SkinKitTheme.current.horizontalGradient)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shown while a cached catalog stands in for a download that failed.
struct SkinStoreOfflineBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(SkinKitTheme.current.horizontalGradient)
            VStack(alignment: .leading, spacing: 2) {
                Text("Offline. Showing skins from your last visit.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.4))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
        )
        .padding(.horizontal)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail: install

/// The detail view's action section in a store: Download & Install, progress with cancel,
/// Installing, Installed, or the failure with a retry. All of it is the installer's state for the
/// entry, so it agrees with the browser's check marks and the variants below.
struct SkinStoreDetailActionSection: View {
    let entry: SkinCatalogEntry
    let store: SkinCatalogStoreHost
    @ObservedObject var installer: SkinStoreInstaller

    var body: some View {
        let state = installer.state(for: entry)
        VStack(spacing: 12) {
            switch state {
            case .idle:
                installButton
            case let .downloading(progress):
                downloading(progress)
            case .installing:
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(SkinKitTheme.current.pink)
                    Text("INSTALLING...")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                        .tracking(1)
                }
                .modifier(SkinStorePanel())
            case .installed:
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                    Text("INSTALLED")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                        .tracking(1)
                }
                .modifier(SkinStorePanel())
            case let .failed(message):
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.orange)
                        Text("DOWNLOAD FAILED")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                            .tracking(1)
                    }
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                    installButton
                }
            }

            if let note = store.note(for: entry) {
                SkinStoreCategoryNote(text: note)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .animation(.easeInOut(duration: 0.3), value: state)
    }

    private var installButton: some View {
        Button {
            installer.startInstall(entry)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                Text("DOWNLOAD & INSTALL")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                    .tracking(1)
            }
            .modifier(SkinStorePanel())
        }
        .buttonStyle(.plain)
    }

    private func downloading(_ progress: Double) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("DOWNLOADING...")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                    .tracking(1)
                // The downloader reports 0 until it knows the length, and stays there when the
                // server never says: spin instead of sitting at 0%.
                if progress > 0 {
                    ProgressView(value: progress)
                        .tint(SkinKitTheme.current.pink)
                } else {
                    ProgressView()
                        .tint(SkinKitTheme.current.pink)
                }
            }
            Button {
                installer.cancelInstall(entry)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel Download")
        }
        .padding(.horizontal, 14)
        .modifier(SkinStorePanel())
    }
}

// MARK: - Detail: variants

/// The variants of a family in a store's detail view: each member the store lists, with its own
/// install control, plus "Install all". A single-file skin's packed variants are listed as
/// included in the one download.
struct SkinStoreVariantsSection: View {
    let family: SkinFamily
    /// The entry the detail view is showing; its row is marked.
    let current: SkinCatalogEntry
    let store: SkinCatalogStoreHost
    @ObservedObject var installer: SkinStoreInstaller
    let destination: (SkinCatalogEntry) -> AnyView

    private var plan: SkinDownloadPlan { store.installAllPlan(for: family) }

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
    }

    private var installAllButton: some View {
        let remaining = installer.remaining(plan).count
        return Button {
            installer.startInstall(plan)
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
        .disabled(remaining == 0 || installer.isBusy(plan))
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

            memberAction(member)
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

    @ViewBuilder
    private func memberAction(_ member: SkinCatalogEntry) -> some View {
        let label = family.label(for: member)
        switch installer.state(for: member) {
        case .idle:
            Button {
                installer.startInstall(member)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(SkinKitTheme.current.horizontalGradient)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Install \(label)")
        case let .downloading(progress):
            Button {
                // "Install all" owns a plan task; a single install owns a member task.
                installer.cancelInstall(plan)
                installer.cancelInstall(member)
            } label: {
                if progress > 0 {
                    ProgressView(value: progress)
                        .progressViewStyle(.circular)
                        .tint(SkinKitTheme.current.pink)
                } else {
                    ProgressView()
                        .tint(SkinKitTheme.current.pink)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Downloading \(label)")
            .accessibilityHint("Cancels the download")
        case .installing:
            ProgressView()
                .tint(SkinKitTheme.current.pink)
                .accessibilityLabel("Installing \(label)")
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(.green)
                .accessibilityLabel("\(label) installed")
        case .failed:
            Button {
                installer.startInstall(member)
            } label: {
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .font(.system(size: 22))
                    .foregroundColor(.orange)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry \(label)")
        }
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
                    Image(systemName: SkinFamilyVariantsSection.icon(for: variant.kind))
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
}
#endif
