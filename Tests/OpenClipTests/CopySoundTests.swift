import XCTest
@testable import OpenClip

final class CopySoundTests: XCTestCase {
    func testUnknownStoredNameFallsBackToDefault() {
        XCTAssertEqual(CopySound(stored: "nope"), .swoosh)
        XCTAssertEqual(CopySound(stored: "zip"), .swoosh, "The retired Zip sound maps to the default")
        XCTAssertEqual(CopySound(stored: "glass"), .glass)
    }

    func testEverySoundIsShortAudibleAndBounded() {
        for sound in CopySound.allCases {
            let samples = sound.samples()
            XCTAssertGreaterThan(samples.count, 1_000, sound.rawValue)
            XCTAssertLessThan(samples.count, 44_100, sound.rawValue)
            XCTAssertTrue(samples.allSatisfy { abs($0) <= 1 }, sound.rawValue)
            XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.05, sound.rawValue)
            XCTAssertEqual(sound.samples(), samples, "Synthesis must be deterministic")
        }
    }

    @MainActor
    func testPrepareBuildsTheSoundBeforeItIsPlayed() async throws {
        let store = MemorySettingsStore()
        store.set(.playCopySound, value: true)
        store.set(.copySoundName, value: "thock")
        CopySound.prepareIfEnabled(store: store)

        let deadline = Date().addingTimeInterval(5)
        while !CopySound.isReady(.thock), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(CopySound.isReady(.thock))
    }

    @MainActor
    func testPrepareDoesNothingWhenTheSettingIsOff() async throws {
        let store = MemorySettingsStore()
        store.set(.copySoundName, value: "bubble")
        CopySound.prepareIfEnabled(store: store)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(CopySound.isReady(.bubble))
    }
}
