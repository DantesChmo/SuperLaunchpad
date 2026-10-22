import Foundation
import Testing
@testable import SuperLaunchpad

@MainActor
struct LaunchpadViewModelSearchTests {

    private func makeVM(apps: [AppEntry] = []) -> LaunchpadViewModel {
        let vm = LaunchpadViewModel(database: nil)
        vm.apps = apps
        return vm
    }

    private func app(_ name: String, page: Int? = 0, order: Int? = 0, folderID: String? = nil) -> AppEntry {
        AppEntry(
            bundleIdentifier: "com.test.\(name)",
            displayName: name,
            appPath: "/Applications/\(name).app",
            pageIndex: page,
            orderIndex: order,
            folderID: folderID,
            folderOrderIndex: folderID == nil ? nil : 0
        )
    }

    private func numberedApps(_ count: Int) -> [AppEntry] {
        (0..<count).map { app(String(format: "App %02d", $0), order: $0) }
    }

    // MARK: - Results

    @Test func emptyQueryIsNotSearching() {
        let vm = makeVM(apps: [app("Safari")])
        #expect(vm.isSearching == false)
        #expect(vm.searchResults.isEmpty)
        #expect(vm.selectedResult == nil)
    }

    @Test func whitespaceQueryIsNotSearching() {
        let vm = makeVM(apps: [app("Safari")])
        vm.searchText = "  "
        #expect(vm.isSearching == false)
        #expect(vm.searchResults.isEmpty)
    }

    @Test func typingFiltersAppsIncludingFolderApps() {
        let vm = makeVM(apps: [
            app("Calendar"),
            app("Calculator", page: nil, order: nil, folderID: "utilities"),
            app("Mail"),
        ])
        vm.searchText = "cal"
        #expect(vm.isSearching)
        #expect(vm.searchResults.map(\.displayName) == ["Calculator", "Calendar"])
        #expect(vm.selectedResult?.displayName == "Calculator")
    }

    @Test func resultsAreCappedAtOnePage() {
        let vm = makeVM(apps: numberedApps(Grid.appsPerPage + 5))
        vm.searchText = "app"
        #expect(vm.searchResults.count == Grid.appsPerPage)
    }

    @Test func resultsFollowAppListChanges() {
        let vm = makeVM(apps: [app("Safari")])
        vm.searchText = "s"
        vm.apps = [app("Safari"), app("Stocks")]
        #expect(vm.searchResults.map(\.displayName) == ["Safari", "Stocks"])
    }

    @Test func typingClosesOpenFolder() {
        let vm = makeVM(apps: [app("Mail")])
        vm.openFolderID = "folder"
        vm.searchText = "m"
        #expect(vm.openFolderID == nil)
    }

    // MARK: - Selection

    @Test func selectionMovesAndClamps() {
        let vm = makeVM(apps: numberedApps(10))
        vm.searchText = "app"
        vm.moveSelection(by: -1)
        #expect(vm.selectedResultIndex == 0)
        vm.moveSelection(by: 1)
        #expect(vm.selectedResultIndex == 1)
        vm.moveSelection(by: Grid.columns)
        #expect(vm.selectedResultIndex == 1 + Grid.columns)
        vm.moveSelection(by: Grid.columns)
        #expect(vm.selectedResultIndex == 9)
        #expect(vm.selectedResult?.displayName == "App 09")
    }

    @Test func selectionResetsWhenQueryChanges() {
        let vm = makeVM(apps: numberedApps(10))
        vm.searchText = "app"
        vm.moveSelection(by: 3)
        vm.searchText = "app 0"
        #expect(vm.selectedResultIndex == 0)
    }

    @Test func selectionClampsWhenResultsShrink() {
        let vm = makeVM(apps: numberedApps(5))
        vm.searchText = "app"
        vm.moveSelection(by: 4)
        vm.apps = numberedApps(2)
        #expect(vm.selectedResultIndex == 1)
    }

    @Test func moveSelectionWithoutResultsIsNoOp() {
        let vm = makeVM(apps: [app("Mail")])
        vm.searchText = "zzz"
        vm.moveSelection(by: 1)
        #expect(vm.selectedResultIndex == 0)
        #expect(vm.selectedResult == nil)
    }

    // MARK: - Escape ladder

    @Test func escapeClearsQueryThenClosesFolderThenHides() {
        let vm = makeVM(apps: [app("Mail")])
        vm.searchText = "m"
        vm.openFolderID = "folder"
        #expect(vm.handleEscape() == .clearedSearch)
        #expect(vm.searchText.isEmpty)
        #expect(vm.openFolderID == "folder")
        #expect(vm.handleEscape() == .closedFolder)
        #expect(vm.openFolderID == nil)
        #expect(vm.handleEscape() == .hideLauncher)
    }

    @Test func escapeClearsWhitespaceOnlyQuery() {
        let vm = makeVM()
        vm.searchText = " "
        #expect(vm.handleEscape() == .clearedSearch)
        #expect(vm.searchText.isEmpty)
    }

    // MARK: - show / hide

    @Test func hideClearsQuery() {
        let vm = makeVM(apps: [app("Mail")])
        vm.show()
        vm.searchText = "m"
        vm.hide()
        #expect(vm.searchText.isEmpty)
        #expect(vm.searchResults.isEmpty)
    }

    @Test func showRequestsSearchFocus() {
        let vm = makeVM()
        let before = vm.searchFocusRequest
        vm.show()
        #expect(vm.searchFocusRequest == before + 1)
    }
}
