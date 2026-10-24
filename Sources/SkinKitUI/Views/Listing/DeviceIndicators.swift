#if canImport(UIKit)
import SkinKitCore
import SkinKitManager
import SkinCatalogKit
//
//  DeviceIndicators.swift
//  PVUI
//
//  Created by Joseph Mattiello on 3/30/25.
//

import SwiftUI

/// Device support indicators
struct DeviceIndicators: View {
    let skin: any DeltaSkinRenderable

    var body: some View {
        HStack(spacing: 4) {
            if skin.supports(DeltaSkinTraits(device: .iphone, displayType: .standard, orientation: .portrait)) {
                Image(systemName: "iphone")
            }
            if skin.supports(DeltaSkinTraits(device: .ipad, displayType: .standard, orientation: .portrait)) {
                Image(systemName: "ipad")
            }
        }
    }
}
#endif
