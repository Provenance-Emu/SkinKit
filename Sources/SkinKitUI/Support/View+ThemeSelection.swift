#if canImport(SwiftUI)
import Combine
import SkinKitCore
import SwiftUI

extension View {
    /// Runs `action` on the main queue whenever the selected theme of the skin with `skinIdentifier` changes
    /// (see ``DeltaSkinThemeSelection/didChangeNotification``), whoever changed it.
    func onThemeSelectionChange(of skinIdentifier: String, perform action: @escaping () -> Void) -> some View {
        onReceive(
            NotificationCenter.default
                .publisher(for: DeltaSkinThemeSelection.didChangeNotification)
                .filter { $0.userInfo?[DeltaSkinThemeSelection.skinIdentifierUserInfoKey] as? String == skinIdentifier }
                .receive(on: DispatchQueue.main)
        ) { _ in action() }
    }
}
#endif
