// ActionSound.swift
// OpenClip
//
// The short sounds offered for the "Play Sound" setting: two bundled recordings (see
// docs/developer-guide/action-sounds.md), two macOS system sounds played from their own files, and the user's own
// file (see CustomActionSound).
// `prepareIfEnabled` loads the chosen sound and wakes the audio output ahead of the first action, so the first play
// is as prompt as later ones.
import AppKit
import Core

public enum ActionSound: String, CaseIterable, Identifiable, Sendable {
    case click, drop
    case systemTink = "system.tink"
    case systemPop = "system.pop"
    case custom

    public var id: String { rawValue }
    public static let `default`: ActionSound = .click

    /// English literal; also the localization key.
    public var title: String {
        switch self {
        case .click: return "Click"
        case .drop: return "Drop"
        case .systemTink: return "Tink"
        case .systemPop: return "Pop"
        case .custom: return "Custom"
        }
    }

    /// Unknown values, including the retired sounds, fall back to the default. A custom choice whose file is gone
    /// falls back too.
    public init(stored: String) {
        let parsed = ActionSound(rawValue: stored) ?? .default
        self = parsed == .custom && CustomActionSound.storedURL() == nil ? .default : parsed
    }

    /// Built-in sounds, in picker order; the custom sound is offered only once a file has been imported.
    public static let builtIn: [ActionSound] = [.click, .drop, .systemTink, .systemPop]

    private var soundFileURL: URL? {
        switch self {
        case .click: return Bundle.main.url(forResource: "ActionClick", withExtension: "caf")
        case .drop: return Bundle.main.url(forResource: "ActionDrop", withExtension: "caf")
        case .systemTink: return URL(fileURLWithPath: "/System/Library/Sounds/Tink.aiff")
        case .systemPop: return URL(fileURLWithPath: "/System/Library/Sounds/Pop.aiff")
        case .custom: return CustomActionSound.storedURL()
        }
    }

    /// The sounds differ a lot in loudness, so each gets its own level.
    private var volume: Float {
        switch self {
        case .systemTink: return 0.35
        case .click, .drop, .systemPop: return 0.5
        case .custom: return 0.7
        }
    }

    @MainActor private static var cache: [ActionSound: NSSound] = [:]
    @MainActor private static var silence: NSSound?

    /// Tests exercise the real handlers; they must never make noise.
    private static let isUnderTest = NSClassFromString("XCTestCase") != nil

    @MainActor static func isReady(_ sound: ActionSound) -> Bool { cache[sound] != nil }
    @MainActor static func evict(_ sound: ActionSound) { cache[sound] = nil }

    /// Loads the chosen sound and wakes the audio output, when the setting is on.
    /// Call when the app launches, the setting changes, or an action is likely.
    @MainActor public static func prepareIfEnabled(store: SettingsStore = DefaultSettingsStore.shared) {
        guard store.get(.playActionSound) else { return }
        prepare(ActionSound(stored: store.get(.actionSoundName)))
        wakeOutput()
    }

    @MainActor static func prepare(_ sound: ActionSound) {
        guard cache[sound] == nil, let url = sound.soundFileURL,
              let loaded = NSSound(contentsOf: url, byReference: true) else { return }
        loaded.volume = sound.volume
        cache[sound] = loaded
    }

    /// An idle output device takes noticeable time to start, which delays the first audible sample.
    /// Starting a silent copy of the default sound opens it early; the first real sound then begins without that wait.
    @MainActor static func wakeOutput() {
        guard !isUnderTest else { return }
        if silence == nil, let url = Self.default.soundFileURL {
            silence = NSSound(contentsOf: url, byReference: true)
            silence?.volume = 0
        }
        silence?.stop()
        silence?.play()
    }

    /// Restarts from the beginning, so rapid copies never go silent while the previous one plays.
    /// A missing sound file plays the default.
    @MainActor public func play() {
        guard !Self.isUnderTest else { return }
        Self.prepare(self)
        guard let sound = Self.cache[self] else {
            if self != .default { Self.default.play() }
            return
        }
        sound.stop()
        sound.play()
    }
}
