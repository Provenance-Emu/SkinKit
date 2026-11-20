//
//  TVBezelRoomLight.swift
//  SkinKitBezels
//
//  Whether the picture lights the room around a TV.
//

import Foundation
#if canImport(Metal)
import Metal
#endif

/// The room-light setting, which goes by the device until the player sets it.
public enum TVBezelRoomLight {

    /// Apple GPU family 7 and later (A14, M1). The room-light preset runs its ambient passes at
    /// the tube's size and costs several times the plain preset.
    public static let gpuIsRecent: Bool = {
        #if canImport(Metal)
        return MTLCreateSystemDefaultDevice()?.supportsFamily(.apple7) ?? false
        #else
        return false
        #endif
    }()

    public static var isOn: Bool {
        ExternalDisplayBezelRules.lightsRoom(stored: BezelEnvironment.current.settings.lightsRoom, gpuIsRecent: gpuIsRecent)
    }

    public static func set(_ isOn: Bool) {
        BezelEnvironment.current.settings.lightsRoom = isOn
    }
}
