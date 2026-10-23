import Foundation
import Testing
@testable import SuperLaunchpad

@MainActor
struct LayoutResetTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func app(
        _ bundleID: String,
        page: Int? = nil,
        order: Int? = nil,
        folderID: String? = nil,
        folderOrder: Int? = nil,
        hidden: Bool = false
    ) -> AppEntry {
        var entry = AppEntry(
            bundleIdentifier: bundleID,
            displayName: bundleID,
            appPath: "/Applications/\(bundleID).app",
            pageIndex: page,
            orderIndex: order,
            folderID: folderID,
            folderOrderIndex: folderOrder
        )
        entry.isHidden = hidden
        return entry
    }

    private func entry(_ apps: [AppEntry], _ id: String) throws -> AppEntry {
        try #require(apps.first { $0.bundleIdentifier == id })
    }

    // Current layout: page 0: folder Mine(d, b), c, a. Hidden: h.
    private let folders = [FolderEntry(id: "F", title: "Mine", pageIndex: 0, orderIndex: 0)]
    private var apps: [AppEntry] {
        [
            app("d", folderID: "F", folderOrder: 0),
            app("b", folderID: "F", folderOrder: 1),
            app("c", page: 0, order: 1),
            app("a", page: 0, order: 2),
            app("h", hidden: true)
        ]
    }

    private func categoryOf(_ app: AppEntry) -> AppCategory {
        ["a": .games, "c": .games][app.bundleIdentifier] ?? .uncategorized
    }

    private func layout(_ result: (apps: [AppEntry], folders: [FolderEntry])) -> LayoutFile {
        LayoutFile(apps: result.apps, folders: result.folders)
    }

    // MARK: - Modes

    @Test func alphabeticalHasNoFolders() {
        let result = LayoutReset.build(.alphabetical, apps: apps, systemOrdering: nil, categoryOf: categoryOf)
        #expect(result.folders.isEmpty)
        #expect(layout(result).pages == [[.app("a"), .app("b"), .app("c"), .app("d")]])
    }

    @Test func alphabeticalFillsPages() throws {
        let ids = (0..<(Grid.appsPerPage + 2)).map { String(format: "app%03d", $0) }
        let result = LayoutReset.build(.alphabetical, apps: ids.map { app($0) }, systemOrdering: nil, categoryOf: categoryOf)
        let last = try entry(result.apps, ids[ids.count - 1])
        #expect(last.pageIndex == 1 && last.orderIndex == 1)
        #expect(try entry(result.apps, ids[0]).orderIndex == 0)
    }

    @Test func categoriesGroupLikeFirstRun() {
        let result = LayoutReset.build(.categories, apps: apps, systemOrdering: nil, categoryOf: categoryOf)
        #expect(layout(result).pages == [[
            .folder(title: AppCategory.games.folderTitle, apps: ["a", "c"]), .app("b"), .app("d")
        ]])
    }

    @Test func systemLaunchpadUsesItsOrderAndAppendsTheRest() {
        let ordering = LaunchpadOrdering(
            appPositions: ["c": (pageIndex: 0, orderIndex: 5), "notInstalled": (pageIndex: 0, orderIndex: 6)],
            folders: [
                FolderInfo(title: "Work", pageIndex: 0, orderIndex: 2, appBundleIDs: [(bundleID: "d", orderIndex: 0), (bundleID: "a", orderIndex: 1)]),
                FolderInfo(title: "Gone", pageIndex: 1, orderIndex: 0, appBundleIDs: [(bundleID: "notInstalled2", orderIndex: 0)])
            ]
        )
        let result = LayoutReset.build(.systemLaunchpad, apps: apps, systemOrdering: ordering, categoryOf: categoryOf)
        #expect(layout(result).pages == [[.folder(title: "Work", apps: ["d", "a"]), .app("c"), .app("b")]])
        #expect(result.folders.map(\.title) == ["Work"])
    }

    @Test func systemLaunchpadWithoutItsDBFallsBackToCategories() {
        let system = LayoutReset.build(.systemLaunchpad, apps: apps, systemOrdering: nil, categoryOf: categoryOf)
        let categories = LayoutReset.build(.categories, apps: apps, systemOrdering: nil, categoryOf: categoryOf)
        #expect(layout(system) == layout(categories))
    }

    @Test(arguments: LayoutReset.Mode.allCases)
    func hiddenAppsStayHidden(_ mode: LayoutReset.Mode) throws {
        let ordering = LaunchpadOrdering(appPositions: ["h": (pageIndex: 0, orderIndex: 0)], folders: [])
        let result = LayoutReset.build(mode, apps: apps, systemOrdering: ordering, categoryOf: categoryOf)
        let h = try entry(result.apps, "h")
        #expect(h.isHidden)
        #expect(h.pageIndex == nil && h.orderIndex == nil && h.folderID == nil && h.folderOrderIndex == nil)
        #expect(result.apps.count == apps.count)
        #expect(result.apps.filter { !$0.isHidden }.allSatisfy { ($0.pageIndex != nil) != ($0.folderID != nil) })
    }

    @Test func resetKeepsNewAppDot() throws {
        var current = apps
        current[3].isNew = true
        let result = LayoutReset.build(.alphabetical, apps: current, systemOrdering: nil, categoryOf: categoryOf)
        #expect(try entry(result.apps, "a").isNew)
    }

    // MARK: - View model and backups

    @Test func resetWritesBackupFirstAndPersists() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try AppDatabase(path: dir.appendingPathComponent("test.db").path)
        let backups = LayoutBackupStore(directory: dir.appendingPathComponent("backups"))
        try db.saveLayout(apps: apps, folders: folders)
        let vm = LaunchpadViewModel(database: db, layoutBackups: backups)
        vm.folders = folders
        vm.apps = apps
        vm.openFolderID = "F"
        let before = vm.layoutFiles.layoutFile

        let backup = try #require(try vm.layoutFiles.resetLayout(.alphabetical, systemOrdering: nil, categoryOf: categoryOf))

        #expect(backups.backups().map(\.lastPathComponent) == [backup.lastPathComponent])
        #expect(try LayoutFile.decode(Data(contentsOf: backup)) == before)
        #expect(vm.folders.isEmpty)
        #expect(vm.openFolderID == nil)
        #expect(try db.fetchAllFolders().isEmpty)
        #expect(LayoutFile(apps: try db.fetchAllApps(), folders: []) == vm.layoutFiles.layoutFile)
    }

    @Test func resetChangesNothingWhenBackupFails() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // A file where the backup folder should be: creating the folder fails.
        let blocked = dir.appendingPathComponent("backups")
        try Data().write(to: blocked)
        let vm = LaunchpadViewModel(database: nil, layoutBackups: LayoutBackupStore(directory: blocked))
        vm.folders = folders
        vm.apps = apps

        #expect(throws: (any Error).self) {
            try vm.layoutFiles.resetLayout(.alphabetical, systemOrdering: nil, categoryOf: categoryOf)
        }
        #expect(vm.apps == apps)
        #expect(vm.folders == folders)
    }

    @Test func backupStoreKeepsNewest() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LayoutBackupStore(directory: dir, keepCount: 2)
        let file = LayoutFile(pages: [[.app("a")]])
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let urls = try (0..<3).map { try store.save(file, date: start.addingTimeInterval(Double($0))) }

        #expect(store.backups().map(\.lastPathComponent) == [urls[2], urls[1]].map(\.lastPathComponent))
        #expect(store.latest?.lastPathComponent == urls[2].lastPathComponent)
        #expect(!FileManager.default.fileExists(atPath: urls[0].path))
    }

    // A load and an instant restore can back up within one millisecond.
    @Test func backupsInTheSameMillisecondKeepBoth() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LayoutBackupStore(directory: dir)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try store.save(LayoutFile(pages: [[.app("a")]]), date: date)
        let second = try store.save(LayoutFile(pages: [[.app("b")]]), date: date)

        #expect(first != second)
        #expect(store.backups().map(\.lastPathComponent) == [second, first].map(\.lastPathComponent))
        #expect(try LayoutFile.decode(Data(contentsOf: first)).pages == [[.app("a")]])
    }
}
