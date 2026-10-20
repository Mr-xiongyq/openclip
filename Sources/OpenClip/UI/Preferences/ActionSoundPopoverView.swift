// ActionSoundPopoverView.swift
// OpenClip
//
// Mini popover for choosing which actions play the sound when they finish.
import SwiftUI
import Core

@MainActor
struct ActionSoundPopoverView: View {
    @Setting(SettingKey.actionSoundDisabledActionIDs) private var disabledIDs
    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @State private var query = ""

    private struct Row: Identifiable {
        let id: String
        let title: String
        let icon: ActionIcon
    }

    private var rows: [Row] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return coordinator.actions.compactMap { action in
            let presentation = customizationManager.presented(action, surface: .table)
            guard needle.isEmpty || presentation.title.localizedCaseInsensitiveContains(needle) else { return nil }
            return Row(id: action.id, title: presentation.title, icon: presentation.icon)
        }
    }

    private var allVisibleSelected: Bool {
        !rows.isEmpty && rows.allSatisfy { !disabledIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Play Sound When Finished"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SettingsDesignTokens.rowTitleColor)
                Spacer(minLength: 8)
                Button(allVisibleSelected ? String(localized: "Clear") : String(localized: "Select All")) {
                    toggleAllVisible()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .disabled(rows.isEmpty)
            }

            TextField(String(localized: "Search actions"), text: $query)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)

            Divider()

            if rows.isEmpty {
                Text(String(localized: "No matching actions."))
                    .font(.caption)
                    .foregroundStyle(SettingsDesignTokens.secondaryText)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 8) {
                        ForEach(rows) { row in
                            rowView(row)
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(height: min(max(CGFloat(rows.count) * 32, 32), 260))
                .scrollIndicators(.automatic)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func toggleAllVisible() {
        var updated = disabledIDs
        if allVisibleSelected {
            rows.forEach { updated.insert($0.id) }
        } else {
            rows.forEach { updated.remove($0.id) }
        }
        disabledIDs = updated
    }

    private func rowView(_ row: Row) -> some View {
        let isOn = Binding<Bool>(
            get: { !disabledIDs.contains(row.id) },
            set: { enabled in
                var updated = disabledIDs
                if enabled { updated.remove(row.id) } else { updated.insert(row.id) }
                disabledIDs = updated
            }
        )
        return HStack(alignment: .center, spacing: 10) {
            ActionIconView(icon: row.icon, size: 15)
                .frame(width: 18, height: 18, alignment: .center)
                .foregroundStyle(.secondary)

            Text(row.title)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(SettingsDesignTokens.rowTitleColor)
                .lineLimit(1)

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(String(localized: "Play sound for \(row.title)"))
        }
    }
}
