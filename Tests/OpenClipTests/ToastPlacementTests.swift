import AppKit
import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class ToastPlacementTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TestIsolation.reset()
    }

    private var cursor: CGPoint {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        return CGPoint(x: visible.midX, y: visible.midY)
    }

    func testToastIsEligibleForOtherApplicationsFullscreenSpaces() {
        let panel = ToastPanel()
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllApplications))
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.hidesOnDeactivate)
    }

    func testOffSpaceToastRecoversOnceWithoutLosingFeedbackOrTimer() throws {
        let old = ToastSpaceTestPanel()
        let point = cursor
        let toast = ToastPanelController(panel: old, cursorLocation: { point })
        defer { toast.hide() }
        let feedback = StatusFeedback(message: "Copied", style: .success)
        toast.show(feedback)
        let id = try XCTUnwrap(toast.presentationID)
        let content = old.contentView
        let frame = old.frame
        let replacement = ToastSpaceTestPanel()
        XCTAssertTrue(toast.recoverToastSpaceIfNeeded(for: id, makePanel: { replacement }))
        XCTAssertEqual(old.ordering, ["out"])
        XCTAssertEqual(replacement.ordering, ["front"])
        XCTAssertNil(old.contentView)
        XCTAssertTrue(replacement.contentView === content)
        XCTAssertEqual(replacement.frame, frame)
        XCTAssertEqual(toast.currentFeedback, feedback)
        XCTAssertEqual(toast.currentPlacement, .nearCursor(point))
        XCTAssertTrue(toast.hasPendingDismissal)
        XCTAssertFalse(replacement.canBecomeKey)
        XCTAssertFalse(toast.recoverToastSpaceIfNeeded(for: id, makePanel: { ToastSpaceTestPanel() }))
    }

    func testToastRecoveryRejectsVisibleActiveStaleAndDismissedPresentations() throws {
        let panel = ToastSpaceTestPanel()
        let toast = ToastPanelController(panel: panel)
        defer { toast.hide() }
        toast.show(StatusFeedback(message: "First", style: .success))
        let oldID = try XCTUnwrap(toast.presentationID)
        panel.activeSpace = true
        XCTAssertFalse(toast.recoverToastSpaceIfNeeded(for: oldID))
        panel.activeSpace = false
        toast.show(StatusFeedback(message: "Second", style: .success))
        XCTAssertFalse(toast.recoverToastSpaceIfNeeded(for: oldID))
        let currentID = try XCTUnwrap(toast.presentationID)
        toast.hide()
        XCTAssertFalse(toast.recoverToastSpaceIfNeeded(for: currentID))
    }

    func testStandardToastAppearsNearCursorWithoutPopup() {
        let point = cursor
        let toast = ToastPanelController(cursorLocation: { point })
        defer { toast.hide() }
        toast.show(StatusFeedback(message: "Copied", style: .success))
        XCTAssertEqual(toast.currentPlacement, .nearCursor(point))
        XCTAssertNil(toast.lastAnchorFrame)
        let content = toast.panelFrame.insetBy(dx: PopupMetrics.toastShadowInset, dy: PopupMetrics.toastShadowInset)
        XCTAssertEqual(content.midX, point.x, accuracy: 0.5)
        XCTAssertGreaterThan(content.minY, point.y)
        XCTAssertFalse(content.contains(point))
    }

    func testExplicitToastPointIsRespected() {
        let point = cursor
        let toast = ToastPanelController(cursorLocation: { CGPoint(x: point.x + 100, y: point.y) })
        let controller = PopupWindowController(toastController: toast, settingsStore: MemorySettingsStore())
        defer { controller.hide(); toast.hide() }
        controller.showToast(StatusFeedback(message: "Captured", style: .success), at: point)
        XCTAssertEqual(toast.currentPlacement, .nearCursor(point))
    }

    func testFreshToastUsesNewCursorPosition() {
        var point = cursor
        let toast = ToastPanelController(cursorLocation: { point })
        defer { toast.hide() }
        toast.show(StatusFeedback(message: "First", style: .info))
        let firstPosition = toast.currentPlacement
        point.x += 100
        toast.show(StatusFeedback(message: "Second", style: .info))
        XCTAssertEqual(toast.currentPlacement, .nearCursor(point))
        XCTAssertNotEqual(toast.currentPlacement, firstPosition)
    }

    func testLoadingCompletionKeepsInitialCursorPosition() {
        var point = cursor
        let toast = ToastPanelController(cursorLocation: { point })
        defer { toast.hide() }
        toast.showLoading(message: "Generating…")
        let initial = toast.currentPlacement
        point.x += 100
        toast.swapTo(StatusFeedback(message: "Done", style: .success))
        XCTAssertEqual(toast.currentPlacement, initial)
        XCTAssertFalse(toast.isLoading)
        XCTAssertTrue(toast.hasPendingDismissal)
    }

    func testDirectLoadingErrorKeepsInitialCursorPosition() {
        var point = cursor
        let toast = ToastPanelController(cursorLocation: { point })
        defer { toast.hide() }
        toast.showLoading(message: "Opening…")
        let initial = toast.currentPlacement
        point.x += 100
        toast.show(StatusFeedback(message: "Could not open", style: .error))
        XCTAssertEqual(toast.currentPlacement, initial)
        XCTAssertFalse(toast.isLoading)
    }

    func testActionResultToastSurvivesClosingCapturePopup() {
        let point = cursor
        let toast = ToastPanelController(cursorLocation: { point })
        let controller = PopupWindowController(toastController: toast, settingsStore: MemorySettingsStore())
        defer { controller.hide(); toast.hide() }
        controller.show(for: SelectionContext(text: "recognized", cursorPosition: point, source: .ocr),
                        captureFeedback: StatusFeedback(message: "Text captured", style: .success))
        let result = StatusFeedback(message: "Action complete", style: .success)
        toast.show(result)
        controller.hide()
        XCTAssertTrue(toast.isShowing)
        XCTAssertEqual(toast.currentFeedback, result)
    }
}

@MainActor
private final class ToastSpaceTestPanel: ToastPanel {
    var activeSpace = false
    var ordering: [String] = []
    override var isVisible: Bool { true }
    override var isOnActiveSpace: Bool { activeSpace }
    override func orderOut(_ sender: Any?) { ordering.append("out") }
    override func orderFrontRegardless() { ordering.append("front") }
}
