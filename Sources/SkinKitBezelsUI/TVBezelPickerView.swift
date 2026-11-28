//
//  TVBezelPickerView.swift
//  SkinKitBezels
//
//  Picks the TV around the picture on an external display, and brings in bezels.
//

#if os(iOS) || os(tvOS)
import Combine
import SwiftUI
import SkinKitBezels
import UniformTypeIdentifiers

/// The list of TVs: none, the built-in ones and the player's own, with import.
public struct TVBezelPickerView: View {
    /// The chosen TV's id. `nil` is *Automatic*, offered only with `allowsAutomatic`.
    @Binding var selection: String?
    /// The list is choosing for one game, which can also be left to the settings.
    var allowsAutomatic = false
    /// The list is the choice for every game, which can be left to each game's system.
    var offersSystemAutomatic = false
    /// The running game, to choose its artwork from The Bezel Project by hand.
    var game: ExternalDisplayGameContext?
    var controllerCommands: AnyPublisher<BezelNavigationCommand, Never>?
    /// Where the player sits in front of a built-in TV; `nil` hides the Seat row.
    var seat: Binding<TVBezelSeat>?
    @Environment(\.dismiss) private var dismiss
    @State private var cursor = 0
    /// The controller's cursor is on the Seat row, which sits above the first choice.
    @State private var cursorOnSeat = false
    /// The Seat row's place in the list, for scrolling to it.
    private static let seatRowID = "SkinKitBezelsUI.seatRow"
    @State private var pickerVisible = false

    private var choices: [String?] {
        (allowsAutomatic ? [nil] : [])
            + (offersSystemAutomatic ? [ExternalDisplayBezelRules.automaticBezelID] : [])
            + [ExternalDisplayBezelRules.noBezelID]
            + (TVBezelCatalog.bundled + TVBezelCatalog.shaderPresets + myBezels).map { Optional($0.id) }
    }


    @State private var myBezels = TVBezelLibrary.shared.listed
    @State private var isImporting = false
    @State private var importReport: String?
    @State private var editing: TVBezel?

    /// A RetroArch overlay description, which has no type of its own.
    private static let importTypes: [UTType] = [.png, .folder] + [UTType(filenameExtension: TVBezelLibrary.configExtension)].compactMap { $0 }

    /// - Parameters:
    ///   - selection: the chosen TV's id. `nil` is *Automatic*, offered only with `allowsAutomatic`.
    ///   - allowsAutomatic: the list is choosing for one game, which can also be left to the settings.
    ///   - offersSystemAutomatic: the list is the choice for every game, which can be left to
    ///     each game's system.
    ///   - game: the running game, to choose its artwork from The Bezel Project by hand.
    ///   - controllerCommands: the app's controller input while the list is on screen.
    ///   - seat: the app's Seat setting, to offer it in the list; `nil` leaves it out.
    public init(selection: Binding<String?>, allowsAutomatic: Bool = false, offersSystemAutomatic: Bool = false,
                game: ExternalDisplayGameContext? = nil,
                controllerCommands: AnyPublisher<BezelNavigationCommand, Never>? = nil,
                seat: Binding<TVBezelSeat>? = nil) {
        self.seat = seat
        _selection = selection
        self.allowsAutomatic = allowsAutomatic
        self.offersSystemAutomatic = offersSystemAutomatic
        self.game = game
        self.controllerCommands = controllerCommands
    }

    public var body: some View {
        ScrollViewReader { scroll in
            pickerList
                .onChange(of: cursor) { _, index in
                    guard choices.indices.contains(index) else { return }
                    scroll.scrollTo(choices[index], anchor: .center)
                }
                .onChange(of: cursorOnSeat) { _, onSeat in
                    if onSeat { scroll.scrollTo(Self.seatRowID, anchor: .center) }
                }
        }
        .onAppear {
            pickerVisible = true
            cursor = choices.firstIndex(of: selection) ?? 0
        }
        .onDisappear { pickerVisible = false }
        .onReceive(controllerCommands ?? Empty().eraseToAnyPublisher()) { command in
            guard pickerVisible, editing == nil, !isImporting, !choices.isEmpty else { return }
            switch command {
            case .up:
                // The Seat row is one step above the first choice.
                if cursor == 0, seat != nil { cursorOnSeat = true }
                cursor = max(0, cursor - 1)
            case .down:
                if cursorOnSeat { cursorOnSeat = false } else { cursor = min(choices.count - 1, cursor + 1) }
            case .activate:
                if cursorOnSeat, let seat {
                    seat.wrappedValue = seat.wrappedValue.nextCloser
                    return
                }
                guard choices.indices.contains(cursor) else { return }
                selection = choices[cursor]
            case .back: dismiss()
            default: break
            }
        }
    }

    private var pickerList: some View {
        List {
            if let seat {
                Section {
                    Picker(String(localized: "Seat"), selection: seat) {
                        ForEach(TVBezelSeat.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .id(Self.seatRowID)
                    .listRowBackground(controllerCommands != nil && cursorOnSeat ? Color.accentColor.opacity(0.25) : nil)
                } footer: {
                    Text("How close you sit to a built-in TV. A closer seat shows less of the room and a larger picture.")
                }
            }

            Section {
                if allowsAutomatic {
                    row(String(localized: "Automatic"), id: nil)
                }
                if offersSystemAutomatic {
                    row(String(localized: "Automatic"), id: ExternalDisplayBezelRules.automaticBezelID)
                }
                row(String(localized: "None"), id: ExternalDisplayBezelRules.noBezelID)
            } footer: {
                if allowsAutomatic {
                    Text("Automatic follows the Bezels settings. Anything else is used for this game only.")
                } else if offersSystemAutomatic {
                    Text("Automatic shows a TV for consoles and computers, and none for handhelds.")
                }
            }

            Section(String(localized: "Built In")) {
                ForEach(TVBezelCatalog.bundled) { bezel in
                    row(bezel.name, id: bezel.id)
                }
            }

            if !TVBezelCatalog.shaderPresets.isEmpty {
                Section(String(localized: "Shader Bezels")) {
                    ForEach(TVBezelCatalog.shaderPresets) { bezel in
                        row(bezel.name, id: bezel.id)
                    }
                }
            }

            Section {
                ForEach(myBezels) { bezel in
                    HStack {
                        row(bezel.name, id: bezel.id, detail: systemName(of: bezel))
                        Button {
                            editing = bezel
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(String(localized: "Edit \(bezel.name)"))
                    }
                }
                .onDelete { offsets in
                    offsets.map { myBezels[$0].id }.forEach(TVBezelLibrary.shared.delete(id:))
                }
                #if os(iOS)
                Button {
                    isImporting = true
                } label: {
                    Label(String(localized: "Import a Bezel…"), systemImage: "square.and.arrow.down")
                }
                #endif
            } header: {
                Text("My Bezels")
            } footer: {
                Text("A bezel is a PNG image with a see-through area where the game shows, such as a RetroArch overlay. "
                     + "You can also put PNG files in the Bezels/Imported folder.")
            }

            if let game, BezelProjectService.systems[game.systemID] != nil {
                Section {
                    NavigationLink(String(localized: "Choose from The Bezel Project…")) {
                        BezelProjectSystemView(systemID: game.systemID, game: game)
                    }
                }
            }
        }
        .navigationTitle(allowsAutomatic ? String(localized: "TV for This Game") : String(localized: "TV"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onReceive(NotificationCenter.default.publisher(for: TVBezelLibrary.didChangeNotification)) { _ in
            myBezels = TVBezelLibrary.shared.listed
        }
        .task {
            // Picks up files put in the folder by hand since the app started.
            await Task.detached(priority: .userInitiated) { TVBezelLibrary.shared.refresh() }.value
        }
        #if os(iOS)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: Self.importTypes, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            importFiles(urls)
        }
        .alert(String(localized: "Import"), isPresented: Binding(get: { importReport != nil }, set: { if !$0 { importReport = nil } })) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(importReport ?? "")
        }
        #endif
        .sheet(item: $editing) { bezel in
            TVBezelInfoView(bezel: bezel)
        }
    }

    private func row(_ name: String, id: String?, detail: String? = nil) -> some View {
        Button {
            selection = id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).foregroundStyle(.primary)
                    if let detail {
                        Text(detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selection == id {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .id(id)
        .listRowBackground(controllerCommands != nil && !cursorOnSeat && choices.firstIndex(of: id) == cursor ? Color.accentColor.opacity(0.25) : nil)
        .accessibilityAddTraits(selection == id ? .isSelected : [])
    }

    private func systemName(of bezel: TVBezel) -> String? {
        bezel.preferredSystems.first.flatMap(BezelEnvironment.current.systemName)
    }

    private func importFiles(_ urls: [URL]) {
        Task {
            let result = await Task.detached(priority: .userInitiated) { TVBezelLibrary.shared.importFiles(at: urls) }.value
            // One import that worked needs no report; it is in the list, and chosen.
            if result.problems.isEmpty, let only = result.imported.first, result.imported.count == 1 {
                selection = only.id
                return
            }
            var lines: [String] = []
            if !result.imported.isEmpty {
                lines.append(String(localized: "Imported \(result.imported.count)."))
            }
            lines += result.problems.map { "\($0.file): \($0.problem.message)" }
            importReport = lines.isEmpty ? String(localized: "No PNG images were found.") : lines.joined(separator: "\n")
        }
    }
}

/// Names a bezel and says which system it belongs to.
private struct TVBezelInfoView: View {
    let bezel: TVBezel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var systemID: String
    @State private var preview: UIImage?

    private static let anySystem = ""
    private static let previewPixels: CGFloat = 800
    private let systems = BezelEnvironment.current.systems().sorted { $0.name < $1.name }

    init(bezel: TVBezel) {
        self.bezel = bezel
        _name = State(initialValue: bezel.name)
        _systemID = State(initialValue: bezel.preferredSystems.first ?? Self.anySystem)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let preview {
                    Section {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .background(Color.black)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }
                }
                Section(String(localized: "Name")) {
                    TextField(String(localized: "Name"), text: $name)
                }
                Section {
                    Picker(String(localized: "Belongs To"), selection: $systemID) {
                        Text("Any System").tag(Self.anySystem)
                        ForEach(systems) { system in
                            Text(system.name).tag(system.id)
                        }
                    }
                } footer: {
                    Text("Games of that system use this bezel in place of your TV while Match the System's Screen is on.")
                }
            }
            .navigationTitle(String(localized: "Bezel"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) {
                        TVBezelLibrary.shared.update(id: bezel.id, name: name.trimmingCharacters(in: .whitespaces),
                                                     system: .some(systemID == Self.anySystem ? nil : systemID))
                        dismiss()
                    }
                }
            }
            .task {
                guard let url = bezel.image?.fileURL else { return }
                preview = await Task.detached(priority: .userInitiated) {
                    TVBezelImage.displayImage(url, maxPixel: Self.previewPixels).map { UIImage(cgImage: $0) }
                }.value
            }
        }
    }
}
#endif
