import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Settings → Layout: save the layout to a file, load one, reset it, and undo
// the last reset or load from the automatic backup.
struct LayoutSettingsSection: View {
    let viewModel: LaunchpadViewModel

    @State private var isResetSheetShown = false
    @State private var systemOrdering: LaunchpadOrdering?
    @State private var latestBackup: URL?
    @State private var status: String?
    @State private var failure: Failure?

    private struct Failure: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        Section {
            Button("Save Layout to File…", action: saveToFile)
            Button("Load Layout from File…", action: loadFromFile)
            Button("Reset Layout…", action: showResetSheet)
            HStack {
                Button("Restore Previous Layout", action: restorePrevious)
                Button("Show Backups in Finder", action: showBackups)
            }
            .disabled(latestBackup == nil)
            if let status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Layout")
        } footer: {
            Text("Before a reset or a load, the current layout is saved to a backup. Restore Previous Layout brings it back.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $isResetSheetShown) {
            ResetLayoutSheet(hasSystemLayout: systemOrdering != nil) { mode in
                isResetSheetShown = false
                reset(mode)
            } onCancel: {
                isResetSheetShown = false
            }
        }
        .alert(item: $failure) { failure in
            Alert(title: Text(failure.title), message: Text(failure.message))
        }
        .onAppear(perform: refreshBackups)
    }

    // MARK: - Actions

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = String(localized: "SuperLaunchpad Layout") + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try viewModel.layoutFile.encoded().write(to: url, options: .atomic)
            status = String(localized: "Saved to “\(url.lastPathComponent)”.")
        } catch {
            show(error, title: String(localized: "Couldn’t save the layout"))
        }
    }

    private func loadFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = try LayoutFile.decode(Data(contentsOf: url))
            let result = try viewModel.loadLayout(file)
            status = loadedStatus(result.applied, restored: false)
        } catch {
            show(error, title: String(localized: "Couldn’t load the layout"))
        }
        refreshBackups()
    }

    private func showResetSheet() {
        systemOrdering = SystemLaunchpadDB.readOrdering()
        isResetSheetShown = true
    }

    private func reset(_ mode: LayoutReset.Mode) {
        do {
            try viewModel.resetLayout(mode, systemOrdering: systemOrdering)
            status = String(localized: "Layout reset. Restore Previous Layout undoes it.")
        } catch {
            show(error, title: String(localized: "Couldn’t reset the layout"))
        }
        refreshBackups()
    }

    private func restorePrevious() {
        do {
            guard let result = try viewModel.restorePreviousLayout() else { return }
            status = loadedStatus(result.applied, restored: true)
        } catch {
            show(error, title: String(localized: "Couldn’t restore the layout"))
        }
        refreshBackups()
    }

    private func showBackups() {
        guard let latestBackup else { return }
        NSWorkspace.shared.activateFileViewerSelecting([latestBackup])
    }

    // MARK: - Helpers

    private func refreshBackups() {
        latestBackup = viewModel.layoutBackups?.latest
    }

    private func loadedStatus(_ applied: LayoutFile.Applied, restored: Bool) -> String {
        var lines = [restored
            ? String(localized: "Previous layout restored. Restore again to undo.")
            : String(localized: "Layout loaded. Restore Previous Layout undoes it.")]
        if !applied.skippedApps.isEmpty {
            lines.append(String(localized: "Not installed on this Mac, skipped: \(applied.skippedApps.count)."))
        }
        if !applied.appendedApps.isEmpty {
            lines.append(String(localized: "Not in the file, put at the end: \(applied.appendedApps.count)."))
        }
        return lines.joined(separator: "\n")
    }

    private func show(_ error: Error, title: String) {
        let localized = error as? LocalizedError
        let message = [localized?.errorDescription ?? error.localizedDescription, localized?.recoverySuggestion]
            .compactMap { $0 }
            .joined(separator: " ")
        failure = Failure(title: title, message: message)
    }
}

private struct ResetLayoutSheet: View {
    let hasSystemLayout: Bool
    let onReset: (LayoutReset.Mode) -> Void
    let onCancel: () -> Void

    @State private var mode: LayoutReset.Mode

    init(hasSystemLayout: Bool, onReset: @escaping (LayoutReset.Mode) -> Void, onCancel: @escaping () -> Void) {
        self.hasSystemLayout = hasSystemLayout
        self.onReset = onReset
        self.onCancel = onCancel
        _mode = State(initialValue: hasSystemLayout ? .systemLaunchpad : .categories)
    }

    private var modes: [LayoutReset.Mode] {
        LayoutReset.Mode.allCases.filter { $0 != .systemLaunchpad || hasSystemLayout }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ResetSheet.spacing) {
            Text("Reset Layout")
                .font(.headline)
            Picker("Arrange apps", selection: $mode) {
                ForEach(modes) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            Text("Every app gets a new place and folders are rebuilt. Hidden apps stay hidden. The current layout is saved to a backup first.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Reset", role: .destructive) { onReset(mode) }
            }
        }
        .padding()
        .frame(width: ResetSheet.width)
    }
}
