import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class ActionSoundPolicyTests: XCTestCase {
    private func store(enabled: Bool = true, silenced: Set<String> = ["b"]) -> MemorySettingsStore {
        let store = MemorySettingsStore()
        store.set(.playActionSound, value: enabled)
        store.set(.actionSoundDisabledActionIDs, value: silenced)
        store.set(.actionSoundName, value: "drop")
        return store
    }

    private func plays(owner: String?, result: ActionResult? = nil, isFinalStep: Bool = true, store: MemorySettingsStore? = nil) -> [ActionSound] {
        var played: [ActionSound] = []
        ActionSoundPolicy.play(owner: owner, result: result, isFinalStep: isFinalStep, store: store ?? self.store(), play: { played.append($0) })
        return played
    }

    func testEveryActionPlaysUnlessSilenced() {
        XCTAssertEqual(plays(owner: "a"), [.drop])
        XCTAssertEqual(plays(owner: "never-seen"), [.drop])
        XCTAssertTrue(plays(owner: "b").isEmpty)
    }

    func testSilencedActionStaysSilentEvenWhenItCopies() {
        XCTAssertTrue(plays(owner: "b", result: .copy("x")).isEmpty)
        XCTAssertEqual(plays(owner: "a", result: .copy("x")), [.drop])
    }

    func testNothingPlaysWhenTheSettingIsOff() {
        XCTAssertTrue(plays(owner: "a", store: store(enabled: false)).isEmpty)
        XCTAssertTrue(plays(owner: nil, result: .copy("x"), store: store(enabled: false)).isEmpty)
    }

    func testOnlyTheLastStepOfAnActionPlays() {
        XCTAssertTrue(plays(owner: "a", isFinalStep: false).isEmpty)
        XCTAssertEqual(plays(owner: "a", isFinalStep: true), [.drop])
    }

    func testCopiesWithoutAnActionPlayAndOtherResultsDoNot() {
        XCTAssertEqual(plays(owner: nil, result: .copy("x")), [.drop])
        XCTAssertTrue(plays(owner: nil, result: .paste("x")).isEmpty)
        XCTAssertTrue(plays(owner: nil).isEmpty)
    }

    func testCopyEffectsAreRecognisedEvenInsideASequence() {
        XCTAssertTrue(ActionResult.copy("x").copiesToClipboard)
        XCTAssertTrue(ActionResult.sequence([.none, .copy("x")]).copiesToClipboard)
        XCTAssertFalse(ActionResult.paste("x").copiesToClipboard)
        XCTAssertFalse(ActionResult.none.copiesToClipboard)
    }
}
