import Foundation
#if os(macOS)
import Security
#endif

/// A small key-value store that syncs across the user's devices, shaped after
/// `NSUbiquitousKeyValueStore` so tests can inject an in-memory one (``InMemoryKeyValueCloudStore``)
/// and an app without the key-value entitlement can pass `nil` and run local-only.
public protocol KeyValueCloudStore: AnyObject, Sendable {
    /// The stored blob for `key`, or nil if there is none.
    func data(forKey key: String) -> Data?

    /// Stores `data` under `key`. Does not notify the caller's own observers.
    func setData(_ data: Data, forKey key: String)

    /// Asks the system to sync now. Returns false when it could not.
    @discardableResult
    func synchronize() -> Bool

    /// Calls `handler` with the keys that changed when another device's write arrives. Delivery
    /// is on the main queue for the iCloud store. Observation lasts until the returned token is
    /// cancelled or released.
    func observeExternalChanges(_ handler: @escaping @Sendable (_ changedKeys: Set<String>) -> Void) -> KeyValueCloudObservation
}

/// Keeps an observation alive; cancelling it (or releasing it) stops delivery.
public final class KeyValueCloudObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var onCancel: (() -> Void)?

    public init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        let work = lock.withLock { () -> (() -> Void)? in
            defer { onCancel = nil }
            return onCancel
        }
        work?()
    }

    deinit {
        cancel()
    }
}

/// ``KeyValueCloudStore`` over `NSUbiquitousKeyValueStore`.
///
/// Needs the `com.apple.developer.ubiquity-kvstore-identifier` entitlement in the host app. Without
/// it the system store accepts writes and never syncs them, which is the same as local-only.
public final class UbiquitousKeyValueCloudStore: KeyValueCloudStore, @unchecked Sendable {
    /// The entitlement the host app needs.
    public static let entitlementKey = "com.apple.developer.ubiquity-kvstore-identifier"

    private let store: NSUbiquitousKeyValueStore

    public init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
    }

    /// The iCloud store, or nil when this process is known not to have the entitlement.
    ///
    /// On macOS (where the package's tests run unsigned) the entitlement is read from the process's
    /// code signature, so a host-side test never touches the user's real iCloud store. On iOS and
    /// tvOS an app can't read its own entitlements, so this always returns the store there: an
    /// unentitled build is inert, as described above.
    public static func ifEntitled() -> UbiquitousKeyValueCloudStore? {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              SecTaskCopyValueForEntitlement(task, entitlementKey as CFString, nil) != nil
        else { return nil }
        #endif
        return UbiquitousKeyValueCloudStore()
    }

    public func data(forKey key: String) -> Data? {
        store.data(forKey: key)
    }

    public func setData(_ data: Data, forKey key: String) {
        store.set(data, forKey: key)
    }

    @discardableResult
    public func synchronize() -> Bool {
        store.synchronize()
    }

    public func observeExternalChanges(_ handler: @escaping @Sendable (Set<String>) -> Void) -> KeyValueCloudObservation {
        let token = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            handler(Set(keys))
        }
        return KeyValueCloudObservation {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

/// An in-memory ``KeyValueCloudStore`` for tests and previews.
///
/// ``replica()`` returns another handle onto the same data, standing in for a second device signed
/// into the same iCloud account: a write through one replica reaches the others and notifies their
/// observers, never the writer's own, as the real store does. Delivery is synchronous.
public final class InMemoryKeyValueCloudStore: KeyValueCloudStore, @unchecked Sendable {
    private final class Backing: @unchecked Sendable {
        let lock = NSRecursiveLock()
        var values: [String: Data] = [:]
        var replicas: [Weak] = []
    }

    private struct Weak {
        weak var store: InMemoryKeyValueCloudStore?
    }

    private let backing: Backing
    private let lock = NSLock()
    private var handlers: [UUID: @Sendable (Set<String>) -> Void] = [:]

    /// Number of ``synchronize()`` calls, for tests.
    public private(set) var synchronizeCount = 0

    public init() {
        backing = Backing()
        backing.replicas.append(Weak(store: self))
    }

    private init(sharing backing: Backing) {
        self.backing = backing
        backing.lock.withLock { backing.replicas.append(Weak(store: self)) }
    }

    /// Another device on the same account.
    public func replica() -> InMemoryKeyValueCloudStore {
        InMemoryKeyValueCloudStore(sharing: backing)
    }

    public func data(forKey key: String) -> Data? {
        backing.lock.withLock { backing.values[key] }
    }

    public func setData(_ data: Data, forKey key: String) {
        let others = backing.lock.withLock { () -> [InMemoryKeyValueCloudStore] in
            backing.values[key] = data
            return backing.replicas.compactMap(\.store).filter { $0 !== self }
        }
        for other in others {
            other.deliver([key])
        }
    }

    @discardableResult
    public func synchronize() -> Bool {
        lock.withLock { synchronizeCount += 1 }
        return true
    }

    public func observeExternalChanges(_ handler: @escaping @Sendable (Set<String>) -> Void) -> KeyValueCloudObservation {
        let id = UUID()
        lock.withLock { handlers[id] = handler }
        return KeyValueCloudObservation { [weak self] in
            guard let self else { return }
            self.lock.withLock { _ = self.handlers.removeValue(forKey: id) }
        }
    }

    /// Delivers a change to this replica's observers as if another device wrote `keys`.
    public func deliver(_ keys: Set<String>) {
        let current = lock.withLock { Array(handlers.values) }
        for handler in current {
            handler(keys)
        }
    }
}
