// PaletteRowShortcuts.swift
// OpenClip
//
// ⌘1…⌘9 are global hot keys only while the palette is on screen. OpenClip never activates, so
// macOS would route a ⌘-digit to the frontmost app and the panel would never see it; the Carbon
// hot-key path (shared with ⌥⌘C) consumes them system-wide until the palette closes.
import AppKit
import Core
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let paletteRow1 = Self("paletteRow1", initial: .init(.one, modifiers: [.command]))
    static let paletteRow2 = Self("paletteRow2", initial: .init(.two, modifiers: [.command]))
    static let paletteRow3 = Self("paletteRow3", initial: .init(.three, modifiers: [.command]))
    static let paletteRow4 = Self("paletteRow4", initial: .init(.four, modifiers: [.command]))
    static let paletteRow5 = Self("paletteRow5", initial: .init(.five, modifiers: [.command]))
    static let paletteRow6 = Self("paletteRow6", initial: .init(.six, modifiers: [.command]))
    static let paletteRow7 = Self("paletteRow7", initial: .init(.seven, modifiers: [.command]))
    static let paletteRow8 = Self("paletteRow8", initial: .init(.eight, modifiers: [.command]))
    static let paletteRow9 = Self("paletteRow9", initial: .init(.nine, modifiers: [.command]))
}

@MainActor
enum PaletteRowShortcuts {
    /// Index 0 is row 1.
    static let names: [KeyboardShortcuts.Name] = [
        .paletteRow1, .paletteRow2, .paletteRow3, .paletteRow4, .paletteRow5,
        .paletteRow6, .paletteRow7, .paletteRow8, .paletteRow9
    ]

    /// Set by the composition root.
    private static var runRow: ((Int) -> Bool)?
    private static var isInstalled = false
    private(set) static var isActive = false

    /// Registers handlers once; the keys stay with the system until a palette opens.
    static func install(runRow: @escaping (Int) -> Bool) {
        self.runRow = runRow
        guard !isInstalled else { return }
        isInstalled = true
        for (index, name) in names.enumerated() {
            let row = index + 1
            KeyboardShortcuts.onKeyDown(for: name) {
                MainActor.assumeIsolated {
                    let handled = Self.runRow?(row) ?? false
                    Log.presentation.debug("palette shortcut ⌘\(row, privacy: .public) handled=\(handled, privacy: .public)")
                }
            }
        }
        setActive(false)
    }

    /// Idempotent.
    static func setActive(_ active: Bool) {
        guard active != isActive || !active else { return }
        isActive = active
        if active {
            KeyboardShortcuts.enable(names)
        } else {
            KeyboardShortcuts.disable(names)
        }
    }
}
