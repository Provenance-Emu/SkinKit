import Combine
import Foundation

/// The catalog entries being downloaded or installed right now, shared by every install path, so
/// one entry is never fetched and imported twice at once (two imports of the same file replace the
/// same installed skin under each other).
///
/// The catalog detail view's "Download & Install", a family's per-variant install and its
/// "Install all" all claim an entry here first and skip it when it's already claimed.
@MainActor
public final class SkinCatalogInstallTracker: ObservableObject {
    public static let shared = SkinCatalogInstallTracker()

    /// Entry ids with an install in flight.
    @Published public private(set) var inFlight: Set<String> = []

    public init() {}

    /// Whether `entryId` has an install in flight.
    public func isInFlight(_ entryId: String) -> Bool {
        inFlight.contains(entryId)
    }

    /// Claims `entryId` for an install. Returns `false`, claiming nothing, when it is already in
    /// flight; on `true` the caller must `end(_:)` it when done, however it ends.
    @discardableResult
    public func begin(_ entryId: String) -> Bool {
        inFlight.insert(entryId).inserted
    }

    /// Releases a claim from `begin(_:)`.
    public func end(_ entryId: String) {
        inFlight.remove(entryId)
    }
}

/// Why a catalog install didn't run.
public enum SkinCatalogInstallError: Error, Equatable, LocalizedError {
    /// Another install of the same entry was already in flight; this one was skipped.
    case alreadyInProgress(entryId: String)

    public var errorDescription: String? {
        switch self {
        case .alreadyInProgress: "This skin is already being installed."
        }
    }
}
