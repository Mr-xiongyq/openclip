// AISystemPromptSection.swift
// OpenClip
//
// The editable part of the AI system prompt as a collapsible `Section` of the AI page (collapsed by
// default, state remembered): OpenClip's role line and general behavior rules, which every AI run
// (presets, Ask AI, follow-ups) sends ahead of the action's own prompt. The editor starts from the
// built-in text; "Reset to Default" clears the override, and a "Custom" badge shows in the header
// even while collapsed. The task, the rule for the selected text in `<text>…</text>` and the
// `<result>` output format are always appended by `AIRequestSupport.systemPrompt` and cannot be
// edited here, so a custom prompt changes behavior without breaking how answers are read back.

import SwiftUI
import Core

extension SettingKey where Value == Bool {
    static var preferencesSystemPromptExpanded: SettingKey<Bool> {
        SettingKey<Bool>("preferencesAI.systemPromptExpanded", defaultValue: false)
    }
}

@MainActor
struct AISystemPromptSection: View {
    @ObservedObject private var aiManager = AIServiceManager.shared
    @Setting(SettingKey.preferencesSystemPromptExpanded) private var isExpanded
    @State private var draft = ""
    @State private var isLoaded = false

    private var isCustomized: Bool {
        !AIServiceManager.normalizedCustomSystemPrompt(draft).isEmpty
    }

    var body: some View {
        Section {
            if isExpanded {
                TextEditor(text: $draft)
                    .font(.system(size: NSFont.systemFontSize))
                    .frame(minHeight: 160, maxHeight: 280)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel(String(localized: "System Prompt"))
            }
        } header: {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 10)
                        Text("System Prompt")
                        if isCustomized {
                            Text("Custom")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "System Prompt"))
                .accessibilityValue(isExpanded ? String(localized: "Expanded") : String(localized: "Collapsed"))

                Spacer()

                if isExpanded {
                    Button("Reset to Default") {
                        draft = AIRequestSupport.defaultGuidelines
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .disabled(!isCustomized)
                }
            }
        } footer: {
            if isExpanded {
                Text("Sent with every AI action, before the action's own prompt. OpenClip always adds the action's prompt, how to treat the selected text, and the answer format after it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!aiManager.isAIEnabled)
        .onAppear {
            guard !isLoaded else { return }
            let stored = aiManager.customSystemPrompt
            draft = stored.isEmpty ? AIRequestSupport.defaultGuidelines : stored
            isLoaded = true
        }
        // Saves as the user types; blank or unchanged text is stored as "use the built-in prompt".
        .onChange(of: draft) { _, newValue in
            guard isLoaded else { return }
            aiManager.customSystemPrompt = newValue
        }
    }
}
