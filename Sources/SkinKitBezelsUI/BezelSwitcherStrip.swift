//
//  BezelSwitcherStrip.swift
//  SkinKitBezels
//
//  The pause menu's TV switcher: a strip over the paused game, which shows each TV as it is
//  stepped onto.
//

#if os(iOS) || os(tvOS)
import Combine
import SkinKitBezels
import SwiftUI

/// The strip itself: the list of TVs and its buttons. It owns nothing; `BezelSwitcherHost`
/// holds the model and does the saving.
public struct BezelSwitcherStrip: View {
    @Binding var model: BezelSwitcherModel
    /// What an item is called: "Off", "Automatic · Living Room TV", a TV's name, "More…".
    let name: (BezelSwitcherModel.Item) -> String
    let isLoading: Bool
    let showsThisGameOnly: Bool
    /// Name the controller's buttons beside the actions.
    let showsControllerHints: Bool
    let supportsRoomLight: Bool
    let onKeep: () -> Void
    let onCancel: () -> Void
    let onMore: () -> Void

    #if os(tvOS)
    @FocusState private var focusedItem: String?
    /// Which focus changes are the player choosing a TV.
    @State private var focus = BezelStripFocus()

    /// How many times, and how far apart, the strip asks for focus when it opens.
    private static let focusAttempts = 20
    private static let focusRetryDelay: Duration = .milliseconds(50)
    #endif

    public init(model: Binding<BezelSwitcherModel>, name: @escaping (BezelSwitcherModel.Item) -> String,
                isLoading: Bool, showsThisGameOnly: Bool, showsControllerHints: Bool, supportsRoomLight: Bool = true,
                onKeep: @escaping () -> Void, onCancel: @escaping () -> Void, onMore: @escaping () -> Void) {
        _model = model
        self.name = name
        self.isLoading = isLoading
        self.showsThisGameOnly = showsThisGameOnly
        self.showsControllerHints = showsControllerHints
        self.supportsRoomLight = supportsRoomLight
        self.onKeep = onKeep
        self.onCancel = onCancel
        self.onMore = onMore
    }

    public var body: some View {
        VStack(spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.items) { item in
                            chip(item).id(item.id)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                #if os(tvOS)
                .focusSection()
                #endif
                .onAppear { proxy.scrollTo(model.selection.id, anchor: .center) }
                .onChange(of: model.selection.id) { _, id in
                    withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
            HStack(spacing: 12) {
                action(String(localized: "Keep"), hint: "a.circle", perform: onKeep)
                action(String(localized: "Cancel"), hint: "b.circle", perform: onCancel)
                if showsThisGameOnly {
                    action(model.thisGameOnly ? String(localized: "This game only: On") : String(localized: "This game only: Off"),
                           hint: "y.circle") { model.thisGameOnly.toggle() }
                }
                if supportsRoomLight {
                    action(model.lightsRoom ? String(localized: "Room light: On") : String(localized: "Room light: Off"),
                           hint: "x.circle") { model.lightsRoom.toggle() }
                }
                Spacer(minLength: 0)
                if isLoading { ProgressView() }
            }
            .padding(.horizontal, 16)
            #if os(tvOS)
            // The buttons sit at the left and the selected TV in the middle: as a section the
            // row is reached by moving down from any TV, not only from one right above a button.
            .focusSection()
            #endif
        }
        .padding(.vertical, 12)
        .background(.regularMaterial)
        #if os(tvOS)
        .defaultFocus($focusedItem, model.selection.id)
        .task {
            // The host disables the control that opened the strip, and tvOS leaves focus on it
            // until something asks for it: left and right then do nothing. Take it, and keep
            // asking until it has arrived on the list once.
            for _ in 0..<Self.focusAttempts {
                guard !focus.isOnList else { break }
                focusedItem = model.selection.id
                try? await Task.sleep(for: Self.focusRetryDelay)
            }
        }
        .onChange(of: focusedItem) { _, id in
            switch focus.focusChanged(to: id, selection: model.selection.id) {
            case .none: break
            case .moveFocus(let id): focusedItem = id
            case .select(let id): model.select(id: id)
            }
        }
        .onExitCommand(perform: onCancel)
        #endif
    }

    private func chip(_ item: BezelSwitcherModel.Item) -> some View {
        let isSelected = model.selection.id == item.id
        let button = Button {
            if item.group == .more {
                onMore()
            } else {
                #if os(tvOS)
                // Focus already chose it; Select keeps it.
                onKeep()
                #else
                model.select(id: item.id)
                #endif
            }
        } label: {
            Text(name(item))
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        #if os(tvOS)
        return button.focused($focusedItem, equals: item.id)
        #else
        return button
            .buttonStyle(.plain)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), in: Capsule())
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        #endif
    }

    private func action(_ title: String, hint: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            if showsControllerHints {
                Label(title, systemImage: hint)
            } else {
                Text(title)
            }
        }
        .buttonStyle(.bordered)
    }
}

/// What the switcher needs from the game being played. The app's emulator screen conforms,
/// or a small adapter beside it.
@MainActor
public protocol BezelSwitcherSession: AnyObject {
    /// The app's key for the running game (the key `BezelSettingsStore.pinnedBezels` uses);
    /// `nil` hides "this game only".
    var bezelGameID: String? { get }
    var bezelSystemID: String? { get }
    /// The game's system was played on a TV or monitor, not on a screen of its own.
    var bezelSystemSuitsTV: Bool { get }
    /// A TV the player chose could show right now. When it turns `false` (rotated to portrait,
    /// a skin applied) the strip closes itself.
    var canShowBezel: Bool { get }
    /// The TV being previewed is still loading.
    var isBezelLoading: Bool { get }
    /// The choice being tried. The app reads it ahead of the stored choices
    /// (`BezelChoice.resolve`) and redraws the paused game when it is set; `nil` ends the preview.
    var bezelPreview: BezelPreview? { get set }
}

/// The switcher as the pause menu shows it: builds the list for the running game, previews
/// the selection on the game behind it, and saves on Keep. Nothing is saved while browsing.
public struct BezelSwitcherHost: View {
    let session: any BezelSwitcherSession
    /// The pause menu's controller input on iOS; tvOS moves focus instead.
    let commands: AnyPublisher<BezelNavigationCommand, Never>?
    /// Name the controller's buttons beside the actions.
    let showsControllerHints: Bool
    let supportsRoomLight: Bool
    /// The strip is done (kept or cancelled): go back to the pause menu.
    let onClose: () -> Void
    /// Open the bezel library in the strip's place.
    let onMore: () -> Void

    @State private var model: BezelSwitcherModel
    @State private var isLoading = false
    /// Keep, Cancel or More has run. The strip stays on screen for a moment after that, and
    /// nothing may preview or close again in it.
    @State private var isClosed = false

    /// How long a selection must rest before the game behind is redrawn in it, so holding a
    /// direction does not load every TV passed over.
    private static let previewDelay: Duration = .milliseconds(150)
    /// How often the loading mark and the "can a TV still show" check are refreshed.
    private static let pollInterval: TimeInterval = 0.25

    private var settings: any BezelSettingsStore { BezelEnvironment.current.settings }

    @MainActor
    public init(session: any BezelSwitcherSession, commands: AnyPublisher<BezelNavigationCommand, Never>?,
                showsControllerHints: Bool, supportsRoomLight: Bool = true,
                onClose: @escaping () -> Void, onMore: @escaping () -> Void) {
        self.session = session
        self.commands = commands
        self.showsControllerHints = showsControllerHints
        self.supportsRoomLight = supportsRoomLight
        self.onClose = onClose
        self.onMore = onMore
        let settings = BezelEnvironment.current.settings
        let pinned = settings.pinnedBezel(forGame: session.bezelGameID)
        _model = State(initialValue: BezelSwitcherModel(
            builtIn: TVBezelCatalog.bundled.map(\.id),
            shaderPresets: TVBezelCatalog.shaderPresets.map(\.id),
            yours: TVBezelLibrary.shared.listed.map(\.id),
            current: pinned ?? settings.chosenBezel,
            gameHasPin: pinned != nil,
            lightsRoom: supportsRoomLight && TVBezelRoomLight.isOn))
    }

    private struct PreviewKey: Equatable {
        let id: String
        let lightsRoom: Bool
    }

    public var body: some View {
        BezelSwitcherStrip(model: $model,
                           name: name,
                           isLoading: isLoading,
                           showsThisGameOnly: session.bezelGameID != nil,
                           showsControllerHints: commands != nil && showsControllerHints,
                           supportsRoomLight: supportsRoomLight,
                           onKeep: keep,
                           onCancel: cancel,
                           onMore: more)
            .task(id: PreviewKey(id: model.selection.id, lightsRoom: model.lightsRoom)) {
                try? await Task.sleep(for: Self.previewDelay)
                guard !Task.isCancelled, !isClosed, model.selection.group != .more else { return }
                session.bezelPreview = .init(choice: model.selection.id, lightsRoom: model.lightsRoom)
            }
            .onReceive(Timer.publish(every: Self.pollInterval, on: .main, in: .common).autoconnect()) { _ in
                // Rotated to portrait, a skin applied, the light gun raised: no TV can show now.
                guard session.canShowBezel else { return cancel() }
                isLoading = session.isBezelLoading
            }
            .onReceive(commands ?? Empty().eraseToAnyPublisher()) { handle($0) }
    }

    private func name(_ item: BezelSwitcherModel.Item) -> String {
        switch item.id {
        case ExternalDisplayBezelRules.noBezelID:
            return String(localized: "Off")
        case ExternalDisplayBezelRules.automaticBezelID:
            let automatic = TVBezelCatalog.resolve(chosen: item.id,
                                                   matchesSystem: settings.matchesSystem,
                                                   systemID: session.bezelSystemID,
                                                   systemSuitsTV: session.bezelSystemSuitsTV)
            if let bezel = automatic.bezel {
                return String(localized: "Automatic · \(bezel.name)")
            }
            if automatic.resolution.outcome == .noneForSystem {
                return String(localized: "Automatic · none for this system")
            }
            return String(localized: "Automatic · no TV available")
        case BezelSwitcherModel.moreID:
            return String(localized: "More…")
        default:
            return TVBezelCatalog.bezel(id: item.id)?.name ?? item.id
        }
    }

    /// Inside the strip the pad's buttons mean the strip's actions: one face button is room
    /// light and another "this game only", and the shoulder buttons jump between groups.
    private func handle(_ command: BezelNavigationCommand) {
        switch command {
        case .left: model.step(-1)
        case .right: model.step(1)
        case .previousGroup: model.jumpGroup(-1)
        case .nextGroup: model.jumpGroup(1)
        case .activate: keep()
        case .back: cancel()
        case .toggleRoomLight:
            if supportsRoomLight { model.lightsRoom.toggle() }
        case .toggleThisGameOnly:
            if session.bezelGameID != nil { model.thisGameOnly.toggle() }
        case .up, .down: break
        }
    }

    private func keep() {
        guard !isClosed else { return }
        let gameID = session.bezelGameID
        let (systemID, suitsTV, settings) = (session.bezelSystemID, session.bezelSystemSuitsTV, settings)
        let commit = model.commit(gameHasPin: settings.pinnedBezel(forGame: gameID) != nil) { choice in
            BezelChoice.shownBezelID(ifChosen: choice, gameID: gameID, systemID: systemID, systemSuitsTV: suitsTV,
                                     settings: settings)
        }
        guard let commit else { return more() }
        isClosed = true
        if let chosen = commit.chosen { settings.chosenBezel = chosen }
        if let gameID { BezelChoice.apply(commit.pin, toGame: gameID, settings: settings) }
        // Only a change is stored: an untouched setting keeps going by the device.
        if supportsRoomLight, commit.lightsRoom != TVBezelRoomLight.isOn { TVBezelRoomLight.set(commit.lightsRoom) }
        session.bezelPreview = nil
        onClose()
    }

    private func cancel() {
        guard !isClosed else { return }
        isClosed = true
        session.bezelPreview = nil
        onClose()
    }

    private func more() {
        guard !isClosed else { return }
        isClosed = true
        session.bezelPreview = nil
        onMore()
    }
}
#endif
