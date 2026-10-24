extension Collection {
    /// The element at `index`, or `nil` when out of range.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
