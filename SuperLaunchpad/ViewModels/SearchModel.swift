import Foundation

// The query, its results and the keyboard selection in them, and the
// Frequently Used row (Settings → Search). Owned by `LaunchpadViewModel`,
// which tells it when the apps or folders change.
@MainActor
@Observable
final class SearchModel {
    private unowned let launchpad: LaunchpadViewModel

    init(launchpad: LaunchpadViewModel) {
        self.launchpad = launchpad
    }

    // Bound to the search field. A non-empty query replaces the paged grid
    // with `searchResults`; typing closes an open folder.
    var searchText: String = "" {
        didSet {
            guard searchText != oldValue else { return }
            let searching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            // Assigned only on change, so views reading it are not
            // re-rendered on every keystroke.
            if isSearching != searching { isSearching = searching }
            if isSearching {
                launchpad.openFolderID = nil
                launchpad.editing.exitEditMode()
            }
            rebuildSearchResults()
            selectedResultIndex = 0
        }
    }

    // Search results for `searchText` (see `AppSearch`): apps and folders,
    // capped at one page. Stored for the same reason as `pages`.
    private(set) var searchResults: [LaunchpadItem] = []
    private(set) var selectedResultIndex = 0
    // Bumped on every `show()`; the search field takes focus when it changes,
    // so typing starts a query straight away.
    private(set) var searchFocusRequest = 0

    // True while the query has non-whitespace text.
    private(set) var isSearching = false

    var selectedResult: LaunchpadItem? {
        searchResults.indices.contains(selectedResultIndex) ? searchResults[selectedResultIndex] : nil
    }

    // Settings → Search: the most launched apps, in a row above the grid;
    // empty while the setting is off. Picked on `show()` and kept in that
    // order while the launcher is open, so a ⌘-click doesn't move the icon
    // under the pointer; the entries still follow `apps`.
    private(set) var frequentApps: [AppEntry] = []
    @ObservationIgnored private var frequentAppIDs: [String] = []
    @ObservationIgnored var preferences = Preferences()

    // Clamped to the results: the selection never wraps or leaves the page.
    func moveSelection(by delta: Int) {
        guard !searchResults.isEmpty else { return }
        selectedResultIndex = min(max(selectedResultIndex + delta, 0), searchResults.count - 1)
    }

    // A folder found by search opens over the grid; the query is cleared, as
    // typing would close the folder again.
    func openFolderFromSearch(_ folder: FolderEntry) {
        searchText = ""
        launchpad.requestFolderOpen(folder.id, renaming: false)
    }

    func launcherDidShow() {
        searchFocusRequest += 1
        pickFrequentApps()
    }

    func contentsDidChange() {
        rebuildSearchResults()
        rebuildFrequentApps()
    }

    private func pickFrequentApps() {
        frequentAppIDs = preferences.showsFrequentApps
            ? AppSearch.mostLaunched(launchpad.apps.filter { !$0.isHidden }).prefix(FrequentApps.maxCount).map(\.bundleIdentifier)
            : []
        rebuildFrequentApps()
    }

    private func rebuildFrequentApps() {
        guard !frequentAppIDs.isEmpty || !frequentApps.isEmpty else { return }
        let appsByID = Dictionary(launchpad.apps.map { ($0.bundleIdentifier, $0) }) { first, _ in first }
        let rebuilt = frequentAppIDs.compactMap { appsByID[$0] }.filter { !$0.isHidden }
        // Assigned only on change, like `isSearching`.
        if rebuilt != frequentApps { frequentApps = rebuilt }
    }

    private func rebuildSearchResults() {
        searchResults = Array(AppSearch.results(for: searchText, in: launchpad.apps, folders: launchpad.folders).prefix(Grid.appsPerPage))
        selectedResultIndex = min(selectedResultIndex, max(searchResults.count - 1, 0))
    }
}
