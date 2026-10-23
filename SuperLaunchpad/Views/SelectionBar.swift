import SwiftUI

// The group actions for the apps selected in edit mode, in place of the
// search field (see AGENTS.md → "Multi-select"). Plain buttons, so VoiceOver
// reaches them like any other control.
struct SelectionBar: View {
    let viewModel: LaunchpadViewModel

    var body: some View {
        let editing = viewModel.editing
        let selected = editing.orderedSelection.compactMap { id in
            viewModel.apps.first { $0.bundleIdentifier == id }
        }
        HStack(spacing: Selection.barSpacing) {
            Text(selected.count == 1 ? String(localized: "1 app selected") : String(localized: "\(selected.count) apps selected"))
                .font(.system(size: Search.fieldFontSize, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, Selection.barPadding)

            Button {
                editing.makeFolderFromSelection()
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            .accessibilityIdentifier("selection-new-folder")

            Button {
                editing.hideSelection()
            } label: {
                Label("Hide", systemImage: "eye.slash")
            }
            .accessibilityIdentifier("selection-hide")

            Button {
                viewModel.removal.requestRemoval(of: selected)
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            // Apps that are part of macOS are skipped; only those selected.
            .disabled(!selected.contains { viewModel.removal.isRemovable($0) })
            .accessibilityIdentifier("selection-trash")

            Button {
                editing.clearSelection()
            } label: {
                Label("Deselect", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .help("Deselect")
            .accessibilityLabel("Deselect")
            .accessibilityIdentifier("selection-deselect")
        }
        .controlSize(.regular)
        .padding(Selection.barPadding)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Selection.barCornerRadius))
        .environment(\.colorScheme, .dark)
        // Clicks on the bar's background must not reach the launcher's
        // click-to-leave-edit-mode.
        .contentShape(Rectangle())
        .onTapGesture {}
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selection")
        .accessibilityIdentifier("selection-bar")
    }
}
