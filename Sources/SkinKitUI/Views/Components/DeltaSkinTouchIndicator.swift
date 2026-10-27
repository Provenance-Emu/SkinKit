#if canImport(UIKit)
import SwiftUI

/// A circle under a finger on the skin, in the view's tint color (the app tints the skin view to match
/// its theme). Drawn by ``DeltaSkinView`` when `DeltaSkinInteractionSettings.showsTouchFeedback` is on.
/// Moved from iFly, which colored it from its theme directly.
struct DeltaSkinTouchIndicator: View {
    let location: CGPoint

    init(at location: CGPoint) {
        self.location = location
    }

    var body: some View {
        Circle()
            .stroke(.tint, lineWidth: 2)
            .background(Circle().fill(.tint.opacity(0.3)))
            .frame(width: 20, height: 20)
            .position(location)
            .transition(.opacity)
    }
}
#endif
