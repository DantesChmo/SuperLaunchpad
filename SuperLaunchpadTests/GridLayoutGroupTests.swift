import Testing
@testable import SuperLaunchpad

// The group operations behind multi-select: several apps leave their pages
// and folders and land together.
struct GridLayoutGroupTests {

    private func apps(_ ids: String...) -> [GridLayout.Item] {
        ids.map { .app($0) }
    }

    // Page 0: a b F(x y) c — page 1: d e.
    private func layout(pageCapacity: Int = 35) -> GridLayout {
        GridLayout(
            pages: [apps("a", "b") + [.folder("F")] + apps("c"), apps("d", "e")],
            folders: ["F": .init(title: "Tools", appIDs: ["x", "y"])],
            pageCapacity: pageCapacity
        )
    }

    // MARK: - Order

    @Test func orderedFollowsPagesAndFolderTiles() {
        #expect(layout().ordered(["e", "y", "a", "c", "x"]) == ["a", "x", "y", "c", "e"])
    }

    @Test func orderedSkipsAppsNotInTheLayout() {
        #expect(layout().ordered(["a", "gone"]) == ["a"])
    }

    // MARK: - moveGroup

    @Test func moveGroupOnTheSamePageLandsConsecutivelyAtTheSlot() {
        var l = layout()
        // Slot 1 of the page without c and a: b F → between b and F.
        let done1 = l.moveGroup(["c", "a"], toPage: 0, slot: 1)
        #expect(done1)
        #expect(l.pages == [apps("b", "c", "a") + [.folder("F")], apps("d", "e")])
    }

    @Test func moveGroupGathersAppsFromOtherPagesAndFolders() {
        var l = layout()
        let done2 = l.moveGroup(["e", "x"], toPage: 0, slot: 0)
        #expect(done2)
        #expect(l.pages == [apps("e", "x", "a", "b") + [.folder("F")] + apps("c"), apps("d")])
        #expect(l.folders["F"]?.appIDs == ["y"])
    }

    @Test func moveGroupToAnotherPage() {
        var l = layout()
        let done3 = l.moveGroup(["a", "c"], toPage: 1, slot: 1)
        #expect(done3)
        #expect(l.pages == [apps("b") + [.folder("F")], apps("d", "a", "c", "e")])
    }

    @Test func moveGroupOverflowSpillsOntoTheNextPage() {
        var l = layout(pageCapacity: 4)
        let done4 = l.moveGroup(["d", "e"], toPage: 0, slot: 0)
        #expect(done4)
        #expect(l.pages == [apps("d", "e", "a", "b"), [.folder("F")] + apps("c")])
    }

    @Test func moveGroupOverflowCascadesAcrossFullPages() {
        var l = GridLayout(pages: [apps("a", "b"), apps("c", "d"), apps("e")], pageCapacity: 2)
        let done5 = l.moveGroup(["e", "d"], toPage: 0, slot: 1)
        #expect(done5)
        #expect(l.pages == [apps("a", "e"), apps("d", "b"), apps("c")])
    }

    @Test func moveGroupPastTheLastPageOpensANewPage() {
        var l = layout()
        let done6 = l.moveGroup(["a", "x"], toPage: 2, slot: 0)
        #expect(done6)
        #expect(l.pages.count == 3)
        #expect(l.pages[2] == apps("a", "x"))
    }

    @Test func moveGroupEmptyingAPageClosesIt() {
        var l = layout()
        let done7 = l.moveGroup(["d", "e"], toPage: 0, slot: 4)
        #expect(done7)
        #expect(l.pages == [apps("a", "b") + [.folder("F")] + apps("c", "d", "e")])
    }

    @Test func moveGroupRejectsBadInput() {
        var l = layout()
        let refused8 = l.moveGroup([], toPage: 0, slot: 0)
        #expect(!refused8)
        let refused9 = l.moveGroup(["a", "a"], toPage: 0, slot: 0)
        #expect(!refused9)
        let refused10 = l.moveGroup(["a", "gone"], toPage: 0, slot: 0)
        #expect(!refused10)
        let refused11 = l.moveGroup(["a"], toPage: 3, slot: 0)
        #expect(!refused11)
        let refused12 = l.moveGroup(["a"], toPage: 0, slot: -1)
        #expect(!refused12)
        #expect(l == layout())
    }

    // MARK: - addGroup

    @Test func addGroupAppendsToTheFolder() {
        var l = layout()
        let done13 = l.addGroup(["c", "d"], toFolder: "F")
        #expect(done13)
        #expect(l.folders["F"]?.appIDs == ["x", "y", "c", "d"])
        #expect(l.pages == [apps("a", "b") + [.folder("F")], apps("e")])
    }

    @Test func addGroupInsertsAtTheIndexCountedWithoutThem() {
        var l = layout()
        // Reordering inside the folder: y and a in front of x.
        let done14 = l.addGroup(["y", "a"], toFolder: "F", at: 0)
        #expect(done14)
        #expect(l.folders["F"]?.appIDs == ["y", "a", "x"])
    }

    @Test func addGroupRejectsAnUnknownFolder() {
        var l = layout()
        let refused15 = l.addGroup(["a"], toFolder: "nope")
        #expect(!refused15)
        #expect(l == layout())
    }

    // MARK: - mergeGroup

    @Test func mergeGroupMakesAFolderInTheTargetsPlace() {
        var l = layout()
        let done16 = l.mergeGroup(["d", "a"], onto: "c", folderID: "N", title: "New")
        #expect(done16)
        #expect(l.pages == [apps("b") + [.folder("F"), .folder("N")], apps("e")])
        #expect(l.folders["N"] == .init(title: "New", appIDs: ["c", "d", "a"]))
    }

    @Test func mergeGroupRejectsATargetInTheGroupOrInAFolder() {
        var l = layout()
        let refused17 = l.mergeGroup(["a", "c"], onto: "c", folderID: "N", title: "New")
        #expect(!refused17)
        let refused18 = l.mergeGroup(["a"], onto: "x", folderID: "N", title: "New")
        #expect(!refused18)
        let refused19 = l.mergeGroup(["a"], onto: "c", folderID: "F", title: "New")
        #expect(!refused19)
        #expect(l == layout())
    }

    // MARK: - makeFolder

    @Test func makeFolderTakesThePlaceOfTheFirstAppOnAPage() {
        var l = layout()
        let done20 = l.makeFolder(["x", "c", "e"], folderID: "N", title: "New")
        #expect(done20)
        // x is in a folder, so c (the first one on a page) gives its slot.
        #expect(l.pages == [apps("a", "b") + [.folder("F"), .folder("N")], apps("d")])
        #expect(l.folders["N"]?.appIDs == ["x", "c", "e"])
        #expect(l.folders["F"]?.appIDs == ["y"])
    }

    @Test func makeFolderFromFolderAppsGoesAfterTheFirstOnesFolder() {
        var l = layout()
        let done21 = l.makeFolder(["x", "y"], folderID: "N", title: "New")
        #expect(done21)
        l.dissolveEmptyFolders()
        #expect(l.pages == [apps("a", "b") + [.folder("N")] + apps("c"), apps("d", "e")])
        #expect(l.folders["N"]?.appIDs == ["x", "y"])
        #expect(l.folders["F"] == nil)
    }

    @Test func makeFolderOfOneApp() {
        var l = layout()
        let done22 = l.makeFolder(["b"], folderID: "N", title: "New")
        #expect(done22)
        #expect(l.pages[0] == apps("a") + [.folder("N"), .folder("F")] + apps("c"))
        #expect(l.folders["N"]?.appIDs == ["b"])
    }
}
