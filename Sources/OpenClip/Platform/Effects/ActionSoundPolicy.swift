// ActionSoundPolicy.swift
// OpenClip
//
// Decides whether finishing an action plays the chosen sound. An action plays it unless the user silenced it;
// a copy that belongs to no action (the card's Copy button, screen-text capture) plays it too.
import Core

extension ActionResult {
    /// Whether this result writes to the clipboard.
    var copiesToClipboard: Bool {
        switch self {
        case .copy, .copySelection, .copyContent, .copyDefinition: return true
        case .sequence(let items): return items.contains { $0.copiesToClipboard }
        default: return false
        }
    }
}

enum ActionSoundPolicy {
    /// `owner` is the finished action's id, nil when no action is involved. Only the last step of a
    /// multi-step action plays, so `isFinalStep` is false for the earlier ones.
    @MainActor
    static func play(
        owner: String?,
        result: ActionResult? = nil,
        isFinalStep: Bool = true,
        store: SettingsStore = DefaultSettingsStore.shared,
        play: @MainActor (ActionSound) -> Void = { $0.play() }
    ) {
        guard store.get(.playActionSound) else { return }
        if let owner {
            guard isFinalStep, !store.get(.actionSoundDisabledActionIDs).contains(owner) else { return }
        } else {
            guard result?.copiesToClipboard == true else { return }
        }
        play(ActionSound(stored: store.get(.actionSoundName)))
    }
}
