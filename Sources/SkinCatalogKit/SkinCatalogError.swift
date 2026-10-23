import Foundation

/// Why the skin catalog could not be produced (network AND every cache failed).
///
/// `errorDescription` is plain English. An app that localizes passes its lookup to
/// `message(localizing:)`; the English strings are the lookup keys (they are the same keys iCube's
/// `L()` already uses), or it can switch on the cases and write its own copy.
public enum SkinCatalogError: LocalizedError {
    case httpStatus(Int)
    case network(String)
    case decoding(String)

    public var errorDescription: String? {
        message(localizing: { $0 })
    }

    /// The description with each format string run through `localize` first.
    public func message(localizing localize: (String) -> String) -> String {
        switch self {
        case let .httpStatus(code):
            String(format: localize("The skin catalog server answered with HTTP %d."), code)
        case let .network(message):
            String(format: localize("The skin catalog could not be downloaded: %@"), message)
        case let .decoding(message):
            String(format: localize("The skin catalog could not be read: %@"), message)
        }
    }
}
