import XCTest
@testable import OpenClip

final class CustomActionSoundTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("custom-sound-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var bundledSound: URL {
        get throws { try XCTUnwrap(Bundle(for: AppDelegate.self).url(forResource: "ActionClick", withExtension: "caf")) }
    }

    @MainActor
    func testImportCopiesTheFileAndReturnsItsName() throws {
        let store = directory.appendingPathComponent("store")
        let name = try CustomActionSound.importFile(from: try bundledSound, into: store)
        XCTAssertEqual(name, "ActionClick")
        XCTAssertEqual(CustomActionSound.storedURL(in: store)?.lastPathComponent, "custom.caf")
    }

    @MainActor
    func testImportReplacesThePreviousSound() throws {
        let store = directory.appendingPathComponent("store")
        try CustomActionSound.importFile(from: try bundledSound, into: store)
        let second = directory.appendingPathComponent("Other.CAF")
        try FileManager.default.copyItem(at: try bundledSound, to: second)
        try CustomActionSound.importFile(from: second, into: store)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.path), ["custom.caf"])
    }

    @MainActor
    func testUnplayableFileIsRejectedAndNothingIsStored() throws {
        let store = directory.appendingPathComponent("store")
        let bogus = directory.appendingPathComponent("notes.mp3")
        try Data("not audio".utf8).write(to: bogus)
        XCTAssertThrowsError(try CustomActionSound.importFile(from: bogus, into: store)) {
            XCTAssertEqual($0 as? CustomActionSound.ImportError, .unreadable)
        }
        XCTAssertNil(CustomActionSound.storedURL(in: store))
    }

    @MainActor
    func testOversizedFileIsRejected() throws {
        let big = directory.appendingPathComponent("big.wav")
        try Data(count: CustomActionSound.maxBytes + 1).write(to: big)
        XCTAssertThrowsError(try CustomActionSound.importFile(from: big, into: directory.appendingPathComponent("store"))) {
            XCTAssertEqual($0 as? CustomActionSound.ImportError, .tooLarge)
        }
    }

    func testRemoveClearsTheStoredSound() throws {
        try Data("x".utf8).write(to: directory.appendingPathComponent("custom.wav"))
        XCTAssertNotNil(CustomActionSound.storedURL(in: directory))
        CustomActionSound.remove(from: directory)
        XCTAssertNil(CustomActionSound.storedURL(in: directory))
    }
}
