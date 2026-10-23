import Foundation
import Testing
@testable import SuperLaunchpad

@MainActor
struct EditingModelDragTests {

    private func makeTempDB() throws -> (AppDatabase, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("test.db").path
        return (try AppDatabase(path: path), dir)
    }

    private func app(_ bundleID: String, order: Int) -> AppEntry {
        AppEntry(
            bundleIdentifier: bundleID,
            displayName: bundleID,
            appPath: "/Applications/\(bundleID).app",
            pageIndex: 0,
            orderIndex: order
        )
    }

    private func makeViewModel(_ db: AppDatabase) throws -> LaunchpadViewModel {
        let apps = [app("a", order: 0), app("b", order: 1)]
        try db.saveApps(apps)
        let vm = LaunchpadViewModel(database: db)
        vm.apps = apps
        return vm
    }

    private func pageIDs(_ vm: LaunchpadViewModel) -> [[String]] {
        vm.pages.map { $0.map(\.id) }
    }

    @Test func rescanResultAppliesImmediatelyWithoutDrag() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)

        vm.receiveRescanResult(apps: [app("a", order: 0), app("b", order: 1), app("c", order: 2)], folders: [], startRevision: 0)

        #expect(pageIDs(vm) == [["a", "b", "c"]])
    }

    @Test func rescanResultIsParkedDuringDragAndAppliedAfter() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)

        vm.editing.beginDragSession()
        vm.receiveRescanResult(apps: [app("a", order: 0), app("b", order: 1), app("c", order: 2)], folders: [], startRevision: 0)
        #expect(pageIDs(vm) == [["a", "b"]])

        vm.editing.endDragSession()
        #expect(!vm.editing.isDragSessionActive)
        #expect(pageIDs(vm) == [["a", "b", "c"]])
    }

    @Test func endDragSessionIsIdempotent() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)

        vm.editing.beginDragSession()
        vm.editing.endDragSession()
        vm.editing.endDragSession()

        #expect(!vm.editing.isDragSessionActive)
        #expect(pageIDs(vm) == [["a", "b"]])
    }

    @Test func dropDuringDragPersistsTheMove() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)

        vm.editing.beginDragSession()
        #expect(vm.editing.moveItem(.app("b"), toPage: 0, slot: 0))
        vm.editing.endDragSession()

        #expect(pageIDs(vm) == [["b", "a"]])
        let stored = try db.fetchAllApps().sorted { ($0.orderIndex ?? 0) < ($1.orderIndex ?? 0) }
        #expect(stored.map(\.bundleIdentifier) == ["b", "a"])
    }

    @Test func escapeCancelsDragBeforeQueryAndFolder() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        vm.search.searchText = "a"
        vm.editing.beginDragSession()
        let request = vm.editing.dragCancelRequest

        #expect(vm.handleEscape() == .cancelledDrag)
        #expect(vm.editing.dragCancelRequest == request + 1)
        #expect(vm.search.searchText == "a")

        vm.editing.endDragSession()
        #expect(vm.handleEscape() == .clearedSearch)
    }
}
