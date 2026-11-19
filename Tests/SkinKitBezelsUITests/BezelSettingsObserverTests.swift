//
//  BezelSettingsObserverTests.swift
//  SkinKitBezelsUI
//
//  Views re-read the stored choices when a store says one changed.
//

import Combine
import Foundation
import Testing
@testable import SkinKitBezelsUI

@Suite("BezelSettingsObserver")
@MainActor
struct BezelSettingsObserverTests {

    @Test("A store's change notification moves the observer on")
    func observes() async throws {
        let name = "SkinKitBezelsUITests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = UserDefaultsBezelSettings(defaults: defaults)
        let observer = BezelSettingsObserver()
        let before = observer.revision
        var changes = observer.$revision.dropFirst().values.makeAsyncIterator()
        settings.chosenBezel = "studio-monitor"
        let after = await changes.next()
        #expect(after == before + 1)
    }
}
