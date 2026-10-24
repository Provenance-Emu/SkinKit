#if canImport(UIKit)
import Combine
import Foundation
import SkinKitCore
import SkinKitManager

/// A class responsible for loading Delta skins with progress tracking
///
/// Moved from Provenance. The system it loads for is described by ``System`` instead of
/// `SystemIdentifier` (PVPrimitives), and the case-controller check
/// (`CaseControllerDetector.isAllowedInAutomaticSkinSelection`) is the manager's
/// `configuration.isAllowedInAutomaticSelection`.
public final class DeltaSkinLoader: ObservableObject {
    // Published properties for UI updates
    @Published public var isLoading = true
    @Published public var loadingProgress: Double = 0.0
    @Published public var loadingStage: LoadingStage = .loading
    @Published public var selectedSkin: (any DeltaSkinRenderable)?
    @Published public var loadingError: Error?

    // Loading stages for better progress reporting
    public enum LoadingStage: String, CaseIterable {
        case loading = "Loading skin..."
        case complete = "Complete"

        public var progressValue: Double {
            switch self {
            case .loading: return 0.5
            case .complete: return 1.0
            }
        }
    }

    /// What the loader needs to know about a system. Provenance builds it from a `SystemIdentifier`:
    /// `System(id: SkinSystemID(system.rawValue), gameType: DeltaSkinGameType(systemIdentifier: system),
    /// catalogSystemCodes: system.relatedSkinCatalogSystemCodes, alsoAcceptedGameTypes: system == .GB ? [.gbc] : [])`.
    public struct System {
        public var id: SkinSystemID
        public var gameType: DeltaSkinGameType?
        public var catalogSystemCodes: Set<String>
        /// Other game types whose skins also fit this system (a Game Boy accepts Game Boy Color skins).
        public var alsoAcceptedGameTypes: Set<DeltaSkinGameType>

        public init(id: SkinSystemID, gameType: DeltaSkinGameType?, catalogSystemCodes: Set<String> = [],
                    alsoAcceptedGameTypes: Set<DeltaSkinGameType> = []) {
            self.id = id
            self.gameType = gameType
            self.catalogSystemCodes = catalogSystemCodes
            self.alsoAcceptedGameTypes = alsoAcceptedGameTypes
        }
    }

    private let manager: DeltaSkinManager

    public init(manager: DeltaSkinManager = .shared) {
        self.manager = manager
    }

    /// Load a skin for the given system
    /// Returns when the skin is resolved or no skin is available (no arbitrary timeout).
    public func loadSkin(forSystem system: System, systemName: String = "Unknown") async -> (any DeltaSkinRenderable)? {
        let systemId = system.id
        ILOG("skins: DeltaSkinLoader starting to load skin for system: \(systemId.rawValue) (name: \(systemName))")

        await MainActor.run { self.updateLoadingState(.loading) }

        do {
            let manager = self.manager

            let skinsAreLoaded = await MainActor.run { manager.skinsAreLoaded }
            if skinsAreLoaded {
                ILOG("skins: Skins already loaded, using fast path lookup")
                let orientation: SkinOrientation = .portrait
                if let selectedIdentifier = manager.selectionManager.effectiveSkinIdentifier(
                    for: systemId,
                    gameId: nil,
                    orientation: orientation
                ),
                    // Same companion-skin policy as `DeltaSkinManager.selectedSkin`; a rejected
                    // selection falls through to the default-skin lookup below.
                    manager.configuration.isAllowedInAutomaticSelection(selectedIdentifier),
                    let skin = await MainActor.run(body: { manager.loadedSkins.first(where: { $0.identifier == selectedIdentifier })?.renderable }) {
                    await MainActor.run {
                        self.selectedSkin = skin
                        self.updateLoadingState(.complete)
                    }
                    ILOG("skins: Found selected skin '\(skin.name)' in cache for system \(systemId.rawValue)")
                    return skin
                }

                if let gameType = system.gameType,
                   let skin = await MainActor.run(body: {
                       manager.loadedSkins.first(where: {
                           let matchesType = $0.gameType == gameType || system.alsoAcceptedGameTypes.contains($0.gameType)
                           guard matchesType else { return false }
                           return manager.configuration.isAllowedInAutomaticSelection($0.identifier)
                       })?.renderable
                   }) {
                    await MainActor.run {
                        self.selectedSkin = skin
                        self.updateLoadingState(.complete)
                    }
                    ILOG("skins: Found default skin '\(skin.name)' in cache for system \(systemId.rawValue)")
                    return skin
                }
                WLOG("skins: No skin found in cache for system \(systemId.rawValue), falling back to async load")
            } else {
                ILOG("skins: Skins not loaded yet, will trigger async load")
            }

            ILOG("skins: Attempting async load of skin for system \(systemId.rawValue)")
            if let gameType = system.gameType,
               let skin = try await manager.skinToUse(for: systemId, gameType: gameType,
                                                      catalogSystemCodes: system.catalogSystemCodes)?.renderable {
                await MainActor.run {
                    self.selectedSkin = skin
                    self.updateLoadingState(.complete)
                }
                ILOG("skins: Successfully loaded skin '\(skin.name)' for system \(systemId.rawValue)")
                return skin
            } else {
                WLOG("skins: No skin available for system: \(systemId.rawValue)")
                await MainActor.run { self.updateLoadingState(.complete) }
                return nil
            }
        } catch {
            ELOG("skins: Error loading skin for system \(systemId.rawValue): \(error)")
            await MainActor.run {
                self.loadingError = error
                self.updateLoadingState(.complete)
            }
            return nil
        }
    }

    /// Update the loading state with the new stage
    @MainActor
    private func updateLoadingState(_ stage: LoadingStage) {
        loadingStage = stage
        loadingProgress = stage.progressValue

        // When complete, set isLoading to false
        if stage == .complete {
            isLoading = false
        }

        ILOG("skins: DeltaSkinLoader loading stage: \(stage.rawValue) (\(Int(loadingProgress * 100))%)")
    }
}
#endif
