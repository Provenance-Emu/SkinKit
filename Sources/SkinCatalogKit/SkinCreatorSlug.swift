import Foundation

/// A Swift port of `slugify()` in `Provenance-Emu/skins` `scripts/generate_author_pages.py`, the
/// function that turns a catalog `author` string into a creator slug.
///
/// The catalog build stamps each entry with the resolved `creator`, but a catalog from before that
/// key existed has none, so the apps derive the same slug locally. The two must agree character for
/// character: `Fixtures/author-slugs.json` pins this port to the Python output for every author
/// string in the catalog.
///
/// The Python is:
///
///     slug = name.lower()
///     slug = re.sub(r"[^a-z0-9]+", "-", slug)
///     slug = slug.strip("-")
///     return slug[:50]
///
/// Note the truncation happens after the strip, so a 50-character slug can end in `-`.
public enum SkinCreatorSlug {
    /// Slugs are at most this many characters (creator profiles spec §1).
    public static let maxLength = 50

    /// The slug for an author string. Lowercase `[a-z0-9-]`, at most ``maxLength`` characters.
    /// Empty when `name` has no ASCII letter or digit in it (an all-CJK name, say); callers treat
    /// that as "no addressable profile".
    public static func make(from name: String) -> String {
        var slug = ""
        var pendingSeparator = false
        for scalar in name.lowercased().unicodeScalars {
            if isSlugCharacter(scalar) {
                if pendingSeparator, !slug.isEmpty {
                    slug.append("-")
                }
                pendingSeparator = false
                slug.unicodeScalars.append(scalar)
            } else {
                pendingSeparator = true
            }
        }
        // A trailing run of separators is simply never emitted, which is the `strip("-")`.
        return String(slug.prefix(maxLength))
    }

    private static func isSlugCharacter(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.value >= 0x61 && scalar.value <= 0x7A) || (scalar.value >= 0x30 && scalar.value <= 0x39)
    }
}
