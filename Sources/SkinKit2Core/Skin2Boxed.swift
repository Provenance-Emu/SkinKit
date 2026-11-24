import Foundation

/// Keeps a large optional field of a node out of line, so the node stays small.
///
/// The resolver, the validator and the drawer recurse once per tree level and their frames hold several copies of
/// a node. Secondary threads have 512 KB of stack; with every field inline, a debug build overflowed it five
/// levels deep. A boxed field costs one pointer in the node and reads and writes like the plain optional.
@propertyWrapper
public struct Skin2Boxed<Value: Hashable & Sendable>: Hashable, Sendable {
    private indirect enum Storage: Hashable, Sendable {
        case none
        case some(Value)
    }

    private var storage: Storage

    public init(wrappedValue: Value?) { storage = wrappedValue.map(Storage.some) ?? .none }

    public var wrappedValue: Value? {
        get { if case .some(let v) = storage { return v } else { return nil } }
        set { storage = newValue.map(Storage.some) ?? .none }
    }
}
