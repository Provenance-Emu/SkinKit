#if canImport(UIKit)
import SkinCatalogKit
import SkinKitManager
import SwiftUI

/// Scopes the catalog browser to one app's store.
///
/// Without a host, ``SkinCatalogBrowserView`` is Provenance's browser: the whole catalog, filtered
/// by system, installed into `DeltaSkinManager.shared`. With one (`SkinCatalogBrowserView(store:)`)
/// the same screen becomes that app's store:
///
/// - it lists only what `policy` places on a shelf and can install, and the shelves are the
///   category chips at the top (``SkinStoreListing``);
/// - skins made for the other device class are hidden (`device`);
/// - installs, progress, failures and the installed marks all go through `installer`, so the app's
///   own install step, retargeting and installed record apply, and `DeltaSkinManager.shared` is
///   never read or written;
/// - a cached catalog paints first and a failed download says so in a banner.
///
/// Not shown in a store: the device and orientation filters, "Set as active skin", Send to
/// RetroArch, creator profiles and the follow shelf. Those read Provenance's skin library.
///
/// Strings the screen draws itself are `Text` literals, so the app's main bundle localizes them;
/// the strings that depend on the app come in here already localized.
@MainActor
public struct SkinCatalogStoreHost {
    /// Which entries the store lists, on which shelf, and how each downloads.
    public var policy: SkinStorePolicy
    /// The app's installer. Its policy should be the same `policy`.
    public var installer: SkinStoreInstaller
    /// Hides entries made for the other device class. Starts as the device the app is running on;
    /// set it to `nil` to show them all.
    public var device: SkinStoreDevice?
    public var service: SkinCatalogService
    /// The chip title of a shelf. The default is the shelf's own English `title`.
    public var categoryTitle: (SkinStoreSection) -> String
    /// A line shown under the chips while a shelf is selected, and on the detail page of its
    /// skins: what installing from this shelf does (iFly: "remapped to the Dreamcast pad").
    public var categoryNote: (SkinStoreSection) -> String?
    /// Turns a catalog load failure into the text shown on screen.
    public var describeError: (any Error) -> String

    public init(
        policy: SkinStorePolicy,
        installer: SkinStoreInstaller,
        service: SkinCatalogService = .shared,
        categoryTitle: @escaping (SkinStoreSection) -> String = { $0.title },
        categoryNote: @escaping (SkinStoreSection) -> String? = { _ in nil },
        describeError: @escaping (any Error) -> String = { $0.localizedDescription }
    ) {
        self.policy = policy
        self.installer = installer
        device = SkinStoreDevice.current
        self.service = service
        self.categoryTitle = categoryTitle
        self.categoryNote = categoryNote
        self.describeError = describeError
    }

    /// The shelf `entry` is on, or `nil` when the store doesn't list it.
    func section(for entry: SkinCatalogEntry) -> SkinStoreSection? {
        policy.section(for: entry)
    }

    /// The note for the shelf `entry` is on.
    func note(for entry: SkinCatalogEntry) -> String? {
        section(for: entry).flatMap(categoryNote)
    }

    /// Whether any member of `family` is installed, for the card's check mark.
    func isInstalled(_ family: SkinFamily) -> Bool {
        family.members.contains { installer.state(for: $0) == .installed }
    }

    /// What "Install all" fetches for `family`: every member the policy can install.
    func installAllPlan(for family: SkinFamily) -> SkinDownloadPlan {
        family.downloadPlan(policy: policy)
    }
}
#endif
