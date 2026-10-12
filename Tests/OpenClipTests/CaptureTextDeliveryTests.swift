import AppKit
import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class CaptureTextDeliveryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TestIsolation.reset()
    }

    private func fixture() -> (CaptureTextController, MemorySettingsStore, NSPasteboard) {
        let store = MemorySettingsStore()
        let board = NSPasteboard(name: .init("com.openclip.tests.capture.\(UUID().uuidString)"))
        board.setString("Original clipboard", forType: .string)
        let controller = CaptureTextController(popupController: PopupWindowController(settingsStore: store),
            settingsStore: store, resultHandler: DefaultActionResultHandler(settingsStore: store, pasteboard: board))
        return (controller, store, board)
    }

    func testCaptureConfirmationUsesSeparateWindowNearCursor() {
        let controller = PopupWindowController(settingsStore: MemorySettingsStore())
        defer { controller.hide() }
        let feedback = StatusFeedback(message: "Text captured", style: .success)
        controller.show(for: SelectionContext(text: "private recognized text", cursorPosition: CGPoint(x: 400, y: 300), source: .ocr),
                        pasteAvailable: false, captureFeedback: feedback)
        XCTAssertEqual(controller.modeStore.mode, .actions)
        XCTAssertEqual(controller.toastController.currentFeedback, feedback)
        XCTAssertEqual(controller.toastController.currentPlacement, .nearCursor(CGPoint(x: 400, y: 300)))
        XCTAssertTrue(controller.toastController.isShowing)
        let panel = controller.panel!
        let toast = controller.toastController.panelFrame.insetBy(dx: PopupMetrics.toastShadowInset, dy: PopupMetrics.toastShadowInset)
        XCTAssertEqual(toast.midX, 400, accuracy: 0.5)
        XCTAssertFalse(toast.intersects(panel.frame.insetBy(dx: PopupMetrics.popupShadowInset, dy: PopupMetrics.popupShadowInset)))
        controller.hide()
        XCTAssertFalse(controller.toastController.isShowing)
        controller.show(for: SelectionContext(text: "new selection"), captureFeedback: feedback)
        XCTAssertFalse(controller.toastController.isShowing, "Regular selections must not inherit capture feedback")
    }

    func testCaptureToastAutomaticallyDismissesWithoutResizingOrClosingPopup() async throws {
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = PopupWindowController(toastController: toast, settingsStore: MemorySettingsStore())
        defer { controller.hide() }
        controller.show(for: SelectionContext(text: "recognized", cursorPosition: CGPoint(x: 400, y: 300), source: .ocr),
                        captureFeedback: StatusFeedback(message: "Text copied", style: .success))
        try await Task.sleep(for: .milliseconds(30))
        let original = controller.panel!.frame
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(toast.isShowing)
        XCTAssertEqual(controller.panel!.frame, original, "A separate toast must not change the action panel's geometry")
        XCTAssertTrue(controller.isVisible)
    }

    func testOldToastDismissalCannotClearNewCaptureToast() async throws {
        let toast = ToastPanelController(autoDismissNanoseconds: 100_000_000)
        let controller = PopupWindowController(toastController: toast, settingsStore: MemorySettingsStore())
        defer { controller.hide() }
        let context = SelectionContext(text: "recognized", source: .ocr)
        controller.show(for: context, captureFeedback: StatusFeedback(message: "Text copied", style: .success))
        try await Task.sleep(for: .milliseconds(60))
        let newFeedback = StatusFeedback(message: "Text captured", style: .success)
        controller.show(for: context, captureFeedback: newFeedback)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(toast.currentFeedback, newFeedback)
        XCTAssertTrue(toast.isShowing)
    }

    func testCaptureToastClearsGroupBarWithoutRestartingTimer() {
        let toast = ToastPanelController(autoDismissNanoseconds: 1_000_000_000)
        defer { toast.hide() }
        let shadow = PopupMetrics.popupShadowInset
        let main = CGRect(x: 200, y: 250, width: 200, height: 33.5).insetBy(dx: -shadow, dy: -shadow)
        toast.show(StatusFeedback(message: "Text copied", style: .success), anchorFrame: main, placement: .above)
        let group = CGRect(x: 210, y: 290, width: 200, height: 33.5).insetBy(dx: -shadow, dy: -shadow)
        toast.reposition(anchorFrame: main, avoidanceRects: [group])
        let content = toast.panelFrame.insetBy(dx: PopupMetrics.toastShadowInset, dy: PopupMetrics.toastShadowInset)
        XCTAssertGreaterThanOrEqual(content.minY, group.maxY - shadow + PopupMetrics.captureStatusGap - 0.5)
        XCTAssertEqual(content.midX, main.midX, accuracy: 0.5)
        XCTAssertTrue(toast.hasPendingDismissal)
    }

    func testCursorToastPrefersAboveAndAvoidsPopupAndGroup() {
        let visible = CGRect(x: 0, y: 0, width: 800, height: 600)
        let cursor = CGPoint(x: 400, y: 300)
        let size = CGSize(width: 150, height: 24)
        let shadow = PopupMetrics.popupShadowInset
        let below = CGRect(x: 300, y: 240, width: 200, height: 33.5).insetBy(dx: -shadow, dy: -shadow)
        let aboveOrigin = ToastPanelController.contentOrigin(size: size, anchor: below, visible: visible,
                                                            placement: .nearCursor(cursor))
        XCTAssertEqual(aboveOrigin.x + size.width / 2, cursor.x)
        XCTAssertGreaterThan(aboveOrigin.y, cursor.y)

        let above = CGRect(x: 300, y: 306, width: 200, height: 33.5).insetBy(dx: -shadow, dy: -shadow)
        let clearOrigin = ToastPanelController.contentOrigin(size: size, anchor: above, visible: visible,
                                                            placement: .nearCursor(cursor), avoidanceRects: [below])
        let frame = CGRect(origin: clearOrigin, size: size)
        XCTAssertFalse(frame.intersects(above.insetBy(dx: shadow, dy: shadow)))
        XCTAssertFalse(frame.intersects(below.insetBy(dx: shadow, dy: shadow)))
        XCTAssertFalse(frame.contains(cursor))
        XCTAssertTrue(visible.contains(frame))
    }

    func testCaptureToastAtTopEdgeStillClearsPopup() {
        let controller = PopupWindowController(settingsStore: MemorySettingsStore())
        defer { controller.hide() }
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        controller.show(for: SelectionContext(text: "recognized", cursorPosition: CGPoint(x: visible.midX, y: visible.maxY - 1), source: .ocr),
                        captureFeedback: StatusFeedback(message: "Text captured", style: .success))
        let content = controller.toastController.panelFrame.insetBy(dx: PopupMetrics.toastShadowInset, dy: PopupMetrics.toastShadowInset)
        XCTAssertFalse(content.intersects(controller.panel!.frame.insetBy(dx: PopupMetrics.popupShadowInset, dy: PopupMetrics.popupShadowInset)))
        XCTAssertLessThanOrEqual(content.maxY, visible.maxY + 0.5)
    }

    func testDefaultCopiesBeforeOpeningPopupAndPreservesRecognizedWhitespace() async throws {
        let (controller, store, board) = fixture()
        defer { board.releaseGlobally() }
        XCTAssertTrue(store.get(.captureTextAutoCopy))
        var shown = false
        var feedback: StatusFeedback?
        try await controller.deliverRecognizedText("First line\nSecond line\n", isCurrent: { true }) { status in
            feedback = status
            XCTAssertEqual(board.string(forType: .string), "First line\nSecond line\n")
            shown = true
        }
        XCTAssertTrue(shown)
        XCTAssertEqual(feedback?.message, "Text copied")
        XCTAssertEqual(feedback?.style, .success)
    }

    func testDisabledSettingKeepsClipboardAndOpensPopup() async throws {
        let (controller, store, board) = fixture()
        defer { board.releaseGlobally() }
        store.set(.captureTextAutoCopy, value: false)
        var shown = false
        var feedback: StatusFeedback?
        try await controller.deliverRecognizedText("Recognized", isCurrent: { true }) { status in
            feedback = status
            shown = true
        }
        XCTAssertTrue(shown)
        XCTAssertEqual(feedback?.message, "Text captured")
        XCTAssertEqual(feedback?.style, .success)
        XCTAssertEqual(board.string(forType: .string), "Original clipboard")
    }

    func testEmptyAndStaleResultsNeitherCopyNorOpenPopup() async throws {
        let (controller, _, board) = fixture()
        defer { board.releaseGlobally() }
        try await controller.deliverRecognizedText(" \n\t", isCurrent: { true }) { _ in XCTFail("Empty result opened popup") }
        try await controller.deliverRecognizedText("Recognized", isCurrent: { false }) { _ in XCTFail("Stale result opened popup") }
        XCTAssertEqual(board.string(forType: .string), "Original clipboard")
    }

    func testSessionInvalidatedBeforeClipboardWriteDoesNotCopy() async throws {
        let (controller, _, board) = fixture()
        defer { board.releaseGlobally() }
        var checks = 0
        try await controller.deliverRecognizedText("Recognized", isCurrent: {
            checks += 1
            return checks == 1
        }) { _ in XCTFail("Superseded result opened popup") }
        XCTAssertEqual(checks, 2, "Validity must be checked again after acquiring the clipboard lease")
        XCTAssertEqual(board.string(forType: .string), "Original clipboard")
    }

    func testCancelledRecognitionDoesNotCopyOrOpenPopup() async throws {
        let (controller, _, board) = fixture()
        defer { board.releaseGlobally() }
        let task = Task { @MainActor in
            try await controller.deliverRecognizedText("Recognized", isCurrent: { true }) { _ in XCTFail("Cancelled result opened popup") }
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: clipboard remains untouched.
        }
        XCTAssertEqual(board.string(forType: .string), "Original clipboard")
    }
}
