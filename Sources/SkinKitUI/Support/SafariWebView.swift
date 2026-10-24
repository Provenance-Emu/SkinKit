#if canImport(SafariServices) && canImport(UIKit)
import SafariServices
import SwiftUI

/// Safari WebView wrapper for presenting SFSafariViewController in SwiftUI. Internal copy of
/// Provenance's `SafariWebView` (kept internal so the two do not collide in the app).
struct SafariWebView: UIViewControllerRepresentable {
    let url: URL
    let entersReaderIfAvailable: Bool

    init(url: URL, entersReaderIfAvailable: Bool = false) {
        self.url = url
        self.entersReaderIfAvailable = entersReaderIfAvailable
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.barCollapsingEnabled = true
        config.entersReaderIfAvailable = entersReaderIfAvailable
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif
