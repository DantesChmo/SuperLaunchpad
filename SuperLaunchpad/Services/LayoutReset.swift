import Foundation

// Settings → Reset Layout: lays every app out again from scratch. Reuses the
// first-run paths (`applyOrdering` for the system Launchpad DB, `InitialLayout`
// for categories). Hidden apps stay hidden and keep no position; the new-app
// dot is kept.
enum LayoutReset {
    enum Mode: String, CaseIterable, Identifiable {
        case systemLaunchpad
        case categories
        case alphabetical

        var id: String { rawValue }

        var title: String {
            switch self {
            case .systemLaunchpad: String(localized: "Like the system Launchpad")
            case .categories: String(localized: "By category")
            case .alphabetical: String(localized: "Alphabetically, without folders")
            }
        }
    }

    // `systemOrdering` is used by `.systemLaunchpad` only; without it that
    // mode falls back to categories. Apps the system layout doesn't know go
    // after the last item by name (the first-run import drops them until the
    // next rescan, a reset has no rescan to wait for).
    static func build(
        _ mode: Mode,
        apps: [AppEntry],
        systemOrdering: LaunchpadOrdering?,
        categoryOf: (AppEntry) -> AppCategory
    ) -> (apps: [AppEntry], folders: [FolderEntry]) {
        let visible = apps.filter { !$0.isHidden }

        let rows: [AppEntry]
        let folders: [FolderEntry]
        switch mode {
        case .systemLaunchpad:
            if let systemOrdering {
                (rows, folders) = LaunchpadViewModel.applyOrdering(systemOrdering, to: visible)
            } else {
                (rows, folders) = InitialLayout.build(visible, categoryOf: categoryOf)
            }
        case .categories:
            (rows, folders) = InitialLayout.build(visible, categoryOf: categoryOf)
        case .alphabetical:
            rows = sortedByName(visible).enumerated().map { index, app in
                var app = app
                app.pageIndex = index / Grid.appsPerPage
                app.orderIndex = index % Grid.appsPerPage
                app.folderID = nil
                app.folderOrderIndex = nil
                return app
            }
            folders = []
        }

        // Through `GridLayout` for dense positions: the system DB's ordering
        // has gaps and may name folders whose apps are not installed.
        var layout = GridLayout(apps: rows, folders: folders)
        layout.dissolveEmptyFolders()
        let placed = Set(rows.map(\.bundleIdentifier))
        for app in sortedByName(visible) where !placed.contains(app.bundleIdentifier) {
            layout.append(app.bundleIdentifier)
        }
        return layout.apply(to: apps, folders: folders)
    }

    private static func sortedByName(_ apps: [AppEntry]) -> [AppEntry] {
        apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
