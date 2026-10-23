import Foundation
import Testing
@testable import SuperLaunchpad

@MainActor
struct HiddenAppsTests {

    private func makeTempDB() throws -> (AppDatabase, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("test.db").path
        return (try AppDatabase(path: path), dir)
    }

    private func app(
        _ bundleID: String,
        name: String? = nil,
        page: Int? = nil,
        order: Int? = nil,
        folderID: String? = nil,
        folderOrder: Int? = nil,
        hidden: Bool = false
    ) -> AppEntry {
        var entry = AppEntry(
            bundleIdentifier: bundleID,
            displayName: name ?? bundleID,
            appPath: "/Applications/\(bundleID).app",
            pageIndex: page,
            orderIndex: order,
            folderID: folderID,
            folderOrderIndex: folderOrder
        )
        entry.isHidden = hidden
        return entry
    }

    // Page 0: a, folder F(x, y, z), b. Page 1: c.
    private func makeViewModel(_ db: AppDatabase?) throws -> LaunchpadViewModel {
        let folders = [FolderEntry(id: "F", title: "Tools", pageIndex: 0, orderIndex: 1)]
        let apps = [
            app("a", page: 0, order: 0),
            app("b", page: 0, order: 2),
            app("c", page: 1, order: 0),
            app("x", folderID: "F", folderOrder: 0),
            app("y", folderID: "F", folderOrder: 1),
            app("z", folderID: "F", folderOrder: 2)
        ]
        try db?.saveFolders(folders)
        try db?.saveApps(apps)
        let vm = LaunchpadViewModel(database: db)
        vm.folders = folders
        vm.apps = apps
        return vm
    }

    private func entry(_ vm: LaunchpadViewModel, _ id: String) throws -> AppEntry {
        try #require(vm.apps.first { $0.bundleIdentifier == id })
    }

    private func pageIDs(_ vm: LaunchpadViewModel) -> [[String]] {
        vm.pages.map { $0.map(\.id) }
    }

    // MARK: - Hide

    @Test func hideTakesAppOffTheGridAndClosesTheGap() throws {
        let vm = try makeViewModel(nil)

        #expect(vm.hideApp("a"))

        #expect(pageIDs(vm) == [["F", "b"], ["c"]])
        let hidden = try entry(vm, "a")
        #expect(hidden.isHidden)
        #expect(hidden.pageIndex == nil && hidden.orderIndex == nil)
        #expect(hidden.folderID == nil && hidden.folderOrderIndex == nil)
        #expect(try entry(vm, "b").orderIndex == 1)
    }

    @Test func hideOnlyAppOfAPageDropsThePage() throws {
        let vm = try makeViewModel(nil)

        #expect(vm.hideApp("c"))

        #expect(pageIDs(vm) == [["a", "F", "b"]])
    }

    @Test func hidePersists() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)

        #expect(vm.hideApp("a"))

        let stored = try db.fetchAllApps()
        let hidden = try #require(stored.first { $0.bundleIdentifier == "a" })
        #expect(hidden.isHidden)
        #expect(hidden.pageIndex == nil)
        #expect(stored.first { $0.bundleIdentifier == "b" }?.orderIndex == 1)
    }

    @Test func hideFolderMemberShrinksTheFolder() throws {
        let vm = try makeViewModel(nil)

        #expect(vm.hideApp("y"))

        #expect(vm.folderApps("F").map(\.bundleIdentifier) == ["x", "z"])
        #expect(try entry(vm, "z").folderOrderIndex == 1)
        let tile = try #require(vm.pages.first?.first { $0.id == "F" })
        guard case .folder(_, let members) = tile else {
            Issue.record("F is not a folder tile")
            return
        }
        #expect(members.map(\.bundleIdentifier) == ["x", "z"])
    }

    @Test func hideLastFolderMemberDissolvesTheFolder() throws {
        let vm = LaunchpadViewModel(database: nil)
        vm.folders = [FolderEntry(id: "F", title: "Tools", pageIndex: 0, orderIndex: 1)]
        vm.apps = [app("a", page: 0, order: 0), app("x", folderID: "F", folderOrder: 0), app("b", page: 0, order: 2)]
        vm.openFolder(try #require(vm.folders.first))

        #expect(vm.hideApp("x"))

        #expect(vm.folders.isEmpty)
        #expect(pageIDs(vm) == [["a", "b"]])
        #expect(vm.openFolderID == nil)
    }

    @Test(arguments: ["missing", "hidden"])
    func hideRejectsUnknownOrHiddenApp(appID: String) throws {
        let vm = try makeViewModel(nil)
        vm.apps.append(app("hidden", hidden: true))
        let before = vm.apps

        #expect(!vm.hideApp(appID))

        #expect(vm.apps == before)
    }

    // MARK: - Unhide

    @Test func unhidePutsAppAfterTheLastItem() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        #expect(vm.hideApp("a"))

        #expect(vm.unhideApp("a"))

        #expect(pageIDs(vm) == [["F", "b"], ["c", "a"]])
        let shown = try entry(vm, "a")
        #expect(!shown.isHidden)
        #expect(shown.pageIndex == 1 && shown.orderIndex == 1)
        let stored = try #require(try db.fetchAllApps().first { $0.bundleIdentifier == "a" })
        #expect(!stored.isHidden)
        #expect(stored.pageIndex == 1 && stored.orderIndex == 1)
    }

    @Test func unhideOntoFullLastPageOpensNewPage() throws {
        let vm = LaunchpadViewModel(database: nil)
        vm.apps = (0..<Grid.appsPerPage).map { app("app\($0)", page: 0, order: $0) } + [app("h", hidden: true)]

        #expect(vm.unhideApp("h"))

        #expect(vm.pages.count == 2)
        #expect(pageIDs(vm)[1] == ["h"])
    }

    @Test func unhideIntoEmptyGrid() throws {
        let vm = LaunchpadViewModel(database: nil)
        vm.apps = [app("h", hidden: true)]
        #expect(vm.pages.isEmpty)

        #expect(vm.unhideApp("h"))

        #expect(pageIDs(vm) == [["h"]])
    }

    @Test(arguments: ["missing", "a"])
    func unhideRejectsUnknownOrShownApp(appID: String) throws {
        let vm = try makeViewModel(nil)
        let before = vm.apps

        #expect(!vm.unhideApp(appID))

        #expect(vm.apps == before)
    }

    @Test func hiddenAppsAreSortedByName() throws {
        let vm = try makeViewModel(nil)
        vm.apps += [app("h1", name: "zebra", hidden: true), app("h2", name: "Émile", hidden: true), app("h3", name: "apple", hidden: true)]

        #expect(vm.hiddenApps.map(\.displayName) == ["apple", "Émile", "zebra"])
    }

    // MARK: - Menu

    @Test func menuHidesAndUnhides() throws {
        let vm = try makeViewModel(nil)

        #expect(vm.menuItems(for: try entry(vm, "a")).joined().contains { $0.action == .hide })
        #expect(!vm.perform(.hide, on: try entry(vm, "a")))
        #expect(try entry(vm, "a").isHidden)

        #expect(vm.menuItems(for: try entry(vm, "a")).joined().contains { $0.action == .unhide })
        #expect(!vm.perform(.unhide, on: try entry(vm, "a")))
        #expect(try entry(vm, "a").isHidden == false)
    }

    // MARK: - Search

    @Test func searchFindsHiddenAppMarkedHidden() throws {
        let vm = try makeViewModel(nil)
        vm.apps.append(app("com.secret", name: "Secret Agent", hidden: true))

        vm.searchText = "secret"

        let result = try #require(vm.searchResults.first?.appEntry)
        #expect(vm.searchResults.count == 1)
        #expect(result.bundleIdentifier == "com.secret")
        #expect(result.isHidden)
    }

    @Test func searchResultFollowsHideAndUnhide() throws {
        let vm = try makeViewModel(nil)
        vm.searchText = "a"
        #expect(vm.searchResults.first { $0.id == "a" }?.appEntry?.isHidden == false)

        #expect(vm.hideApp("a"))
        #expect(vm.searchResults.first { $0.id == "a" }?.appEntry?.isHidden == true)

        #expect(vm.unhideApp("a"))
        #expect(vm.searchResults.first { $0.id == "a" }?.appEntry?.isHidden == false)
    }

    // MARK: - Rescan

    @Test func rescanKeepsHiddenAppHiddenAndOffTheGrid() throws {
        let existing = [app("a", page: 0, order: 0), app("h", name: "Old", hidden: true)]
        let enumerated = [app("a"), app("h", name: "New"), app("n")]

        let (merged, _) = LaunchpadViewModel.mergeNewApps(
            enumerated,
            existingApps: existing,
            existingFolders: [],
            systemOrdering: nil,
            folderImportDone: true
        )

        let hidden = try #require(merged.first { $0.bundleIdentifier == "h" })
        #expect(hidden.isHidden)
        #expect(hidden.displayName == "New")
        #expect(hidden.pageIndex == nil && hidden.folderID == nil)
        // The new app goes after the visible ones; the hidden app holds no slot.
        let new = try #require(merged.first { $0.bundleIdentifier == "n" })
        #expect(new.pageIndex == 0 && new.orderIndex == 1)
    }

    @Test func folderReimportLeavesHiddenAppOut() throws {
        let existing = [app("a", page: 0, order: 0), app("h", hidden: true)]
        let ordering = LaunchpadOrdering(
            appPositions: [:],
            folders: [
                FolderInfo(
                    title: "Utilities",
                    pageIndex: 0,
                    orderIndex: 1,
                    appBundleIDs: [(bundleID: "a", orderIndex: 0), (bundleID: "h", orderIndex: 1)]
                )
            ]
        )

        let (merged, folders) = LaunchpadViewModel.mergeNewApps(
            [app("a"), app("h")],
            existingApps: existing,
            existingFolders: [],
            systemOrdering: ordering,
            folderImportDone: false
        )

        #expect(folders.count == 1)
        #expect(merged.first { $0.bundleIdentifier == "a" }?.folderID == folders.first?.id)
        let hidden = try #require(merged.first { $0.bundleIdentifier == "h" })
        #expect(hidden.isHidden)
        #expect(hidden.folderID == nil)
    }

    @Test func rescanResultKeepsHiddenAppsOffTheGrid() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        #expect(vm.hideApp("y"))

        // Next launch: what a rescan reads back from the DB after its merge.
        let relaunched = LaunchpadViewModel(database: db)
        relaunched.receiveRescanResult(apps: try db.fetchAllApps(), folders: try db.fetchAllFolders(), startRevision: 0)

        #expect(try entry(relaunched, "y").isHidden)
        #expect(relaunched.folderApps("F").map(\.bundleIdentifier) == ["x", "z"])
        #expect(!relaunched.pages.joined().contains { $0.id == "y" })
    }
}
