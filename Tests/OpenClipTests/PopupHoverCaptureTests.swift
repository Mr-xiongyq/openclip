import AppKit
import SwiftUI
import XCTest
@testable import Core
@testable import OpenClip

/// Offscreen captures of production views with simulated hover (no desktop input or actions).
@MainActor
final class PopupHoverCaptureTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TestIsolation.reset()
    }

    func testCapturePopupHoverStates() async throws {
        let store = MemorySettingsStore()
        store.set(SettingKey.popupTheme, value: "classic")
        store.set(SettingKey.popupScale, value: 3)
        store.set(SettingKey.popupFitToWidth, value: true)
        store.set(SettingKey.contextualActionsEnabled, value: true)
        let context = ActionContext(selection: SelectionContext(
            text: "2 + 2", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: .zero, timestamp: Date(), appPolicy: .default))
        let actions: [any Action] = [
            CaptureAction(id: "builtin.calculate", title: "Calculate", icon: .text("4")),
            CaptureAction(id: "builtin.openurl", title: "Open URL", icon: .symbol("link")),
            CaptureAction(id: "capture.copy", title: "Copy", icon: .text("Copy")),
            CaptureAction(id: "capture.star", title: "Star", icon: .symbol("star")),
            CaptureAction(id: "capture.paste", title: "Paste", icon: .text("Paste"))
        ]
        for scheme in [ColorScheme.light, .dark] {
            let appearance = scheme == .dark ? "dark" : "light"
            store.set(SettingKey.popupThemeColor, value: appearance)
            for position in ["left", "right"] {
                store.set(SettingKey.contextualPillPosition, value: position)
                let hover = PopupHoverState()
                hover.usesGlobalMouseMonitoring = true
                var frames: [PopupHoverTarget: CGRect] = [:]
                var hoveredID: String?
                let view = PopupView(settingsStore: store, actions: actions, context: context,
                    hoverState: hover, onResult: { _ in },
                    onHoveredActionChanged: { hoveredID = $0?.id })
                    .onPreferenceChange(PopupHoverFramePreferenceKey.self) { value in
                        MainActor.assumeIsolated { frames = value }
                    }
                let host = makeHost(view, scheme: scheme)
                await settle(host)
                XCTAssertEqual(frames.keys.filter { if case .action = $0 { return true }; return false }.count, actions.count)
                let rest = try capture(host, name: "\(appearance)-context-\(position)-rest")
                let ordered = position == "left" ? actions : Array(actions.dropFirst(2)) + Array(actions.prefix(2))
                for index in ordered.indices {
                    let frame = try XCTUnwrap(frames[.action(index)])
                    hover.location = CGPoint(x: frame.midX, y: frame.midY)
                    await settle(host)
                    XCTAssertEqual(hoveredID, ordered[index].id, "Simulated cursor must hover the intended production button")
                    let highlighted = try capture(host, name: "\(appearance)-context-\(position)-hover-\(index)")
                    XCTAssertNotEqual(highlighted, rest, "Hover must visibly change the capture")
                }
            }
            var subBarRest: Data?
            for index in -1..<3 {
                let view = GroupSubActionBarView(settingsStore: store,
                    subActions: Array(actions.suffix(3)), currentPage: .constant(0),
                    hoverState: SubBarHoverState(), onResult: { _ in }, onRunAI: { _ in },
                    onRunLoadingAction: { _, _ in }, onWillPerformAction: { _, _ in true },
                    onActionPerformed: { _ in }, onClickIntent: { .primary }, context: context,
                    presenter: ActionCustomizationManager.shared, effectiveTheme: appearance,
                    hoveredTarget: index < 0 ? nil : .subAction(index), scale: 1)
                    .popupCardChrome(effectiveTheme: appearance, colorScheme: scheme)
                let host = makeHost(view, scheme: scheme)
                await settle(host)
                let image = try capture(host, name: "\(appearance)-subbar-\(index < 0 ? "rest" : "hover-\(index)")")
                if index < 0 { subBarRest = image }
                else { XCTAssertNotEqual(image, try XCTUnwrap(subBarRest)) }
            }
        }
    }

    func testCaptureOCRConfirmationWithGroupBar() async throws {
        let store = MemorySettingsStore()
        store.set(SettingKey.popupTheme, value: "classic")
        store.set(SettingKey.popupScale, value: 3)
        store.set(SettingKey.popupFitToWidth, value: true)
        let actions: [any Action] = [
            CaptureAction(id: "capture.copy", title: "Copy", icon: .text("Copy")),
            GroupAction(id: "capture.group", title: "Tools", icon: .symbol("folder"),
                        chrome: ActionChrome(popupBehavior: .showSubActions)),
            CaptureAction(id: "capture.search", title: "Search", icon: .symbol("magnifyingglass"))
        ]
        let children: [any Action] = [
            CaptureAction(id: "capture.group.translate", title: "Translate", icon: .text("Translate")),
            CaptureAction(id: "capture.group.search", title: "Search", icon: .text("Search"))
        ]
        let context = ActionContext(selection: SelectionContext(text: "private OCR input", source: .ocr))
        for scheme in [ColorScheme.light, .dark] {
            let appearance = scheme == .dark ? "dark" : "light"
            store.set(SettingKey.popupThemeColor, value: appearance)
            for copied in [false, true] {
                for groupPosition in ["closed", "below", "above"] {
                    let mode = PopupModeStore()
                    let feedback = StatusFeedback(message: copied ? "Text copied" : "Text captured", style: .success,
                                                  symbolName: "checkmark.circle.fill")
                    mode.activeSubGroupID = groupPosition == "closed" ? nil : "capture.group"
                    mode.isSubBarActive = groupPosition != "closed"
                    let main = PopupView(settingsStore: store, actions: actions + children, context: context,
                        hoverState: PopupHoverState(), modeStore: mode, onResult: { _ in })
                    let sub = GroupSubActionBarView(settingsStore: store, subActions: children,
                        currentPage: .constant(0), hoverState: SubBarHoverState(), onResult: { _ in },
                        onRunAI: { _ in }, onRunLoadingAction: { _, _ in },
                        onWillPerformAction: { _, _ in true }, onActionPerformed: { _ in },
                        onClickIntent: { .primary }, context: context, presenter: ActionCustomizationManager.shared,
                        effectiveTheme: appearance, hoveredTarget: .subAction(0), scale: 1)
                        .popupCardChrome(effectiveTheme: appearance, colorScheme: scheme)
                    // Composite fixture of the independent windows, at their 6 pt content gaps.
                    let arrangement = VStack(alignment: .center, spacing: PopupMetrics.captureStatusGap) {
                        ToastView(feedback: feedback, settingsStore: store)
                        if groupPosition == "above" { sub }
                        main.padding(-PopupMetrics.popupShadowInset)
                        if groupPosition == "below" { sub }
                    }
                    let host = makeHost(arrangement, scheme: scheme, height: 180)
                    await settle(host)
                    try capture(host, name: "ocr-\(appearance)-\(copied ? "copied" : "captured")-group-\(groupPosition)")
                }
            }
        }
    }

    private func makeHost<V: View>(_ view: V, scheme: ColorScheme, height: CGFloat = 100) -> NSHostingView<some View> {
        let host = NSHostingView(rootView: view.fixedSize().padding(20)
            .frame(width: 640, height: height, alignment: .leading)
            .background(Color(red: 0.25, green: 0.28, blue: 0.33))
            .environment(\.colorScheme, scheme))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: height)
        return host
    }

    private func settle<V: View>(_ host: NSHostingView<V>) async {
        host.layoutSubtreeIfNeeded()
        // Let preference delivery and the hover animation finish before capturing.
        try? await Task.sleep(for: .milliseconds(350))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
    }

    @discardableResult
    private func capture<V: View>(_ host: NSHostingView<V>, name: String) throws -> Data {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: "/tmp/openclip-hover-captures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(png.count, 1000, "Capture must contain rendered content")
        return png
    }
}

private struct CaptureAction: Action {
    let id: String
    let title: String
    let icon: ActionIcon
    var chrome: ActionChrome { ActionChrome(source: .builtin) }
    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}
