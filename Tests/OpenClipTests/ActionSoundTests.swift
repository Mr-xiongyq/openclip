import XCTest
@testable import Core
@testable import OpenClip

final class ActionSoundTests: XCTestCase {
    func testUnknownStoredNameFallsBackToDefault() {
        XCTAssertEqual(ActionSound(stored: "nope"), .click)
        for retired in ["swoosh", "tick", "thock", "bubble", "zip", "glass", "uiPop", "chime", "blip", "dew", "knock", "tap", "system.ping"] {
            XCTAssertEqual(ActionSound(stored: retired), .default, "The retired \(retired) sound maps to the default")
        }
        XCTAssertEqual(ActionSound(stored: "drop"), .drop)
        XCTAssertEqual(ActionSound(stored: "system.tink"), .systemTink)
    }

    func testBundledRecordingsAreShippedAndSmall() throws {
        for name in ["ActionClick", "ActionDrop"] {
            let url = try XCTUnwrap(Bundle(for: AppDelegate.self).url(forResource: name, withExtension: "caf"), name)
            XCTAssertLessThan(try Data(contentsOf: url).count, 20_000, name)
        }
    }

    @MainActor
    func testPrepareLoadsTheChosenSoundBeforeItIsPlayed() {
        let store = MemorySettingsStore()
        store.set(.playActionSound, value: true)
        store.set(.actionSoundName, value: "drop")
        ActionSound.evict(.drop)
        ActionSound.prepareIfEnabled(store: store)
        XCTAssertTrue(ActionSound.isReady(.drop))
    }

    @MainActor
    func testPrepareDoesNothingWhenTheSettingIsOff() {
        let store = MemorySettingsStore()
        store.set(.actionSoundName, value: "system.pop")
        ActionSound.evict(.systemPop)
        ActionSound.prepareIfEnabled(store: store)
        XCTAssertFalse(ActionSound.isReady(.systemPop))
    }
}
