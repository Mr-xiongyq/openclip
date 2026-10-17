import XCTest
@testable import OpenClip

final class SelectionGestureTargetProbeTests: XCTestCase {
    func testRolePathClassification() {
        XCTAssertFalse(SelectionGestureTargetProbe.isWindowChrome(ancestorRoles: ["AXTextField", "AXToolbar", "AXWindow"]))
        XCTAssertFalse(SelectionGestureTargetProbe.isWindowChrome(ancestorRoles: ["AXStaticText", "AXWebArea", "AXWindow"]))
        XCTAssertFalse(SelectionGestureTargetProbe.isWindowChrome(ancestorRoles: ["AXStaticText", "AXGroup", "AXWindow"]))
        XCTAssertFalse(SelectionGestureTargetProbe.isWindowChrome(ancestorRoles: ["AXGroup", "AXWindow"]))
        XCTAssertTrue(SelectionGestureTargetProbe.isWindowChrome(ancestorRoles: ["AXGroup", "AXToolbar", "AXWindow"]))
        XCTAssertTrue(SelectionGestureTargetProbe.isWindowChrome(ancestorRoles: ["AXButton", "AXTitleBar", "AXWindow"]))
        XCTAssertFalse(SelectionGestureTargetProbe.isWindowChrome(ancestorRoles: ["AXUnknown", "AXUnknown"]))
        XCTAssertFalse(SelectionGestureTargetProbe.isWindowChrome(ancestorRoles: ["AXGroup"], subroles: ["AXUnknown"]))
        XCTAssertTrue(SelectionGestureTargetProbe.isWindowChrome(ancestorRoles: ["AXGroup", "AXUnknown"], subroles: [nil, "AXTitleBar"]))
    }

    /// Flat or lazily built AX trees (terminals, canvas editors, Electron before its tree exists)
    /// report their whole content area as a bare AXWindow hit. That must not read as chrome, or
    /// every drag/double-click in those apps is silently rejected before retrieval.
    func testBareWindowHitIsNotChrome() {
        XCTAssertFalse(SelectionGestureTargetProbe.isWindowChrome(ancestorRoles: ["AXWindow"]))
        XCTAssertFalse(SelectionGestureTargetProbe.isWindowChrome(ancestorRoles: ["AXWindow"], subroles: ["AXStandardWindow"]))
        XCTAssertFalse(SelectionGestureTargetProbe.isWindowChrome(ancestorRoles: ["AXWindow", "AXApplication"]))
        XCTAssertFalse(SelectionGestureTargetProbe.isWindowChrome(ancestorRoles: ["AXWindow", "AXToolbar"]),
                       "Roles past the window boundary belong to other windows and must not be read")
        XCTAssertTrue(SelectionGestureTargetProbe.isWindowChrome(ancestorRoles: ["AXToolbar", "AXWindow"]))
        XCTAssertTrue(SelectionGestureTargetProbe.isWindowChrome(ancestorRoles: ["AXButton", "AXWindow"], subroles: ["AXTitleBar", nil]))
    }

    @MainActor
    func testBlockedLookupReturnsFalseAtDeadlineWithoutWaitingForWorker() async {
        let unblock = DispatchSemaphore(value: 0)
        let started = expectation(description: "lookup started off main thread")
        let finished = expectation(description: "worker eventually exits")
        let point = CGPoint(x: 120, y: 240)
        let probe = SelectionGestureTargetProbe(timeout: 0.1) { pid, axPoint, deadline in
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertEqual(pid, 99991)
            XCTAssertEqual(axPoint, point)
            XCTAssertGreaterThan(deadline.timeIntervalSinceNow, 0)
            started.fulfill()
            _ = unblock.wait(timeout: .now() + 2)
            finished.fulfill()
            return true
        }
        defer { unblock.signal() }
        let start = Date()
        let request = Task { await probe.isWindowChrome(at: point, pid: 99991) }
        await fulfillment(of: [started], timeout: 1)
        let result = await request.value
        XCTAssertFalse(result, "Timed out AX checks must fail open")
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        unblock.signal()
        await fulfillment(of: [finished], timeout: 1)
    }

    func testQuickLookupReturnsItsAnswerAndRejectsInvalidPID() async {
        for chrome in [false, true] {
            let probe = SelectionGestureTargetProbe(timeout: 1) { _, _, _ in chrome }
            let result = await probe.isWindowChrome(at: .zero, pid: 99991)
            let invalidPIDResult = await probe.isWindowChrome(at: .zero, pid: 0)
            XCTAssertEqual(result, chrome)
            XCTAssertFalse(invalidPIDResult)
        }
    }

    func testCancelledLookupCannotRejectSelection() async {
        let unblock = DispatchSemaphore(value: 0)
        let started = expectation(description: "lookup started")
        let probe = SelectionGestureTargetProbe(timeout: 1) { _, _, _ in
            started.fulfill()
            _ = unblock.wait(timeout: .now() + 2)
            return true
        }
        defer { unblock.signal() }
        let request = Task { await probe.isWindowChrome(at: .zero, pid: 99991) }
        await fulfillment(of: [started], timeout: 1)
        request.cancel()
        unblock.signal()
        let result = await request.value
        XCTAssertFalse(result)
    }
}
