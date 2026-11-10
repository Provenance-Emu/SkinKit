#if canImport(UIKit)
import SkinKitCore
import SkinKitManager
import SkinCatalogKit
//
//  SkinPreviewCell.swift
//  PVUI
//
//  Created by Joseph Mattiello on 3/30/25.
//

import SwiftUI

/// Preview cell for a skin with rubber-like design.
///
/// Loads the skin image asynchronously on a background thread and renders a
/// lightweight static thumbnail rather than a full ``DeltaSkinView``.
struct SkinPreviewCell: View {
    let skin: any DeltaSkinRenderable
    let manager: DeltaSkinManager
    var orientation: DeltaSkinOrientation = .portrait

    @State private var showingDeleteAlert = false
    @State private var deleteError: Error?
    @State private var showingErrorAlert = false
    @State private var thumbnailImage: UIImage?
    @State private var isLoadingThumbnail = true
    @State private var thumbnailFailed = false
    /// The render in flight. A newer load (a theme change) cancels it so a late, superseded render
    /// cannot overwrite the thumbnail or the shared cache with stale artwork.
    @State private var thumbnailTask: Task<Void, Never>?
    #if !os(tvOS)
    @State private var showingShareSheet = false
    @State private var showingEditSheet = false
    #endif
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Width over height of the slot the artwork is fitted in.
    private static let thumbnailSlotAspect: CGFloat = 1

    /// Resolve the best supported traits for preview, trying progressively
    /// wider fallbacks so skins that only support one device/orientation
    /// still render a thumbnail.
    private var previewTraits: DeltaSkinTraits {
        let device: DeltaSkinDevice = horizontalSizeClass == .regular ? .ipad : .iphone
        let altDevice: DeltaSkinDevice = device == .ipad ? .iphone : .ipad
        let displayTypes: [DeltaSkinDisplayType] = [.standard, .edgeToEdge]
        let oppositeOrientation: DeltaSkinOrientation = orientation == .portrait ? .landscape : .portrait

        // 1. Current device, requested orientation
        for displayType in displayTypes {
            let traits = DeltaSkinTraits(device: device, displayType: displayType, orientation: orientation)
            if skin.supports(traits) { return traits }
        }

        // 2. Current device, opposite orientation
        for displayType in displayTypes {
            let traits = DeltaSkinTraits(device: device, displayType: displayType, orientation: oppositeOrientation)
            if skin.supports(traits) { return traits }
        }

        // 3. Alternate device, requested orientation
        for displayType in displayTypes {
            let traits = DeltaSkinTraits(device: altDevice, displayType: displayType, orientation: orientation)
            if skin.supports(traits) { return traits }
        }

        // 4. Alternate device, opposite orientation
        for displayType in displayTypes {
            let traits = DeltaSkinTraits(device: altDevice, displayType: displayType, orientation: oppositeOrientation)
            if skin.supports(traits) { return traits }
        }

        // Final fallback (should rarely be reached)
        return DeltaSkinTraits(device: device, displayType: .standard, orientation: orientation)
    }

    var body: some View {
        ZStack {
            // Preview content with disabled interaction
            content
                .allowsHitTesting(false)

            // Transparent overlay to capture context menu
            Color.clear
                .contentShape(Rectangle())
        }
        .contextMenu {
            #if !os(tvOS)
            Button {
                showingShareSheet = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Button {
                showingEditSheet = true
            } label: {
                Label("Edit Button Positions…", systemImage: "pencil.and.ruler")
            }
            #endif

            if manager.isDeletable(skin) {
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .skinKitAlert("Delete Skin?",
                    message: "Are you sure you want to delete '\(skin.name)'? This cannot be undone.",
                    isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await manager.deleteSkin(skin.identifier)
                    } catch {
                        deleteError = error
                        showingErrorAlert = true
                    }
                }
            }
        }
        .skinKitAlert("Delete Error",
                    message: deleteError?.localizedDescription ?? "",
                    isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { }
        }
        #if !os(tvOS)
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: [skin.fileURL])
        }
        .sheet(isPresented: $showingEditSheet) {
            DeltaSkinFullscreenPreview(
                skin: skin,
                traits: previewTraits,
                filters: [],
                initialEditMode: true
            )
        }
        #endif
        .onAppear {
            loadThumbnail()
        }
        .onThemeSelectionChange(of: skin.identifier) {
            loadThumbnail()
        }
    }

    // MARK: - Thumbnail preview

    @ViewBuilder
    private var thumbnailPreview: some View {
        if isLoadingThumbnail {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if let thumbnailImage {
            Image(uiImage: thumbnailImage)
                .resizable()
                .scaledToFit()
        } else {
            // Fallback for skins where image loading failed
            VStack(spacing: 4) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text(skin.name)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.15))
        }
    }

    private func loadThumbnail() {
        thumbnailTask?.cancel()
        thumbnailTask = nil

        let traits = previewTraits
        let cacheKey = SkinPreviewThumbnailCache.key(for: skin.identifier, traits: traits)

        // Fast path: use SkinSelectionPreviewCell's shared cache. Whatever was stored is the best
        // render there is; re-checking it for visible content only re-rendered thin artwork forever.
        if let cached = SkinPreviewThumbnailCache.shared.thumbnail(forKey: cacheKey) {
            thumbnailImage = cached
            isLoadingThumbnail = false
            thumbnailFailed = false
            return
        }

        thumbnailFailed = false
        isLoadingThumbnail = true
        let skin = self.skin
        thumbnailTask = Task.detached(priority: .utility) {
            do {
                let image = try await SkinPreviewThumbnailCache.preview(of: skin, traits: traits)
                // Superseded while rendering: drop the result before the cache write and the UI update.
                try Task.checkCancellation()
                SkinPreviewThumbnailCache.shared.store(image, forKey: cacheKey)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.thumbnailImage = image
                    self.isLoadingThumbnail = false
                }
            } catch is CancellationError {
                // A newer load owns the cell now.
            } catch {
                ELOG("skins: SkinPreviewCell failed to load thumbnail for '\(skin.name)' traits=\(traits.description): \(error)")
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.thumbnailFailed = true
                    self.isLoadingThumbnail = false
                }
            }
        }
    }

    /// Every cell is the same size: the artwork is fitted inside a fixed slot, so portrait and
    /// landscape skins line up in one grid instead of making rows of mismatched height.
    private var content: some View {
        let theme = SkinKitTheme.current
        return VStack(alignment: .leading, spacing: 8) {
            Color.black
                .aspectRatio(Self.thumbnailSlotAspect, contentMode: .fit)
                .overlay { thumbnailPreview.padding(6) }
                .clipShape(RoundedRectangle(cornerRadius: theme.radiusSM))

            VStack(alignment: .leading, spacing: 4) {
                Text(skin.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.85)

                DeviceIndicators(skin: skin)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(theme.chromeInset - 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .skinKitCard()
    }
}

/// Process-wide thumbnail cache shared between ``SkinPreviewCell`` and
/// ``SkinSelectionPreviewCell`` so the same skin image is never decoded twice.
///
/// Backed by ``ImageMemoryCache``: the previous plain `Dictionary` was capped
/// at 100 entries by *count* with no byte budget, trimmed arbitrary entries
/// (`Dictionary.keys` is unordered, so `prefix(20)` was not LRU), and was never
/// purged on memory pressure — despite holding full-size skin renders.
final class SkinPreviewThumbnailCache: @unchecked Sendable {
    static let shared = SkinPreviewThumbnailCache()

    private let cache = SkinImageMemoryCache(
        name: "SkinPreviewThumbnailCache",
        totalCostLimit: SkinImageCacheBudget.skinPreviews,
        countLimit: SkinImageCacheBudget.defaultCountLimit
    )

    func thumbnail(forKey key: String) -> UIImage? {
        cache.image(forKey: key)
    }

    /// Key of a skin's preview for `traits`. It includes the skin's selected theme, so picking a theme
    /// shows that theme's artwork instead of the preview cached for the previous choice.
    static func key(for skinIdentifier: String, traits: DeltaSkinTraits) -> String {
        // "theme:<id>" vs "none": a theme whose id is "default" must not share a key with no theme.
        let theme = DeltaSkinThemeSelection.selectedThemeId(for: skinIdentifier).map { "theme:\($0)" } ?? "none"
        return "\(skinIdentifier)-\(traits.device.rawValue)-\(traits.displayType.rawValue)-\(traits.orientation.rawValue)-\(theme)"
    }

    func store(_ image: UIImage, forKey key: String) {
        cache.setImage(image, forKey: key)
    }

    /// Longest side of a stored preview, in points.
    static let maxPointSize: CGFloat = 256

    /// The image both skin grids show: the skin's small `thumbnail` render, which the skin also keeps
    /// on disk. Never the full-size image: at 3x one is ~14 MB, so the library grid kept evicting
    /// every other preview from this cache's budget and re-rendering skins on each appearance.
    /// A full render stands in only when the thumbnail fails or samples blank, scaled down first.
    static func preview(of skin: any DeltaSkinRenderable, traits: DeltaSkinTraits) async throws -> UIImage {
        if let thumbnail = try? await skin.thumbnail(for: traits, maxDimension: maxPointSize),
           thumbnail.hasVisibleContent {
            return thumbnail
        }
        return scaledDown(try await skin.image(for: traits))
    }

    private static func scaledDown(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxPointSize else { return image }
        let factor = maxPointSize / longest
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
#endif
