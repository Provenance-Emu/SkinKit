import Foundation

/// A variant's label inside its family, derived the way the catalog's backfill derives
/// `variantLabel` (`Provenance-Emu/skins` `scripts/skin_schema.py`, `strip_variant_suffix` and
/// `derive_variant_label`, which port the website's `browse.js`).
///
/// Used when an entry has no `variantLabel` (catalogs before schema 3, records installed before
/// families existed). `nil` means "nothing derivable": show the full name.
public enum SkinVariantLabel {
    /// Tried in this order; the first one found at an index above 0 wins.
    public static let separators = [" — ", " - "]

    /// The name before the first separator, else the whole name.
    public static func stripSuffix(_ fullName: String) -> String {
        for separator in separators {
            if let range = fullName.range(of: separator), range.lowerBound > fullName.startIndex {
                return String(fullName[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return fullName
    }

    /// The text after the first separator. Without one, `fullName` minus `baseName` (the family's
    /// name) from the front, case-insensitively, with leading spaces, dashes and colons dropped.
    /// `nil` when neither gives anything.
    public static func derive(fullName: String, baseName: String?) -> String? {
        guard !fullName.isEmpty else { return nil }
        for separator in separators {
            if let range = fullName.range(of: separator), range.lowerBound > fullName.startIndex {
                let rest = fullName[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                return rest.isEmpty ? nil : rest
            }
        }
        guard let baseName, !baseName.isEmpty,
              fullName.lowercased().hasPrefix(baseName.lowercased())
        else {
            return nil
        }
        let afterBase = fullName.dropFirst(baseName.count)
        let leading = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-—:"))
        let rest = String(afterBase.drop { $0.unicodeScalars.allSatisfy(leading.contains) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }

    /// An explicit label when there is one, else the derived one, else `nil`.
    public static func resolve(explicit: String?, fullName: String, baseName: String?) -> String? {
        if let explicit = explicit?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            return explicit
        }
        return derive(fullName: fullName, baseName: baseName)
    }
}
