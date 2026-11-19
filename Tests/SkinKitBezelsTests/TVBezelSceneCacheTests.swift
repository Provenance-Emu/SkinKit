//
//  TVBezelSceneCacheTests.swift
//  SkinKitBezels
//
//  The app-wide cache of built TV scenes.
//

import CoreGraphics
import Testing
@testable import SkinKitBezels

@Suite("TVBezelSceneCache")
struct TVBezelSceneCacheTests {

    /// A scene told apart by one of its values.
    private func scene(_ revision: Int) -> TVBezelScene {
        TVBezelScene(key: "test", tubeRect: .zero, presetID: TVBezelShader.presetID(libraryPath: "test/tv"),
                     values: ["revision": Float(revision)], borderPNG: nil)
    }

    @Test("A stored scene comes back, and an unknown key gives none")
    func roundTrip() {
        let cache = TVBezelSceneCache(capacity: 2)
        cache.store(scene(1), for: "a")
        #expect(cache.scene(for: "a")?.values["revision"] == 1)
        #expect(cache.scene(for: "b") == nil)
    }

    @Test("Past its capacity the least recently used scene goes")
    func evictsLeastRecentlyUsed() {
        let cache = TVBezelSceneCache(capacity: 2)
        cache.store(scene(1), for: "a")
        cache.store(scene(2), for: "b")
        cache.store(scene(3), for: "c")
        #expect(cache.scene(for: "a") == nil)
        #expect(cache.scene(for: "b")?.values["revision"] == 2)
        #expect(cache.scene(for: "c")?.values["revision"] == 3)
    }

    @Test("Reading a scene protects it from eviction")
    func readingRefreshes() {
        let cache = TVBezelSceneCache(capacity: 2)
        cache.store(scene(1), for: "a")
        cache.store(scene(2), for: "b")
        _ = cache.scene(for: "a")
        cache.store(scene(3), for: "c")
        #expect(cache.scene(for: "a")?.values["revision"] == 1)
        #expect(cache.scene(for: "b") == nil)
    }

    @Test("Storing a key again replaces its scene without growing the cache")
    func replaces() {
        let cache = TVBezelSceneCache(capacity: 2)
        cache.store(scene(1), for: "a")
        cache.store(scene(2), for: "a")
        cache.store(scene(3), for: "b")
        #expect(cache.scene(for: "a")?.values["revision"] == 2)
        #expect(cache.scene(for: "b")?.values["revision"] == 3)
    }

    @Test("Emptying the cache drops every scene")
    func empties() {
        let cache = TVBezelSceneCache(capacity: 2)
        cache.store(scene(1), for: "a")
        cache.removeAll()
        #expect(cache.scene(for: "a") == nil)
    }
}
