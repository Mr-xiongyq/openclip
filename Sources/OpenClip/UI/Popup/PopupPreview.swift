// PopupPreview.swift
// OpenClip
//
// Static preview of the popup bar with a fixed action set, decoupled from the live registry so it always
// shows the same canonical actions. Used by the Preferences Appearance tab.
import SwiftUI
import AppKit
import ImageIO
import Core

@MainActor
struct PopupPreview: View {
    /// Canonical preview actions, independent of what the user has enabled in the real popup.
    private static let previewActions: [any Action] = [
        SearchAction(),
        CopyAction(),
        CutAction(),
        PasteAction(),
        AIToolsAction()
    ]

    /// Uses its own hover state so it never leaks into the real popup's shared hover state.
    private static let previewHoverState = PopupHoverState()

    @State private var wallpaperImage: NSImage? = nil

    private var mockContext: ActionContext {
        let app = NSRunningApplication.current
        let context = SelectionContext(
            text: "OpenClip Preview",
            sourceApp: AppIdentity(app),
            cursorPosition: .zero,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: .default
        )
        return ActionContext(selection: context, modifiers: [])
    }

    @Setting(SettingKey.popupScale) private var popupScale
    @Setting(SettingKey.popupAlignment) private var popupAlignment
    @Setting(SettingKey.popupVerticalPosition) private var popupVerticalPosition
    @Setting(SettingKey.popupBarWidth) private var barWidthLevel

    private var isPlacedAbove: Bool {
        let pos = PopupVerticalPosition(rawValue: popupVerticalPosition) ?? .auto
        return pos != .below
    }

    private var selectionAlignment: PopupBarAlignment {
        PopupBarAlignment(rawValue: popupAlignment) ?? .left
    }

    private var scale: CGFloat {
        PopupMetrics.scaleMultiplier(for: popupScale)
    }

    private var popupBarWidth: CGFloat {
        // Standard width for 5 actions + Command search glyph at current scale.
        220 * scale
    }

    private var buttonCenterInset: CGFloat {
        (PopupMetrics.actionButtonWidth * scale) / 2
    }

    /// Horizontal offset aligning the popup with the text selection anchors:
    /// - Left: First action button aligns with the left I-beam (-40pt).
    /// - Center: Popup center aligns with selection center (+10pt).
    /// - Right: Last action button aligns with the right I-beam (+58pt).
    private var popupOffsetX: CGFloat {
        switch selectionAlignment {
        case .left:
            return -40 + (popupBarWidth / 2) - buttonCenterInset

        case .center:
            return 10

        case .right:
            return 58 - (popupBarWidth / 2) + buttonCenterInset
        }
    }

    private var popupOffsetY: CGFloat {
        isPlacedAbove ? -23 : 23
    }

    private var cardOffsetY: CGFloat {
        isPlacedAbove ? 31 : -31
    }

    private var previewModeStore: PopupModeStore {
        let store = PopupModeStore()
        store.subBarAbove = isPlacedAbove
        return store
    }

    /// An authentic macOS text insertion I-beam cursor with top/bottom serifs, rendered in pure white.
    private var iBeamView: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.95))
                .frame(width: 7, height: 1.8)

            Rectangle()
                .fill(Color.white.opacity(0.95))
                .frame(width: 1.8, height: 16)

            Capsule()
                .fill(Color.white.opacity(0.95))
                .frame(width: 7, height: 1.8)
        }
        .frame(width: 8, height: 20)
    }

    /// Decodes a wallpaper thumbnail sized for the blurred 156 pt preview; falls back to a full decode.
    private nonisolated static func downscaledWallpaper(at url: URL) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(contentsOf: url)
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    @ViewBuilder
    private var wallpaperBackground: some View {
        if let image = wallpaperImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .scaleEffect(1.08)
                .blur(radius: 6)
                .overlay(Color.black.opacity(0.28))
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.15, blue: 0.25),
                    Color(red: 0.07, green: 0.09, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(Color.black.opacity(0.25))
        }
    }

    /// Floating text selection with a soft translucent highlight and no harsh shadows.
    private var selectionTextView: some View {
        HStack(spacing: 0) {
            Text("Transform ")

            HStack(spacing: 2.5) {
                if selectionAlignment == .left {
                    iBeamView
                }

                Text("selected text")

                if selectionAlignment != .left {
                    iBeamView
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(Color.accentColor.opacity(0.45))
            )

            Text(" instantly.")
        }
        .font(.system(size: 16, weight: .regular))
        .foregroundStyle(Color.white.opacity(0.90))
    }

    var body: some View {
        ZStack {
            wallpaperBackground

            selectionTextView
                .offset(y: cardOffsetY)

            PopupView(
                actions: Self.previewActions,
                context: mockContext,
                hoverState: Self.previewHoverState,
                isStatic: true,
                modeStore: previewModeStore
            ) { _ in }
            .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
            .offset(x: popupOffsetX, y: popupOffsetY)
        }
        .frame(maxWidth: SettingsLayout.contentMaxWidth - 40)
        .frame(height: 156)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .task {
            // Resolve the AppKit wallpaper lookup on the main actor, then decode a thumbnail off-main.
            // A full-resolution decode is unnecessary for the blurred preview.
            guard let screen = NSScreen.main ?? NSScreen.screens.first,
                  let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return }
            let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                Self.downscaledWallpaper(at: url)
            }.value
            wallpaperImage = image
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: popupAlignment)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: popupVerticalPosition)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: popupScale)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: barWidthLevel)
    }
}
