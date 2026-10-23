import Foundation
import Testing

/// Validates the JSON shape used for `skin_path_index.json` (identifier → file path).
/// Ported from Provenance; `DeltaSkinManagerTests` covers the index itself.
@Suite("Path index format")
struct DeltaSkinPathIndexFormatTests {

    @Test func roundTripIdentifierToPathMap() throws {
        let original: [String: String] = [
            "com.example.skin": "/Documents/DeltaSkins/Example.deltaskin",
            "another.id": "/path/with spaces/Manic.skin/manicskin"
        ]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([String: String].self, from: data)
        #expect(decoded == original)
    }
}
