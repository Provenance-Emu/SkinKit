import SkinKitManager

/// Which cell of ``SystemSkinSelectionView`` carries the selection ring.
enum SkinPickerHighlight {
    /// Whether the Built-in cell is highlighted.
    ///
    /// - Parameters:
    ///   - scopedSelection: What the picker's scope stores, the built-in token included; `nil` when
    ///     this scope stores nothing.
    ///   - effectiveSelection: The packaged skin the whole session → game → system chain resolves to,
    ///     with the built-in token read as `nil`.
    ///   - emptySelectionMeansBuiltIn: The host shows its built-in controls when no packaged skin is
    ///     picked, instead of choosing one itself.
    static func isBuiltInHighlighted(
        scopedSelection: String?,
        effectiveSelection: String?,
        emptySelectionMeansBuiltIn: Bool
    ) -> Bool {
        if scopedSelection == DeltaSkinSelectionManager.builtInSkinPreferenceToken {
            return true
        }
        // Nothing stored here and no packaged skin anywhere in the chain: the built-in controls run.
        // A packaged skin inherited from another scope is not highlighted here, so neither is this.
        return emptySelectionMeansBuiltIn && scopedSelection == nil && effectiveSelection == nil
    }
}
