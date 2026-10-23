import Foundation
#if canImport(UIKit)
    import UIKit
#endif

/// Device classes the skin store filters by.
public enum SkinStoreDevice: Sendable {
    case iPhone
    case iPad

    /// The device this build is running on; `nil` where the store doesn't filter
    /// (tvOS has no touch skins, macOS isn't a target).
    @MainActor
    public static var current: SkinStoreDevice? {
        #if os(iOS)
            return UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #else
            return nil
        #endif
    }
}

/// Whether a catalog entry fits a device class. Pure, so it is testable. Not per-app config: it
/// came from iFly's store and iCube's store does not call it, but it is harmless to share.
///
/// The feed's `deviceSupport` field is the right source and wins whenever an entry fills it (it is
/// empty on every entry in the 2026-10-23 feed, so today nothing takes that path). Without it the
/// skin's name and tags are the only hint: deltastyles titles say "for iPhone" or "for iPad"
/// outright. A skin that names neither, or both, stays visible, since hiding something that works
/// is worse than showing something that doesn't. The installed skin's own representations still
/// decide what it draws.
public extension SkinStorePolicy {
    static func isCompatible(_ entry: SkinCatalogEntry, with device: SkinStoreDevice) -> Bool {
        let declared = Set(entry.deviceSupport.map { $0.lowercased() })
        if !declared.isEmpty {
            let universal: Set = ["universal", "both", "all"]
            if !declared.isDisjoint(with: universal) { return true }
            switch device {
            case .iPad: return declared.contains("ipad")
            case .iPhone: return declared.contains("iphone")
            }
        }

        let haystack = ([entry.name] + entry.tags).joined(separator: " ").lowercased()
        let namesIPad = haystack.range(of: #"\bipad\b"#, options: .regularExpression) != nil
        let namesIPhone = haystack.range(of: #"\biphones?\b"#, options: .regularExpression) != nil
        switch device {
        case .iPad: return !(namesIPhone && !namesIPad)
        case .iPhone: return !(namesIPad && !namesIPhone)
        }
    }

    /// `entries` without the ones that don't fit `device` (all of them when `device` is nil).
    static func filtered(_ entries: [SkinCatalogEntry], for device: SkinStoreDevice?) -> [SkinCatalogEntry] {
        guard let device else { return entries }
        return entries.filter { isCompatible($0, with: device) }
    }
}
