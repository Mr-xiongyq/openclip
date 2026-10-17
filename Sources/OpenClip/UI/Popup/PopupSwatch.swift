// PopupSwatch.swift
// OpenClip
//
// Live preview for the Appearance settings: the real `PopupView` over a soft gradient, reading the
// same theme, color mode and scale as the live popup.

import SwiftUI
import AppKit
import ImageIO
import Core

@MainActor
struct PopupSwatch: View {
    /// Fixed 13-action set, independent of the user's bar, so pagination is exercised.
    static let actions: [any Action] = [
        CalculateAction(),
        CustomAction(id: "swatch.search", title: "Search", iconName: "magnifyingglass", type: .textSnippet(template: "")),
        CopyAction(),
        CutAction(),
        PasteAction(),
        CustomAction(id: "swatch.define", title: "Define", iconName: "book.closed", type: .textSnippet(template: "")),
        CustomAction(id: "swatch.calendar", title: "Add Event", iconName: "calendar.badge.plus", type: .textSnippet(template: "")),
        CustomAction(id: "swatch.uppercase", title: "Uppercase", iconName: "textformat.size.larger", type: .textSnippet(template: "")),
        CustomAction(id: "swatch.lowercase", title: "Lowercase", iconName: "textformat.size.smaller", type: .textSnippet(template: "")),
        CustomAction(id: "swatch.share", title: "Share", iconName: "square.and.arrow.up", type: .textSnippet(template: "")),
        CustomAction(id: "swatch.translate", title: "Translate", iconName: "character.book.closed", type: .textSnippet(template: "")),
        CustomAction(id: "swatch.summarize", title: "Summarize", iconName: "doc.text.magnifyingglass", type: .textSnippet(template: "")),
        CustomAction(id: "swatch.notes", title: "Add to Notes", iconName: "note.text.badge.plus", type: .textSnippet(template: ""))
    ]

    /// Resting hover state; the preview never observes it, so it can't leak into the real popup.
    private static let hoverState = PopupHoverState()

    /// Shared wallpaper thumbnail, decoded once.
    @MainActor private static let wallpaper: NSImage? = loadWallpaper()

    var height: CGFloat = 116
    /// Extra headroom above the bar so the drop shadow doesn't make the preview look top-heavy.
    var topInset: CGFloat = 12

    @Setting(SettingKey.popupTheme) private var storedTheme
    @Setting(SettingKey.popupThemeColor) private var storedColor
    @Environment(\.colorScheme) private var systemScheme

    private var category: PopupThemeModel.Category {
        PopupThemeModel.category(fromStored: storedTheme)
    }

    private var effectiveTheme: String {
        if category == .glass { return "glass" }
        return PopupThemeModel.classicToken(appearance: storedColor, systemIsDark: systemScheme == .dark)
    }

    private var effectiveScheme: ColorScheme {
        PopupThemeModel.effectiveScheme(appearance: storedColor, systemIsDark: systemScheme == .dark)
    }

    @StateObject private var modeStore: PopupModeStore = {
        let store = PopupModeStore()
        store.subBarAbove = true
        return store
    }()

    var body: some View {
        let context = ActionContext(selection: mockContext.selection, modifiers: [])
        // The stage owns its size; a wider popup must not enlarge the settings pane.
        Color.clear
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background {
            GeometryReader { geometry in
                backdrop
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
        }
        .overlay {
            PopupPreviewLayout {
                PopupView(
                    actions: Self.actions,
                    context: context,
                    hoverState: Self.hoverState,
                    presenter: PopupPreviewPresenter(),
                    isStatic: true,
                    modeStore: modeStore
                ) { _ in }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.top, topInset)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PopupMetrics.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PopupMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(SettingsDesignTokens.sectionCardBorder, lineWidth: 0.5)
        )
        .environment(\.colorScheme, effectiveScheme)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.15), value: effectiveTheme)
        .animation(.easeInOut(duration: 0.15), value: effectiveScheme)
    }

    /// Blurred wallpaper for the glass to blur; tint follows color mode. Gradient fallback if unreadable.
    @ViewBuilder
    private var backdrop: some View {
        if let image = Self.wallpaper {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 6)
                .overlay(Color.black.opacity(effectiveScheme == .dark ? 0.32 : 0.12))
        } else {
            let stops: [Color] = effectiveScheme == .dark
                ? [
                    Color(red: 0.20, green: 0.17, blue: 0.34),
                    Color(red: 0.13, green: 0.15, blue: 0.28),
                    Color(red: 0.09, green: 0.10, blue: 0.20)
                ]
                : [
                    Color(red: 0.85, green: 0.82, blue: 0.95),
                    Color(red: 0.78, green: 0.82, blue: 0.94),
                    Color(red: 0.72, green: 0.80, blue: 0.92)
                ]
            LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// Decodes the current wallpaper to a thumbnail; nil when it can't be resolved.
    private static func loadWallpaper() -> NSImage? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 800
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(contentsOf: url)
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private var mockContext: ActionContext {
        let context = SelectionContext(
            text: "OpenClip",
            sourceApp: AppIdentity(NSRunningApplication.current),
            cursorPosition: .zero,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: context, modifiers: [])
    }
}

/// Preview glyphs are fixed samples rather than the user's saved action customizations.
@MainActor
private struct PopupPreviewPresenter: ActionPresenting {
    func displayTitle(for action: any Action) -> String { action.title }
    func popupIcon(for action: any Action) -> ActionIcon { action.icon }
    func tableIcon(for action: any Action) -> ActionIcon { action.icon }
}

/// Centers the popup when it fits; otherwise keeps a leading inset. Never changes the proposed size.
private struct PopupPreviewLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let popup = subviews.first else { return }
        let size = popup.sizeThatFits(.unspecified)
        popup.place(
            at: CGPoint(
                x: bounds.minX + max(16, (bounds.width - size.width) / 2),
                y: bounds.midY - size.height / 2
            ),
            anchor: .topLeading,
            proposal: ProposedViewSize(size)
        )
    }
}
