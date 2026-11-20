//
//  BezelSetting.swift
//  SkinKitBezelsUI
//
//  A stored TV choice as a view's property.
//

import Combine
import SkinKitBezels
import SwiftUI

/// Reads and writes one value of `BezelEnvironment.current.settings`, and redraws the view
/// when any of them changes.
@propertyWrapper
public struct BezelSetting<Value>: DynamicProperty {
    @StateObject private var observer = BezelSettingsObserver()
    private let keyPath: ReferenceWritableKeyPath<any BezelSettingsStore, Value>

    public init(_ keyPath: ReferenceWritableKeyPath<any BezelSettingsStore, Value>) {
        self.keyPath = keyPath
    }

    public var wrappedValue: Value {
        get {
            _ = observer.revision
            return BezelEnvironment.current.settings[keyPath: keyPath]
        }
        nonmutating set {
            BezelEnvironment.current.settings[keyPath: keyPath] = newValue
            observer.revision += 1
        }
    }

    public var projectedValue: Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}

/// Publishes when a `BezelSettingsStore` reports a change.
final class BezelSettingsObserver: ObservableObject {
    @Published var revision = 0
    private var subscription: AnyCancellable?

    /// - Parameter store: the only store to listen to; `nil` for every store, which is what
    ///   views want (the app has one).
    init(store: (any BezelSettingsStore)? = nil) {
        subscription = NotificationCenter.default.publisher(for: .bezelSettingsDidChange, object: store)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.revision += 1 }
    }
}
