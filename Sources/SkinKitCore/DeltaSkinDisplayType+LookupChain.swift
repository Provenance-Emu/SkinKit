import Foundation

public extension DeltaSkinDisplayType {
    /// The display-type buckets to try, in order, when looking up a representation.
    ///
    /// The two full-screen types fall back to each other (a skin that only declares `edgeToEdge` still
    /// serves `standard` traits, and the other way round), because callers often can't tell them apart:
    /// an emulation view that ignores safe areas reads zero insets and resolves `.standard` even on
    /// Face ID hardware. The special types (`splitView`, `stageManager`, `externalDisplay`) only match
    /// themselves. `DeltaSkin.representation(for:)` resolves through the same order; this is public
    /// for callers that read `jsonRepresentation` directly (iFly's per-item lookups) so the two
    /// can't disagree about which bucket a skin resolves to.
    var lookupChain: [DeltaSkinDisplayType] {
        switch self {
        case .standard: [.standard, .edgeToEdge]
        case .edgeToEdge: [.edgeToEdge, .standard]
        case .splitView, .stageManager, .externalDisplay: [self]
        }
    }
}
