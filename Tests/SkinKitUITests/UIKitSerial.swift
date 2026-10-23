#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit

/// Initialises UIKit and SwiftUI on the main thread before a test body runs.
///
/// The skin renderer asks `UIScreen.main` for its scale from background threads, and the test process
/// has no app, so UIKit's one-time setup (it loads its application context over XPC) happens on whichever
/// thread gets there first. When that is a background thread while the main thread is also entering UIKit,
/// the Objective-C class-initialisation locks deadlock (a hang inside `initializeNonMetaClass`, or in
/// `_UIApplicationConfigurationLoader`). Touching the same classes on the main thread first avoids it.
struct UIKitWarmUp: SuiteTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        await MainActor.run {
            _ = UIScreen.main.scale
            let format = UIGraphicsImageRendererFormat()
            _ = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { _ in }
            _ = UIHostingController(rootView: EmptyView()).view
        }
        try await function()
    }
}

/// Root of every test suite that touches UIKit or SwiftUI rendering. `.serialized` applies to the nested
/// suites too, so none of them run at the same time, and ``UIKitWarmUp`` runs before each test.
@Suite("SkinKitUI", .serialized, UIKitWarmUp())
enum UIKitSerial {}
#endif
