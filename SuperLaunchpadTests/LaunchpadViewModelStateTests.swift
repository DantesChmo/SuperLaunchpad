import Foundation
import Testing
@testable import SuperLaunchpad

@MainActor
struct LaunchpadViewModelStateTests {

    private func makeVM() -> LaunchpadViewModel {
        // Inject nil database to avoid touching the real user filesystem
        LaunchpadViewModel(database: nil)
    }

    private func app(
        _ bundleID: String,
        page: Int? = nil,
        order: Int? = nil,
        folderID: String? = nil,
        folderOrder: Int? = nil,
        name: String? = nil
    ) -> AppEntry {
        AppEntry(
            bundleIdentifier: bundleID,
            displayName: name ?? bundleID,
            appPath: "/Applications/\(bundleID).app",
            iconData: nil,
            pageIndex: page,
            orderIndex: order,
            folderID: folderID,
            folderOrderIndex: folderOrder
        )
    }

    // MARK: - show / hide / toggle

    @Test func showSetsVisibleAndResetsPage() {
        let vm = makeVM()
        vm.currentPage = 3
        vm.show()
        #expect(vm.isVisible == true)
        #expect(vm.currentPage == 0)
    }

    @Test func hideClearsVisibilityAndOpenFolder() {
        let vm = makeVM()
        vm.isVisible = true
        vm.openFolderID = "some-id"
        vm.hide()
        #expect(vm.isVisible == false)
        #expect(vm.openFolderID == nil)
    }

    @Test func toggleFromHiddenShowsAndResetsPage() {
        let vm = makeVM()
        vm.isVisible = false
        vm.currentPage = 5
        vm.toggle()
        #expect(vm.isVisible == true)
        #expect(vm.currentPage == 0)
    }

    @Test func toggleFromVisibleHides() {
        let vm = makeVM()
        vm.isVisible = true
        vm.openFolderID = "x"
        vm.toggle()
        #expect(vm.isVisible == false)
        #expect(vm.openFolderID == nil)
    }

    // MARK: - openFolder / closeFolder

    @Test func openFolderSetsID() {
        let vm = makeVM()
        let folder = FolderEntry(id: "fld-1", title: "F", pageIndex: 0, orderIndex: 0)
        vm.openFolder(folder)
        #expect(vm.openFolderID == "fld-1")
    }

    @Test func closeFolderClearsID() {
        let vm = makeVM()
        vm.openFolderID = "anything"
        vm.closeFolder()
        #expect(vm.openFolderID == nil)
    }

    @Test func openFolderComputedReturnsMatchingEntry() {
        let vm = makeVM()
        let folder = FolderEntry(id: "fld-1", title: "F", pageIndex: 0, orderIndex: 0)
        vm.folders = [folder]
        vm.openFolderID = "fld-1"
        #expect(vm.openFolder == folder)
    }

    @Test func openFolderComputedNilWhenNoID() {
        let vm = makeVM()
        vm.folders = [FolderEntry(id: "fld-1", title: "F", pageIndex: 0, orderIndex: 0)]
        vm.openFolderID = nil
        #expect(vm.openFolder == nil)
    }

    @Test func openFolderComputedNilWhenIDNotFound() {
        let vm = makeVM()
        vm.folders = [FolderEntry(id: "fld-1", title: "F", pageIndex: 0, orderIndex: 0)]
        vm.openFolderID = "missing"
        #expect(vm.openFolder == nil)
    }

    // MARK: - openFolderApps

    @Test func openFolderAppsFiltersAndSorts() {
        let vm = makeVM()
        vm.apps = [
            app("a", folderID: "f1", folderOrder: 2),
            app("b", folderID: "f1", folderOrder: 0),
            app("c", folderID: "f2", folderOrder: 0),
            app("d", page: 0, order: 0),
            app("e", folderID: "f1", folderOrder: 1)
        ]
        vm.openFolderID = "f1"
        let result = vm.openFolderApps
        #expect(result.map(\.bundleIdentifier) == ["b", "e", "a"])
    }

    @Test func openFolderAppsEmptyWhenNoneOpen() {
        let vm = makeVM()
        vm.apps = [app("a", folderID: "f1", folderOrder: 0)]
        vm.openFolderID = nil
        #expect(vm.openFolderApps.isEmpty)
    }

    // MARK: - pages

    @Test func pagesEmptyWhenNoData() {
        let vm = makeVM()
        #expect(vm.pages.isEmpty)
    }

    @Test func pagesGroupedByPageIndexAndSortedByOrder() {
        let vm = makeVM()
        vm.apps = [
            app("p0-2", page: 0, order: 2),
            app("p1-0", page: 1, order: 0),
            app("p0-0", page: 0, order: 0),
            app("p0-1", page: 0, order: 1),
            app("p1-1", page: 1, order: 1)
        ]
        let pages = vm.pages
        #expect(pages.count == 2)
        #expect(pages[0].map(\.id) == ["p0-0", "p0-1", "p0-2"])
        #expect(pages[1].map(\.id) == ["p1-0", "p1-1"])
    }

    @Test func pagesMixesAppsAndFoldersWithCorrectSort() {
        let vm = makeVM()
        vm.apps = [
            app("a", page: 0, order: 0),
            app("b", page: 0, order: 2)
        ]
        vm.folders = [
            FolderEntry(id: "fld", title: "Utils", pageIndex: 0, orderIndex: 1)
        ]
        let pages = vm.pages
        #expect(pages.count == 1)
        #expect(pages[0].map(\.id) == ["a", "fld", "b"])
    }

    @Test func pagesFolderItemContainsAppsSortedByFolderOrderIndex() {
        let vm = makeVM()
        vm.apps = [
            app("inner-2", folderID: "fld", folderOrder: 2),
            app("inner-0", folderID: "fld", folderOrder: 0),
            app("inner-1", folderID: "fld", folderOrder: 1)
        ]
        vm.folders = [FolderEntry(id: "fld", title: "F", pageIndex: 0, orderIndex: 0)]
        let pages = vm.pages
        #expect(pages.count == 1)
        guard case .folder(_, let folderApps) = pages[0][0] else {
            Issue.record("Expected first item to be a folder")
            return
        }
        #expect(folderApps.map(\.bundleIdentifier) == ["inner-0", "inner-1", "inner-2"])
    }

    @Test func pagesExcludesFolderAppsFromTopLevel() {
        let vm = makeVM()
        vm.apps = [
            app("top", page: 0, order: 0),
            app("hidden-in-folder", folderID: "fld", folderOrder: 0)
        ]
        vm.folders = [FolderEntry(id: "fld", title: "F", pageIndex: 0, orderIndex: 1)]
        let pages = vm.pages
        #expect(pages[0].count == 2)
        let topLevelAppIDs: [String] = pages[0].compactMap {
            if case .app(let entry) = $0 { return entry.bundleIdentifier }
            return nil
        }
        #expect(topLevelAppIDs == ["top"])
    }
}
