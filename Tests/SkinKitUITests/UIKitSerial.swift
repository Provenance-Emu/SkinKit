#if canImport(UIKit)
import Testing

/// Root of every test suite that touches UIKit or SwiftUI rendering.
///
/// `.serialized` applies to the nested suites too, so none of them run at the same time. That matters:
/// the first use of UIKit classes (`UIScreen`, `UIGraphicsImageRendererFormat`, the SwiftUI hosting
/// machinery) initialises them, and when several test threads and the main thread do that at once the
/// Objective-C class-initialisation locks deadlock (seen as a hang inside `initializeNonMetaClass`).
@Suite("SkinKitUI", .serialized)
enum UIKitSerial {}
#endif
