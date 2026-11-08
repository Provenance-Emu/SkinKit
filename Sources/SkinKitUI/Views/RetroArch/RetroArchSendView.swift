#if canImport(UIKit) && !os(tvOS)
import SkinKitCore
import SkinKitManager
import SkinKitRetroArch
import SwiftUI
import UIKit

// "Send to RetroArch": converts an installed skin to a RetroArch overlay folder with SkinKitRetroArch, shows what
// did not convert, and exports the folder with the document picker (share sheet as the second option).
// Design: docs/specs/2026-11-03-retroarch-ios-integration-design.md §4. iOS only; compiled out on tvOS.
//
// Public API for host apps:
//   RetroArchSendView(skin:)                 the sheet content for a skin you already hold
//   RetroArchSendSheet(skinIdentifier:)      resolves an installed skin by id, then shows the sheet (deep link)
//   View.retroArchSendSheet(item:)           presents the sheet for a RetroArchSendItem binding
//   RetroArchSendRoute.parse(_:) (SkinKitRetroArch)   recognizes provenance://skins/retroarch?skin=<id>

// MARK: - Item

/// A skin to send, as a sheet item.
public struct RetroArchSendItem: Identifiable {
    public let skin: any DeltaSkinProtocol
    public var id: String { skin.identifier }

    public init(skin: any DeltaSkinProtocol) {
        self.skin = skin
    }
}

public extension View {
    /// Presents the Send to RetroArch sheet for the item while it is non-nil.
    func retroArchSendSheet(item: Binding<RetroArchSendItem?>) -> some View {
        sheet(item: item) { item in
            RetroArchSendView(skin: item.skin)
        }
    }
}

// MARK: - Sheet content

/// The Send to RetroArch sheet: runs the exporter, shows the report, then hands the folder to the Files picker.
public struct RetroArchSendView: View {
    private let skinName: String
    @StateObject private var model: RetroArchSendModel
    @State private var showingPicker = false
    @State private var shareItem: ShareItem?
    @State private var shareError: String?
    @State private var saved = false
    @Environment(\.dismiss) private var dismiss

    public init(skin: any DeltaSkinProtocol) {
        skinName = skin.name
        _model = StateObject(wrappedValue: RetroArchSendModel {
            let map = try RetroArchInputMap.bundled()
            let export = try RetroArchOverlayExporter.export(skin: skin, rasterize: RetroArchRasterizer.png(for:))
            return RetroArchSendResult(export: export, inputMap: map)
        })
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Send to RetroArch")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .task { await model.start() }
        .onDisappear { model.cleanUp() }
        .sheet(isPresented: $showingPicker) {
            if let folder = model.folder {
                RetroArchFolderExporter(folder: folder) { didSave in
                    showingPicker = false
                    if didSave { saved = true }
                }
                .ignoresSafeArea()
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .exporting:
            VStack(spacing: 12) {
                ProgressView()
                Text("Converting \(skinName)…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Could not convert \(skinName)")
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    model.reset()
                    Task { await model.start() }
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .ready(let result):
            reportList(result.report)
        }
    }

    private func reportList(_ report: RetroArchSendReport) -> some View {
        List {
            Section {
                LabeledContent("Overlay", value: report.folderName)
                LabeledContent("Layouts", value: "\(report.overlayCount)")
                LabeledContent("System", value: report.system)
                if let assumes = report.assumes {
                    Text("Buttons follow \(assumes). On another core, remap its RetroPad.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Converted")
            }

            if !report.warnings.isEmpty {
                Section("Notes") {
                    ForEach(report.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                    }
                }
            }

            if !report.unmapped.isEmpty {
                Section {
                    ForEach(report.unmappedByInput, id: \.input) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.input).font(.body.monospaced())
                            Text(item.reason).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Not converted")
                } footer: {
                    Text("These inputs have no RetroArch equivalent, so they are left out of the overlay.")
                }
            }

            Section {
                Text(RetroArchSendText.destinationHint)
                    .font(.footnote)
                ForEach(Array(RetroArchSendText.menuTaps(folderName: report.folderName).enumerated()), id: \.offset) { index, tap in
                    Label(tap, systemImage: "\(index + 1).circle")
                        .font(.footnote)
                }
            } header: {
                Text("Where it goes")
            }

            Section {
                Button {
                    saved = false
                    showingPicker = true
                } label: {
                    Label(saved ? "Save to Files Again…" : "Save to Files…", systemImage: "folder.badge.plus")
                }
                Button {
                    do {
                        shareError = nil
                        shareItem = ShareItem(url: try model.shareArchive())
                    } catch {
                        shareError = error.localizedDescription
                    }
                } label: {
                    Label("Share Instead…", systemImage: "square.and.arrow.up")
                }
                if saved {
                    Label("Saved. Now turn it on in RetroArch.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.footnote)
                }
                if let shareError {
                    Text(shareError).font(.footnote).foregroundStyle(.red)
                }
            } footer: {
                Text("Share sends a zip you can AirDrop or open elsewhere. Opening a zip in RetroArch itself does not put it in overlays.")
            }
        }
    }
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - Sheet that finds its skin

/// Resolves an installed skin by identifier, then shows ``RetroArchSendView``. For the
/// `provenance://skins/retroarch?skin=<id>` route; a missing id shows how to choose a skin.
public struct RetroArchSendSheet: View {
    private struct Loaded {
        let skin: any DeltaSkinProtocol
    }

    private enum Phase {
        case loading
        case ready(Loaded)
        case unavailable(String)
    }

    private let skinIdentifier: String?
    @State private var phase: Phase = .loading
    @Environment(\.dismiss) private var dismiss

    public init(skinIdentifier: String?) {
        self.skinIdentifier = skinIdentifier
    }

    public var body: some View {
        switch phase {
        case .loading:
            ProgressView()
                .task { await resolve() }
        case .ready(let loaded):
            RetroArchSendView(skin: loaded.skin)
        case .unavailable(let message):
            NavigationStack {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding()
                    .navigationTitle("Send to RetroArch")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            }
        }
    }

    private func resolve() async {
        guard let skinIdentifier else {
            phase = .unavailable("Open a skin in your library and choose Send to RetroArch.")
            return
        }
        let skins = (try? await DeltaSkinManager.shared.availableSkins()) ?? []
        guard let skin = skins.first(where: { $0.identifier == skinIdentifier }) else {
            phase = .unavailable("That skin is not installed. Install it, then choose Send to RetroArch.")
            return
        }
        guard RetroArchSendAvailability.isSupported(skin: skin) else {
            phase = .unavailable("RetroArch has no button mapping for \(skin.name)'s system yet.")
            return
        }
        phase = .ready(Loaded(skin: skin))
    }
}

// MARK: - Entry button

/// The "Send to RetroArch" button the detail view shows for an installed skin.
struct RetroArchSendEntryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up.on.square")
                    .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                Text("SEND TO RETROARCH")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(SkinKitTheme.current.horizontalGradient)
                    .tracking(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.5))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(SkinKitTheme.current.gradient, lineWidth: 1))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("send-to-retroarch")
    }
}

// MARK: - Document picker

/// `UIDocumentPickerViewController(forExporting:asCopy:)` for a folder. The picker copies the folder to the place
/// the user picks and opens at the last place they used. `onFinish(true)` after a save, `onFinish(false)` on cancel.
struct RetroArchFolderExporter: UIViewControllerRepresentable {
    let folder: URL
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [folder], asCopy: true)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onFinish(true)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFinish(false)
        }
    }
}

// MARK: - Rasterizer

enum RetroArchRasterizeError: LocalizedError {
    case unreadableArtwork(String)
    case encodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableArtwork(let name): return "The artwork \(name) could not be drawn."
        case .encodingFailed(let name): return "The picture for \(name) could not be saved as PNG."
        }
    }
}

/// Draws the pictures `RetroArchOverlayExporter` asks for, with the same PDF, SVG and bitmap handling the skin
/// renderer uses. Pixel-exact: one pixel per canvas unit, no screen scale.
enum RetroArchRasterizer {

    static func png(for request: RetroArchImageRequest) throws -> Data {
        let size = CGSize(width: request.pixelWidth, height: request.pixelHeight)
        let ppp = CGFloat(request.pixelsPerPoint)

        // Where the artwork goes: the whole canvas, or a thumbstick cap centered in its hitbox.
        var target = CGRect(origin: .zero, size: size)
        if request.kind == .thumbstick {
            let width = CGFloat(request.innerWidth ?? request.mappingWidth) * ppp
            let height = CGFloat(request.innerHeight ?? request.mappingHeight) * ppp
            target = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
        }

        var drawn = false
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            drawn = draw(request.assetData, ext: request.fileExtension, into: target, context: context.cgContext)
            for rect in request.clearRects {
                context.cgContext.clear(CGRect(x: CGFloat(rect.x) * ppp, y: CGFloat(rect.y) * ppp,
                                               width: CGFloat(rect.width) * ppp, height: CGFloat(rect.height) * ppp))
            }
        }
        guard drawn else { throw RetroArchRasterizeError.unreadableArtwork(request.assetName) }
        guard let data = image.pngData() else { throw RetroArchRasterizeError.encodingFailed(request.file) }
        return data
    }

    private static func draw(_ data: Data, ext: String, into target: CGRect, context: CGContext) -> Bool {
        switch ext {
        case "pdf":
            guard let provider = CGDataProvider(data: data as CFData),
                  let document = CGPDFDocument(provider),
                  let page = document.page(at: 1) else { return false }
            let box = page.getBoxRect(.mediaBox)
            guard box.width > 0, box.height > 0 else { return false }
            // Aspect-fit and center, like UIImage(pdfData:size:).
            let scale = min(target.width / box.width, target.height / box.height)
            let width = box.width * scale
            let height = box.height * scale
            context.saveGState()
            context.translateBy(x: target.midX - width / 2, y: target.midY + height / 2)
            context.scaleBy(x: scale, y: -scale)
            context.translateBy(x: -box.origin.x, y: -box.origin.y)
            context.drawPDFPage(page)
            context.restoreGState()
            return true
        case "svg":
            guard let image = UIImage(svgData: data, size: target.size) else { return false }
            image.draw(in: target)
            return true
        default:
            guard let image = UIImage(data: data) else { return false }
            image.draw(in: target)
            return true
        }
    }
}
#endif
