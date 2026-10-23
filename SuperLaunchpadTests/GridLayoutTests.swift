import Foundation
import Testing
@testable import SuperLaunchpad

struct GridLayoutTests {

    private func app(
        _ bundleID: String,
        page: Int? = nil,
        order: Int? = nil,
        folderID: String? = nil,
        folderOrder: Int? = nil
    ) -> AppEntry {
        AppEntry(
            bundleIdentifier: bundleID,
            displayName: bundleID,
            appPath: "/Applications/\(bundleID).app",
            pageIndex: page,
            orderIndex: order,
            folderID: folderID,
            folderOrderIndex: folderOrder
        )
    }

    // Pages of app IDs; "#F" stands for folder "F".
    private func layout(_ pages: [[String]], folders: [String: [String]] = [:], capacity: Int = Grid.appsPerPage) -> GridLayout {
        GridLayout(
            pages: pages.map { $0.map(item) },
            folders: folders.mapValues { GridLayout.Folder(title: "Folder", appIDs: $0) },
            pageCapacity: capacity
        )
    }

    private func item(_ name: String) -> GridLayout.Item {
        name.hasPrefix("#") ? .folder(String(name.dropFirst())) : .app(name)
    }

    private func names(_ layout: GridLayout) -> [[String]] {
        layout.pages.map { page in
            page.map { item in
                switch item {
                case .app(let id): id
                case .folder(let id): "#" + id
                }
            }
        }
    }

    // MARK: - Building from rows

    @Test func initGroupsRowsByPageAndOrder() {
        let apps = [
            app("c", page: 2, order: 0),
            app("b", page: 0, order: 1),
            app("a", page: 0, order: 0),
            app("in2", folderID: "F", folderOrder: 1),
            app("in1", folderID: "F", folderOrder: 0),
            app("orphan", folderID: "missing", folderOrder: 0)
        ]
        let folders = [FolderEntry(id: "F", title: "Tools", pageIndex: 0, orderIndex: 2)]
        let layout = GridLayout(apps: apps, folders: folders)
        #expect(names(layout) == [["a", "b", "#F"], ["c"]])
        #expect(layout.folders["F"] == GridLayout.Folder(title: "Tools", appIDs: ["in1", "in2"]))
        #expect(layout.location(of: .app("orphan")) == nil)
    }

    @Test func initPutsUnpositionedAppsAtTheEndOfPageZero() {
        let layout = GridLayout(apps: [app("new"), app("a", page: 0, order: 0)], folders: [])
        #expect(names(layout) == [["a", "new"]])
    }

    @Test func locationFindsPageSlotsAndFolderMembers() {
        let layout = layout([["a", "#F"], ["b"]], folders: ["F": ["x", "y"]])
        #expect(layout.location(of: .app("b")) == .page(1, slot: 0))
        #expect(layout.location(of: .folder("F")) == .page(0, slot: 1))
        #expect(layout.location(of: .app("y")) == .folder("F", index: 1))
        #expect(layout.location(of: .app("nope")) == nil)
    }

    // MARK: - Move

    @Test(arguments: [
        ("a", 2, ["b", "c", "a", "d"]),
        ("d", 0, ["d", "a", "b", "c"]),
        ("b", 1, ["a", "b", "c", "d"]),
        ("b", 99, ["a", "c", "d", "b"])
    ])
    func moveWithinPage(id: String, slot: Int, expected: [String]) {
        var layout = layout([["a", "b", "c", "d"]])
        let moved = layout.move(.app(id), toPage: 0, slot: slot)
        #expect(moved)
        #expect(names(layout) == [expected])
    }

    @Test func moveAcrossPages() {
        var layout = layout([["a", "b"], ["c"]], capacity: 3)
        let moved = layout.move(.app("a"), toPage: 1, slot: 0)
        #expect(moved)
        #expect(names(layout) == [["b"], ["a", "c"]])
    }

    @Test func moveIntoFullPageSpillsOverflowAndCascades() {
        var layout = layout([["a", "b"], ["c", "d"], ["e"]], capacity: 2)
        let moved = layout.move(.app("e"), toPage: 0, slot: 0)
        #expect(moved)
        #expect(names(layout) == [["e", "a"], ["b", "c"], ["d"]])
    }

    @Test func moveSpillFillsGapLeftByMovedItem() {
        var layout = layout([["a", "b"], ["c", "d"]], capacity: 2)
        let moved = layout.move(.app("d"), toPage: 0, slot: 1)
        #expect(moved)
        #expect(names(layout) == [["a", "d"], ["b", "c"]])
    }

    @Test func moveSpillOpensNewLastPage() {
        var layout = layout([["a", "b"], ["c", "#F"]], folders: ["F": ["x"]], capacity: 2)
        let moved = layout.move(.app("x"), toPage: 0, slot: 0)
        #expect(moved)
        #expect(names(layout) == [["x", "a"], ["b", "c"], ["#F"]])
    }

    @Test func moveToPageCountOpensNewPage() {
        var layout = layout([["a", "b"]])
        let moved = layout.move(.app("a"), toPage: 1, slot: 0)
        #expect(moved)
        #expect(names(layout) == [["b"], ["a"]])
    }

    @Test func moveRemovesPageLeftEmpty() {
        var layout = layout([["a"], ["b"], ["c"]])
        let moved = layout.move(.app("a"), toPage: 2, slot: 1)
        #expect(moved)
        #expect(names(layout) == [["b"], ["c", "a"]])
    }

    @Test func moveFolderLikeAnApp() {
        var layout = layout([["a", "#F"]], folders: ["F": ["x"]])
        let moved = layout.move(.folder("F"), toPage: 0, slot: 0)
        #expect(moved)
        #expect(names(layout) == [["#F", "a"]])
        #expect(layout.folders["F"]?.appIDs == ["x"])
    }

    @Test func moveAppOutOfFolder() {
        var layout = layout([["a", "#F"]], folders: ["F": ["x", "y"]])
        let moved = layout.move(.app("x"), toPage: 0, slot: 1)
        #expect(moved)
        #expect(names(layout) == [["a", "x", "#F"]])
        #expect(layout.folders["F"]?.appIDs == ["y"])
    }

    @Test(arguments: [
        ("a", -1, 0),
        ("a", 2, 0),
        ("a", 0, -1),
        ("unknown", 0, 0)
    ])
    func moveRejectsInvalidTargets(id: String, page: Int, slot: Int) {
        var layout = layout([["a", "b"]])
        let before = layout
        let moved = layout.move(.app(id), toPage: page, slot: slot)
        #expect(moved == false)
        #expect(layout == before)
    }

    // MARK: - Merge

    @Test func mergeReplacesTargetWithNewFolder() {
        var layout = layout([["a", "b", "c"]])
        let merged = layout.merge("c", onto: "a", folderID: "N", title: "Games")
        #expect(merged)
        #expect(names(layout) == [["#N", "b"]])
        #expect(layout.folders["N"] == GridLayout.Folder(title: "Games", appIDs: ["a", "c"]))
    }

    @Test func mergeOntoLaterSlotOnSamePage() {
        var layout = layout([["a", "b", "c"]])
        let merged = layout.merge("a", onto: "c", folderID: "N", title: "Folder")
        #expect(merged)
        #expect(names(layout) == [["b", "#N"]])
    }

    @Test func mergeTakesAppOutOfAnotherFolder() {
        var layout = layout([["#F", "b"]], folders: ["F": ["x"]])
        let merged = layout.merge("x", onto: "b", folderID: "N", title: "Folder")
        #expect(merged)
        #expect(names(layout) == [["#F", "#N"]])
        #expect(layout.folders["F"]?.appIDs == [])
        #expect(layout.folders["N"]?.appIDs == ["b", "x"])
    }

    @Test(arguments: [
        ("a", "a", "N"),
        ("a", "x", "N"),
        ("a", "F", "N"),
        ("a", "b", "F"),
        ("nope", "b", "N"),
        ("a", "nope", "N")
    ])
    func mergeRejectsInvalidPairs(appID: String, target: String, folderID: String) {
        var layout = layout([["a", "b", "#F"]], folders: ["F": ["x"]])
        let before = layout
        let merged = layout.merge(appID, onto: target, folderID: folderID, title: "Folder")
        #expect(merged == false)
        #expect(layout == before)
    }

    // MARK: - Add / remove

    @Test(arguments: [
        (nil as Int?, ["x", "y", "a"]),
        (0, ["a", "x", "y"]),
        (1, ["x", "a", "y"]),
        (99, ["x", "y", "a"])
    ])
    func addTopLevelAppToFolder(index: Int?, expected: [String]) {
        var layout = layout([["a", "#F", "b"]], folders: ["F": ["x", "y"]])
        let added = layout.add("a", toFolder: "F", at: index)
        #expect(added)
        #expect(names(layout) == [["#F", "b"]])
        #expect(layout.folders["F"]?.appIDs == expected)
    }

    @Test func addWithinSameFolderReorders() {
        var layout = layout([["#F"]], folders: ["F": ["x", "y", "z"]])
        let added = layout.add("z", toFolder: "F", at: 0)
        #expect(added)
        #expect(layout.folders["F"]?.appIDs == ["z", "x", "y"])
    }

    @Test func addMovesAppBetweenFolders() {
        var layout = layout([["#F", "#G"]], folders: ["F": ["x"], "G": ["y"]])
        let added = layout.add("x", toFolder: "G")
        #expect(added)
        #expect(layout.folders["F"]?.appIDs == [])
        #expect(layout.folders["G"]?.appIDs == ["y", "x"])
    }

    @Test(arguments: [("G", "F"), ("a", "missing"), ("nope", "F")])
    func addRejectsFoldersAndUnknownIDs(id: String, folderID: String) {
        var layout = layout([["a", "#F", "#G"]], folders: ["F": ["x"], "G": ["y"]])
        let before = layout
        let added = layout.add(id, toFolder: folderID)
        #expect(added == false)
        #expect(layout == before)
    }

    @Test func removePlacesAppOnPage() {
        var layout = layout([["a", "#F"], ["b"]], folders: ["F": ["x", "y"]])
        let removed = layout.remove("y", fromFolder: "F", toPage: 1, slot: 0)
        #expect(removed)
        #expect(names(layout) == [["a", "#F"], ["y", "b"]])
        #expect(layout.folders["F"]?.appIDs == ["x"])
    }

    @Test func removeKeepsEmptiedFolderUntilDissolved() {
        var layout = layout([["#F"]], folders: ["F": ["x"]])
        let removed = layout.remove("x", fromFolder: "F", toPage: 0, slot: 1)
        #expect(removed)
        #expect(names(layout) == [["#F", "x"]])
        #expect(layout.folders["F"]?.appIDs == [])
    }

    @Test(arguments: [("x", "G"), ("a", "F"), ("nope", "F")])
    func removeRejectsAppNotInThatFolder(appID: String, folderID: String) {
        var layout = layout([["a", "#F", "#G"]], folders: ["F": ["x"], "G": ["y"]])
        let before = layout
        let removed = layout.remove(appID, fromFolder: folderID, toPage: 0, slot: 0)
        #expect(removed == false)
        #expect(layout == before)
    }

    // MARK: - Delete

    @Test func deleteClosesGapAndPullsNextPageForward() {
        var layout = layout([["a", "b"], ["c"]], capacity: 2)
        let deleted = layout.delete("a")
        #expect(deleted)
        #expect(names(layout) == [["b"], ["c"]])
    }

    @Test func deleteDropsPageLeftEmpty() {
        var layout = layout([["a"], ["b"]])
        let deleted = layout.delete("b")
        #expect(deleted)
        #expect(names(layout) == [["a"]])
    }

    @Test func deleteFromFolderKeepsEmptyFolderForDissolve() {
        var layout = layout([["#F", "a"]], folders: ["F": ["x"]])
        let deleted = layout.delete("x")
        #expect(deleted)
        #expect(layout.folders["F"]?.appIDs == [])
        layout.dissolveEmptyFolders()
        #expect(names(layout) == [["a"]])
    }

    @Test func deleteRejectsUnknownAppAndFolders() {
        var layout = layout([["#F", "a"]], folders: ["F": ["x"]])
        let before = layout
        let deletedMissing = layout.delete("missing")
        let deletedFolder = layout.delete("F")
        #expect(!deletedMissing)
        #expect(!deletedFolder)
        #expect(layout == before)
    }

    // MARK: - Dissolve / rename

    @Test func dissolveEmptyFoldersClosesGapsAndDropsEmptyPages() {
        var layout = layout([["a", "#E", "b"], ["#E2"], ["#F"]], folders: ["E": [], "E2": [], "F": ["x"]])
        layout.dissolveEmptyFolders()
        #expect(names(layout) == [["a", "b"], ["#F"]])
        #expect(Set(layout.folders.keys) == ["F"])
    }

    @Test func dissolveKeepsSingleAppFolders() {
        var layout = layout([["#F"]], folders: ["F": ["x"]])
        let before = layout
        layout.dissolveEmptyFolders()
        #expect(layout == before)
    }

    @Test(arguments: [
        ("Work", "Work"),
        ("  Games \n", "Games")
    ])
    func renameStoresTrimmedTitle(input: String, expected: String) {
        var layout = layout([["#F"]], folders: ["F": ["x"]])
        let renamed = layout.rename(folder: "F", to: input)
        #expect(renamed)
        #expect(layout.folders["F"]?.title == expected)
    }

    @Test(arguments: ["", "   ", "\n"])
    func renameRejectsBlankTitle(input: String) {
        var layout = layout([["#F"]], folders: ["F": ["x"]])
        let renamed = layout.rename(folder: "F", to: input)
        #expect(renamed == false)
        #expect(layout.folders["F"]?.title == "Folder")
    }

    @Test func renameRejectsUnknownFolder() {
        var layout = layout([["a"]])
        let renamed = layout.rename(folder: "F", to: "Work")
        #expect(renamed == false)
    }

    // MARK: - Disband / sort

    @Test func disbandPutsAppsInFolderPlaceInOrder() {
        var layout = layout([["a", "#F", "b"], ["c"]], folders: ["F": ["x", "y", "z"]])
        let disbanded = layout.disband("F")
        #expect(disbanded)
        #expect(names(layout) == [["a", "x", "y", "z", "b"], ["c"]])
        #expect(layout.folders["F"] == nil)
    }

    @Test func disbandOnFullPageSpillsOverflowOntoNextPages() {
        var layout = layout([["a", "#F", "b"], ["c", "d", "e"]], folders: ["F": ["x", "y"]], capacity: 3)
        let disbanded = layout.disband("F")
        #expect(disbanded)
        #expect(names(layout) == [["a", "x", "y"], ["b", "c", "d"], ["e"]])
    }

    @Test func disbandEmptyFolderClosesGapAndDropsEmptyPage() {
        var layout = layout([["a"], ["#E"]], folders: ["E": []])
        let disbanded = layout.disband("E")
        #expect(disbanded)
        #expect(names(layout) == [["a"]])
    }

    @Test func disbandRejectsUnknownFolderAndApps() {
        var layout = layout([["a", "#F"]], folders: ["F": ["x"]])
        let before = layout
        let disbandedMissing = layout.disband("missing")
        let disbandedApp = layout.disband("a")
        #expect(!disbandedMissing)
        #expect(!disbandedApp)
        #expect(layout == before)
    }

    @Test func sortFolderReordersOnlyThatFolder() {
        var layout = layout([["#F", "#G"]], folders: ["F": ["c", "a", "b"], "G": ["z", "y"]])
        let sorted = layout.sortFolder("F", by: <)
        #expect(sorted)
        #expect(layout.folders["F"]?.appIDs == ["a", "b", "c"])
        #expect(layout.folders["G"]?.appIDs == ["z", "y"])
        #expect(names(layout) == [["#F", "#G"]])
    }

    @Test func sortRejectsUnknownFolder() {
        var layout = layout([["a"]])
        let sorted = layout.sortFolder("F", by: <)
        #expect(!sorted)
    }

    // MARK: - Apply

    @Test func applyWritesDensePositionsAndKeepsInvariant() throws {
        let apps = [
            app("a", page: 0, order: 3),
            app("b", page: 4, order: 9),
            app("x", folderID: "F", folderOrder: 7),
            app("y", folderID: "F", folderOrder: 2),
            app("stray", folderID: "missing", folderOrder: 0)
        ]
        let folders = [
            FolderEntry(id: "F", title: "Old", pageIndex: 4, orderIndex: 0),
            FolderEntry(id: "Gone", title: "Gone", pageIndex: 0, orderIndex: 0)
        ]
        var layout = GridLayout(apps: apps, folders: folders)
        layout.folders["Gone"] = nil
        layout.pages = layout.pages.map { $0.filter { $0 != .folder("Gone") } }
        let merged = layout.merge("b", onto: "a", folderID: "N", title: "New")
        #expect(merged)
        let renamed = layout.rename(folder: "F", to: "Tools")
        #expect(renamed)

        let result = layout.apply(to: apps, folders: folders)
        let byID = Dictionary(uniqueKeysWithValues: result.apps.map { ($0.id, $0) })

        #expect(result.folders == [
            FolderEntry(id: "N", title: "New", pageIndex: 0, orderIndex: 0),
            FolderEntry(id: "F", title: "Tools", pageIndex: 1, orderIndex: 0)
        ])
        let a = try #require(byID["a"])
        #expect(a.folderID == "N" && a.folderOrderIndex == 0)
        #expect(a.pageIndex == nil && a.orderIndex == nil)
        #expect(byID["b"]?.folderOrderIndex == 1)
        #expect(byID["y"]?.folderOrderIndex == 0)
        #expect(byID["x"]?.folderOrderIndex == 1)
        #expect(byID["stray"] == apps[4])
        for app in result.apps where app.folderID != nil {
            #expect(app.pageIndex == nil && app.orderIndex == nil)
        }
    }

    @Test func applyMovesFolderAppBackToPage() {
        let apps = [app("a", page: 0, order: 0), app("x", folderID: "F", folderOrder: 0)]
        let folders = [FolderEntry(id: "F", title: "F", pageIndex: 0, orderIndex: 1)]
        var layout = GridLayout(apps: apps, folders: folders)
        let moved = layout.move(.app("x"), toPage: 0, slot: 0)
        #expect(moved)
        layout.dissolveEmptyFolders()
        let result = layout.apply(to: apps, folders: folders)
        #expect(result.folders.isEmpty)
        #expect(result.apps == [
            app("a", page: 0, order: 1),
            app("x", page: 0, order: 0)
        ])
    }

    @Test func applyOfUnchangedLayoutRoundTrips() {
        let apps = (0..<40).map { app("app\($0)", page: $0 / Grid.appsPerPage, order: $0 % Grid.appsPerPage) }
        let layout = GridLayout(apps: apps, folders: [])
        #expect(layout.pages.map(\.count) == [Grid.appsPerPage, 5])
        let result = layout.apply(to: apps, folders: [])
        #expect(result.apps == apps)
        #expect(GridLayout(apps: result.apps, folders: result.folders) == layout)
    }
}
