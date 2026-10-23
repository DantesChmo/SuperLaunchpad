import Foundation
import Testing
@testable import SuperLaunchpad

@MainActor
struct SearchModelTests {

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
        #expect(vm.search.isSearching == false)
        #expect(vm.search.searchResults.isEmpty)
        #expect(vm.search.selectedResult == nil)
    }

    @Test func whitespaceQueryIsNotSearching() {
        let vm = makeVM(apps: [app("Safari")])
        vm.search.searchText = "  "
        #expect(vm.search.isSearching == false)
        #expect(vm.search.searchResults.isEmpty)
    }

    @Test func typingFiltersAppsIncludingFolderApps() {
        let vm = makeVM(apps: [
            app("Calendar"),
            app("Calculator", page: nil, order: nil, folderID: "utilities"),
            app("Mail"),
        ])
        vm.search.searchText = "cal"
        #expect(vm.search.isSearching)
        #expect(vm.search.searchResults.map(\.name) == ["Calculator", "Calendar"])
        #expect(vm.search.selectedResult?.name == "Calculator")
    }

    @Test func resultsAreCappedAtOnePage() {
        let vm = makeVM(apps: numberedApps(Grid.appsPerPage + 5))
        vm.search.searchText = "app"
        #expect(vm.search.searchResults.count == Grid.appsPerPage)
    }

    @Test func resultsFollowAppListChanges() {
        let vm = makeVM(apps: [app("Safari")])
        vm.search.searchText = "s"
        vm.apps = [app("Safari"), app("Stocks")]
        #expect(vm.search.searchResults.map(\.name) == ["Safari", "Stocks"])
    }

    @Test func typingClosesOpenFolder() {
        let vm = makeVM(apps: [app("Mail")])
        vm.openFolderID = "folder"
        vm.search.searchText = "m"
        #expect(vm.openFolderID == nil)
    }

    // MARK: - Folders

    private func makeVMWithFolder() -> LaunchpadViewModel {
        let vm = makeVM(apps: [
            app("Terminal", page: nil, order: nil, folderID: "F"),
            app("Utility Belt"),
        ])
        vm.folders = [FolderEntry(id: "F", title: "Utilities", pageIndex: 0, orderIndex: 1)]
        return vm
    }

    @Test func foldersAreFoundByTitle() throws {
        let vm = makeVMWithFolder()
        vm.search.searchText = "util"

        #expect(vm.search.searchResults.map(\.name) == ["Utilities", "Utility Belt"])
        guard case .folder(let folder, let apps) = try #require(vm.search.selectedResult) else {
            Issue.record("expected the folder to be selected")
            return
        }
        #expect(folder.id == "F")
        #expect(apps.map(\.displayName) == ["Terminal"])
    }

    @Test func resultsFollowFolderChanges() {
        let vm = makeVMWithFolder()
        vm.search.searchText = "tools"
        #expect(vm.search.searchResults.isEmpty)
        vm.folders = [FolderEntry(id: "F", title: "Tools", pageIndex: 0, orderIndex: 1)]
        #expect(vm.search.searchResults.map(\.name) == ["Tools"])
    }

    @Test func openingFolderResultClearsQueryAndRequestsTheFolder() throws {
        let vm = makeVMWithFolder()
        vm.show()
        vm.search.searchText = "util"
        guard case .folder(let folder, _) = try #require(vm.search.selectedResult) else {
            Issue.record("expected the folder to be selected")
            return
        }

        vm.search.openFolderFromSearch(folder)

        #expect(vm.search.searchText.isEmpty)
        #expect(vm.search.isSearching == false)
        #expect(vm.isVisible)
        let request = try #require(vm.folderOpenRequest)
        #expect(request.folderID == "F")
        #expect(request.renaming == false)
    }

    // MARK: - Selection

    @Test func selectionMovesAndClamps() {
        let vm = makeVM(apps: numberedApps(10))
        vm.search.searchText = "app"
        vm.search.moveSelection(by: -1)
        #expect(vm.search.selectedResultIndex == 0)
        vm.search.moveSelection(by: 1)
        #expect(vm.search.selectedResultIndex == 1)
        vm.search.moveSelection(by: Grid.columns)
        #expect(vm.search.selectedResultIndex == 1 + Grid.columns)
        vm.search.moveSelection(by: Grid.columns)
        #expect(vm.search.selectedResultIndex == 9)
        #expect(vm.search.selectedResult?.name == "App 09")
    }

    @Test func selectionResetsWhenQueryChanges() {
        let vm = makeVM(apps: numberedApps(10))
        vm.search.searchText = "app"
        vm.search.moveSelection(by: 3)
        vm.search.searchText = "app 0"
        #expect(vm.search.selectedResultIndex == 0)
    }

    @Test func selectionClampsWhenResultsShrink() {
        let vm = makeVM(apps: numberedApps(5))
        vm.search.searchText = "app"
        vm.search.moveSelection(by: 4)
        vm.apps = numberedApps(2)
        #expect(vm.search.selectedResultIndex == 1)
    }

    @Test func moveSelectionWithoutResultsIsNoOp() {
        let vm = makeVM(apps: [app("Mail")])
        vm.search.searchText = "zzz"
        vm.search.moveSelection(by: 1)
        #expect(vm.search.selectedResultIndex == 0)
        #expect(vm.search.selectedResult == nil)
    }

    // MARK: - Escape ladder

    @Test func escapeClearsQueryThenClosesFolderThenHides() {
        let vm = makeVM(apps: [app("Mail")])
        vm.search.searchText = "m"
        vm.openFolderID = "folder"
        #expect(vm.handleEscape() == .clearedSearch)
        #expect(vm.search.searchText.isEmpty)
        #expect(vm.openFolderID == "folder")
        #expect(vm.handleEscape() == .closedFolder)
        #expect(vm.openFolderID == nil)
        #expect(vm.handleEscape() == .hideLauncher)
    }

    @Test func escapeClearsWhitespaceOnlyQuery() {
        let vm = makeVM()
        vm.search.searchText = " "
        #expect(vm.handleEscape() == .clearedSearch)
        #expect(vm.search.searchText.isEmpty)
    }

    // MARK: - show / hide

    @Test func hideClearsQuery() {
        let vm = makeVM(apps: [app("Mail")])
        vm.show()
        vm.search.searchText = "m"
        vm.hide()
        #expect(vm.search.searchText.isEmpty)
        #expect(vm.search.searchResults.isEmpty)
    }

    @Test func showRequestsSearchFocus() {
        let vm = makeVM()
        let before = vm.search.searchFocusRequest
        vm.show()
        #expect(vm.search.searchFocusRequest == before + 1)
    }
}
