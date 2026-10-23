import Foundation

/// Date parsing for the skin catalog feed.
///
/// The feed mixes two shapes: the root and `submittedAt` use full ISO 8601
/// (`2026-10-04T05:11:24Z`), while every non-null per-skin `lastUpdated` is a bare
/// date (`2025-09-23`). A strict `.iso8601` decoder would reject those entries, so
/// dates are read as strings and parsed here, and anything unparseable becomes
/// `nil` instead of failing the entry.
///
/// Uses `Date.ISO8601FormatStyle` rather than a shared `DateFormatter` because
/// the format styles are `Sendable` value types.
public enum SkinCatalogDates {
    public static func parse(_ string: String?) -> Date? {
        guard let raw = string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let full = try? Date.ISO8601FormatStyle().parse(raw) {
            return full
        }
        if let fractional = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw) {
            return fractional
        }
        return try? Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day().parse(raw)
    }
}
