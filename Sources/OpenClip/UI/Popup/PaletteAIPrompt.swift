// PaletteAIPrompt.swift
// OpenClip
//
// The action-search palette's AI fallback: when a query matches nothing, offer it as an AI
// instruction (run on the selection, or saved as a reusable AI tool). Pure presentation model so
// the rules are unit-testable without SwiftUI.
import Foundation
import Core

/// One row of the palette's AI fallback, in display order.
enum PaletteAIPromptRow: Hashable, CaseIterable {
    /// Run the typed text as an AI instruction transforming the selection.
    case apply
    /// Run the typed text as a standalone AI question without selection context.
    case ask
    /// Save the typed text as a custom AI tool, then run it.
    case save
}

enum PaletteAIPrompt {
    /// Longest title a saved tool gets before it is elided with an ellipsis.
    static let maxToolTitleLength = 40

    /// What the palette found for the query, as far as the AI rows care.
    enum Results {
        /// Nothing matched: offer both rows.
        case none
        /// Real actions matched: no AI rows.
        case actions
    }

    /// AI rows appear only when nothing matched, and never for a blank query or with AI off.
    static func rows(for query: String, aiEnabled: Bool, results: Results) -> [PaletteAIPromptRow] {
        guard aiEnabled, !instruction(from: query).isEmpty else { return [] }
        switch results {
        case .none: return PaletteAIPromptRow.allCases
        case .actions: return []
        }
    }

    /// Short action title for primary execution (⏎).
    static func primaryActionTitle() -> String {
        String(localized: "Show")
    }

    /// Short action title for secondary execution (⇧⏎).
    static func secondaryActionTitle(canPaste: Bool?) -> String {
        canPaste == false ? String(localized: "Copy") : String(localized: "Replace")
    }

    /// The key hint under the AI rows: ⏎ shows the result card, ⇧⏎ replaces the selection
    /// (copies when the target can't paste).
    static func hint(canPaste: Bool?) -> String {
        let secondary = secondaryActionTitle(canPaste: canPaste).lowercased()
        return "⏎ show · ⇧⏎ \(secondary)"
    }

    /// The query with whitespace trimmed and collapsed, so stray spaces never change the prompt.
    static func instruction(from query: String) -> String {
        query
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }

    /// Prompt instruction wrapped with format requirements for standalone questions/tasks.
    static func standaloneQuestionPrompt(for query: String) -> String {
        let task = instruction(from: query)
        return """
        \(task)

        Format requirements:
        1. Output a short 2-4 word title for this question/topic inside <title>...</title> tags.
        2. Output your answer or response inside <result>...</result> tags.
        """
    }

    /// Prompt instruction wrapped with format requirements to generate a 2-4 word task title.
    static func askAITaskPrompt(for query: String) -> String {
        let task = instruction(from: query)
        return """
        \(task)

        Format requirements:
        1. Output a short 2-4 word title for this task inside <title>...</title> tags.
        2. Output your transformed text inside <result>...</result> tags.
        """
    }

    /// Prompt instruction wrapped with format requirements to generate a clean reusable tool name.
    /// Shares the `<title>` tag with the task-heading flows.
    static func saveToolTaskPrompt(for query: String) -> String {
        let task = instruction(from: query)
        return """
        \(task)

        Format requirements:
        1. Output a clean, concise 2-4 word action tool name for this reusable tool inside <title>...</title> tags (e.g. "Formal Email Rewriter", "Translate to Slovak").
        2. Output your transformed text inside <result>...</result> tags.
        """
    }

    /// Tool title: the capitalised instruction cut at a word boundary to `maxToolTitleLength`, with
    /// an ellipsis when trimmed. Empty for a blank prompt.
    static func toolTitle(for prompt: String) -> String {
        let collapsed = instruction(from: prompt)
        guard let first = collapsed.first else { return "" }
        let capitalised = String(first).uppercased() + collapsed.dropFirst()
        guard capitalised.count > maxToolTitleLength else { return capitalised }

        let budget = maxToolTitleLength - 1 // room for the ellipsis
        var cut = String(capitalised.prefix(budget))
        if let lastSpace = cut.lastIndex(of: " "),
           cut.distance(from: cut.startIndex, to: lastSpace) >= budget / 2 {
            cut = String(cut[..<lastSpace])
        }
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }

    static func rowTitle(_ row: PaletteAIPromptRow, query: String = "") -> String {
        switch row {
        case .apply:
            return String(localized: "Rewrite Selection")
        case .ask:
            return String(localized: "Ask a Question")
        case .save:
            return String(localized: "Save as AI Tool")
        }
    }

    /// SF Symbol; `sparkle` is the app's AI mark, shared by all AI rows.
    static func rowSymbol(_ row: PaletteAIPromptRow) -> String {
        Constants.defaultAIIconSymbol
    }
}
