#if canImport(SwiftUI)
import SwiftUI

extension View {
    /// Applies `transform` when `condition` holds. (Provenance's `PVUIBase` helper of the same shape;
    /// internal here so the two do not collide in the app.)
    @ViewBuilder
    func `if`<Content: View>(_ condition: @autoclosure () -> Bool, transform: (Self) -> Content) -> some View {
        if condition() {
            transform(self)
        } else {
            self
        }
    }
}
#endif
