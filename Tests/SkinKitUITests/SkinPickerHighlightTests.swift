import SkinKitManager
import Testing
@testable import SkinKitUI

@Suite("Skin picker Built-in highlight")
struct SkinPickerHighlightTests {
    private let token = DeltaSkinSelectionManager.builtInSkinPreferenceToken

    @Test("A stored built-in token is highlighted whatever the host's default", arguments: [false, true])
    func storedToken(emptyMeansBuiltIn: Bool) {
        #expect(SkinPickerHighlight.isBuiltInHighlighted(scopedSelection: token, effectiveSelection: nil,
                                                         emptySelectionMeansBuiltIn: emptyMeansBuiltIn))
    }

    @Test("An empty chain is Built-in only for hosts that show built-in controls by default")
    func emptyChain() {
        #expect(SkinPickerHighlight.isBuiltInHighlighted(scopedSelection: nil, effectiveSelection: nil,
                                                         emptySelectionMeansBuiltIn: true))
        #expect(!SkinPickerHighlight.isBuiltInHighlighted(scopedSelection: nil, effectiveSelection: nil,
                                                          emptySelectionMeansBuiltIn: false))
    }

    @Test("A packaged pick, here or inherited, is never Built-in", arguments: [false, true])
    func packagedPick(emptyMeansBuiltIn: Bool) {
        let skin = "com.example.skin"
        #expect(!SkinPickerHighlight.isBuiltInHighlighted(scopedSelection: skin, effectiveSelection: skin,
                                                          emptySelectionMeansBuiltIn: emptyMeansBuiltIn))
        #expect(!SkinPickerHighlight.isBuiltInHighlighted(scopedSelection: nil, effectiveSelection: skin,
                                                          emptySelectionMeansBuiltIn: emptyMeansBuiltIn))
    }
}
