#if canImport(UIKit)
import SkinKitCore
import SkinKitManager
import SkinCatalogKit
import SwiftUI

/// Hosting controller that forces hidden Home Indicator and defers system gestures on edges
public final class SkinHostingController<Content: View>: UIHostingController<Content> {
	#if os(iOS)
	/// Always hide the home indicator while emulation is active
	public override var prefersHomeIndicatorAutoHidden: Bool { true }
	/// Defer system gestures on edges to reduce accidental swipes
	public override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.left, .right, .bottom] }

	public override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		setNeedsUpdateOfHomeIndicatorAutoHidden()
		setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
	}
	#endif
}
#endif
