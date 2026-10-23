import Foundation

/// Haptic feedback configuration for a skin button
public struct DeltaSkinHaptic: Codable, Equatable {
    /// Haptic style name: light, medium, heavy, soft, rigid (impact) or selection
    public let style: String
    /// Intensity 0.0–1.0 (ignored for selection style)
    public let intensity: Double

    public init(style: String = "medium", intensity: Double = 1.0) {
        self.style = style
        self.intensity = intensity
    }

    // Custom decoding so that skins omitting `style` or `intensity` still decode correctly.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style     = try container.decodeIfPresent(String.self, forKey: .style)     ?? "medium"
        intensity = try container.decodeIfPresent(Double.self,  forKey: .intensity) ?? 1.0
    }

    private enum CodingKeys: String, CodingKey {
        case style, intensity
    }
}
