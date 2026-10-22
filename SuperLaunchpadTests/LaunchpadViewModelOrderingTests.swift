import Foundation
import Testing
@testable import SuperLaunchpad

@MainActor
struct LaunchpadViewModelOrderingTests {

    private func app(_ bundleID: String, name: String? = nil) -> AppEntry {
        AppEntry(
            bundleIdentifier: bundleID,
            displayName: name ?? bundleID,
            appPath: "/Applications/\(bundleID).app"
        )
    }

    private func makeTempDB() throws -> (AppDatabase, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("test.db").path
        return (try AppDatabase(path: path), dir)
    }

    private func merge(
        _ enumerated: [AppEntry],
        in db: AppDatabase,
        systemOrdering: LaunchpadOrdering?
    ) throws -> ([AppEntry], [FolderEntry]) {
        LaunchpadViewModel.mergeNewApps(
            enumerated,
            existingApps: try db.fetchAllApps(),
            existingFolders: try db.fetchAllFolders(),
            systemOrdering: systemOrdering,
            folderImportDone: try db.setting(.folderImportDone) != nil
        )
    }

    // MARK: - applyOrdering

    @Test func applyOrderingWithNilSortsAlphabeticallyAndPaginates() {
        let apps = [
            app("com.c", name: "Charlie"),
            app("com.a", name: "Alpha"),
            app("com.b", name: "Bravo")
        ]
        let (ordered, folders) = LaunchpadViewModel.applyOrdering(nil, to: apps)
        #expect(folders.isEmpty)
        #expect(ordered.map(\.displayName) == ["Alpha", "Bravo", "Charlie"])
        #expect(ordered.allSatisfy { $0.pageIndex == 0 })
        #expect(ordered.map(\.orderIndex) == [0, 1, 2])
    }

    @Test func applyOrderingWithNilPaginatesAcrossPages() {
        // Create Grid.appsPerPage + 2 apps, sorted alphabetically by name
        let apps = (0..<(Grid.appsPerPage + 2)).map { i -> AppEntry in
            // Names like "App 00", "App 01", ... ensure deterministic alphabetical order
            let label = String(format: "App %02d", i)
            return app("com.x.\(i)", name: label)
        }
        let (ordered, _) = LaunchpadViewModel.applyOrdering(nil, to: apps)
        #expect(ordered.count == Grid.appsPerPage + 2)
        // Last two should be on page 1
        let lastTwo = ordered.suffix(2)
        #expect(lastTwo.allSatisfy { $0.pageIndex == 1 })
        #expect(lastTwo.map(\.orderIndex) == [0, 1])
        // First Grid.appsPerPage all on page 0
        let firstPage = ordered.prefix(Grid.appsPerPage)
        #expect(firstPage.allSatisfy { $0.pageIndex == 0 })
    }

    @Test func applyOrderingAssignsAppPositionsAndDropsUnordered() {
        let apps = [
            app("com.a"),
            app("com.b"),
            app("com.unknown")
        ]
        let ordering = LaunchpadOrdering(
            appPositions: [
                "com.a": (pageIndex: 0, orderIndex: 1),
                "com.b": (pageIndex: 1, orderIndex: 0)
            ],
            folders: []
        )
        let (ordered, folders) = LaunchpadViewModel.applyOrdering(ordering, to: apps)
        #expect(folders.isEmpty)
        #expect(ordered.count == 2)
        let byID = Dictionary(uniqueKeysWithValues: ordered.map { ($0.bundleIdentifier, $0) })
        #expect(byID["com.a"]?.pageIndex == 0)
        #expect(byID["com.a"]?.orderIndex == 1)
        #expect(byID["com.b"]?.pageIndex == 1)
        #expect(byID["com.b"]?.orderIndex == 0)
        #expect(byID["com.unknown"] == nil)
    }

    @Test func applyOrderingCreatesFoldersAndAssignsMembership() {
        let apps = [app("com.x"), app("com.y"), app("com.z")]
        let ordering = LaunchpadOrdering(
            appPositions: ["com.z": (pageIndex: 0, orderIndex: 5)],
            folders: [
                FolderInfo(
                    title: "Utilities",
                    pageIndex: 0,
                    orderIndex: 0,
                    appBundleIDs: [
                        (bundleID: "com.x", orderIndex: 0),
                        (bundleID: "com.y", orderIndex: 1)
                    ]
                )
            ]
        )
        let (ordered, folders) = LaunchpadViewModel.applyOrdering(ordering, to: apps)
        #expect(folders.count == 1)
        #expect(folders[0].title == "Utilities")
        #expect(folders[0].pageIndex == 0)
        #expect(folders[0].orderIndex == 0)
        let folderID = folders[0].id

        let byID = Dictionary(uniqueKeysWithValues: ordered.map { ($0.bundleIdentifier, $0) })
        #expect(byID["com.x"]?.folderID == folderID)
        #expect(byID["com.x"]?.folderOrderIndex == 0)
        #expect(byID["com.x"]?.pageIndex == nil)
        #expect(byID["com.x"]?.orderIndex == nil)

        #expect(byID["com.y"]?.folderID == folderID)
        #expect(byID["com.y"]?.folderOrderIndex == 1)

        #expect(byID["com.z"]?.folderID == nil)
        #expect(byID["com.z"]?.pageIndex == 0)
        #expect(byID["com.z"]?.orderIndex == 5)
    }

    @Test func applyOrderingFolderTakesPriorityOverAppPosition() {
        let apps = [app("com.x")]
        let ordering = LaunchpadOrdering(
            appPositions: ["com.x": (pageIndex: 2, orderIndex: 4)],
            folders: [
                FolderInfo(
                    title: "F",
                    pageIndex: 0,
                    orderIndex: 0,
                    appBundleIDs: [(bundleID: "com.x", orderIndex: 0)]
                )
            ]
        )
        let (ordered, folders) = LaunchpadViewModel.applyOrdering(ordering, to: apps)
        #expect(ordered.count == 1)
        #expect(ordered[0].folderID == folders[0].id)
        #expect(ordered[0].pageIndex == nil)
        #expect(ordered[0].orderIndex == nil)
    }

    // MARK: - mergeNewApps

    @Test func mergeNewAppsKeepsExistingPositionsAndUpdatesMeta() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Pre-seed an existing app
        var existing = app("com.a", name: "OldName")
        existing.appPath = "/Old/Path.app"
        existing.pageIndex = 1
        existing.orderIndex = 5
        try db.saveApps([existing])


        var fresh = app("com.a", name: "NewName")
        fresh.appPath = "/New/Path.app"
        fresh.iconData = Data([0x01])

        let (result, _) = try merge([fresh], in: db, systemOrdering: nil)
        #expect(result.count == 1)
        #expect(result[0].bundleIdentifier == "com.a")
        #expect(result[0].displayName == "NewName")
        #expect(result[0].appPath == "/New/Path.app")
        #expect(result[0].iconData == Data([0x01]))
        // Existing position preserved
        #expect(result[0].pageIndex == 1)
        #expect(result[0].orderIndex == 5)
    }

    @Test func mergeNewAppsAssignsNewAppAfterLastPosition() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }

        var existingA = app("com.a")
        existingA.pageIndex = 0
        existingA.orderIndex = 3
        try db.saveApps([existingA])


        let newApp = app("com.b")
        let (result, _) = try merge([existingA, newApp], in: db, systemOrdering: nil)
        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.bundleIdentifier, $0) })
        #expect(byID["com.a"]?.orderIndex == 3)
        #expect(byID["com.b"]?.pageIndex == 0)
        #expect(byID["com.b"]?.orderIndex == 4)
    }

    @Test func mergeNewAppsOverflowsToNextPage() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Fill page 0
        var seeded: [AppEntry] = []
        for i in 0..<Grid.appsPerPage {
            var entry = app("com.seed.\(i)")
            entry.pageIndex = 0
            entry.orderIndex = i
            seeded.append(entry)
        }
        try db.saveApps(seeded)


        let newApp = app("com.new")
        // enumerate must include the seeded apps too
        let enumerated = seeded + [newApp]
        let (result, _) = try merge(enumerated, in: db, systemOrdering: nil)
        let byID = Dictionary(uniqueKeysWithValues: result.map { ($0.bundleIdentifier, $0) })
        #expect(byID["com.new"]?.pageIndex == 1)
        #expect(byID["com.new"]?.orderIndex == 0)
    }

    @Test func mergeNewAppsUsesSystemOrderingForNewApp() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }


        let newApp = app("com.new")
        let ordering = LaunchpadOrdering(
            appPositions: ["com.new": (pageIndex: 2, orderIndex: 7)],
            folders: []
        )
        let (result, _) = try merge([newApp], in: db, systemOrdering: ordering)
        #expect(result.count == 1)
        #expect(result[0].pageIndex == 2)
        #expect(result[0].orderIndex == 7)
    }

    @Test func mergeNewAppsImportsFoldersWhenNoneExist() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }

        // DB is empty — no folders, no folder apps

        let newApp = app("com.x")
        let ordering = LaunchpadOrdering(
            appPositions: [:],
            folders: [
                FolderInfo(
                    title: "Imported",
                    pageIndex: 0,
                    orderIndex: 2,
                    appBundleIDs: [(bundleID: "com.x", orderIndex: 0)]
                )
            ]
        )
        let (result, folders) = try merge([newApp], in: db, systemOrdering: ordering)
        #expect(folders.count == 1)
        #expect(folders[0].title == "Imported")
        #expect(result.count == 1)
        #expect(result[0].folderID == folders[0].id)
        #expect(result[0].folderOrderIndex == 0)
        #expect(result[0].pageIndex == nil)
        #expect(result[0].orderIndex == nil)
    }

    @Test func mergeNewAppsReassignsExistingAppToImportedFolder() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Existing app at top level
        var existing = app("com.x")
        existing.pageIndex = 0
        existing.orderIndex = 0
        try db.saveApps([existing])


        let ordering = LaunchpadOrdering(
            appPositions: [:],
            folders: [
                FolderInfo(
                    title: "F",
                    pageIndex: 0,
                    orderIndex: 0,
                    appBundleIDs: [(bundleID: "com.x", orderIndex: 0)]
                )
            ]
        )
        let (result, folders) = try merge([existing], in: db, systemOrdering: ordering)
        #expect(folders.count == 1)
        #expect(result.count == 1)
        #expect(result[0].folderID == folders[0].id)
        #expect(result[0].pageIndex == nil)
        #expect(result[0].orderIndex == nil)
    }

    // MARK: - Folder import flag

    private var systemFolderOrdering: LaunchpadOrdering {
        LaunchpadOrdering(
            appPositions: [:],
            folders: [
                FolderInfo(
                    title: "System",
                    pageIndex: 0,
                    orderIndex: 1,
                    appBundleIDs: [(bundleID: "com.x", orderIndex: 0)]
                )
            ]
        )
    }

    @Test func mergeNewAppsSkipsFolderImportOnceDone() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        var existing = app("com.x")
        existing.pageIndex = 0
        existing.orderIndex = 0
        try db.saveApps([existing])
        try db.setSetting(.folderImportDone, "1")

        let (result, folders) = try merge([existing], in: db, systemOrdering: systemFolderOrdering)
        #expect(folders.isEmpty)
        #expect(result.count == 1)
        #expect(result[0].folderID == nil)
        #expect(result[0].pageIndex == 0)
        #expect(result[0].orderIndex == 0)
    }

    @Test func mergeNewAppsDoesNotPutNewAppIntoSkippedSystemFolder() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        var existing = app("com.a")
        existing.pageIndex = 0
        existing.orderIndex = 0
        try db.saveApps([existing])
        try db.setSetting(.folderImportDone, "1")

        let (result, folders) = try merge([existing, app("com.x")], in: db, systemOrdering: systemFolderOrdering)
        #expect(folders.isEmpty)
        let newApp = try #require(result.first { $0.bundleIdentifier == "com.x" })
        #expect(newApp.folderID == nil)
        #expect(newApp.pageIndex == 0)
        #expect(newApp.orderIndex == 1)
    }
}
