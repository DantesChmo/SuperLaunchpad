import Foundation
import Testing
@testable import SuperLaunchpad

@MainActor
struct FolderRenameTests {

    @Test(arguments: [
        ("Work", "Work"),
        ("  Work  ", "Work"),
        ("\tDev Tools\n", "Dev Tools"),
        ("Tools ", nil),
        ("Tools", nil),
        ("", nil),
        ("   ", nil),
        ("\n", nil)
    ] as [(String, String?)])
    func committedTitle(draft: String, expected: String?) {
        #expect(FolderRename.committedTitle(draft: draft, current: "Tools") == expected)
    }

    private func makeTempDB() throws -> (AppDatabase, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("test.db").path
        return (try AppDatabase(path: path), dir)
    }

    private func app(_ bundleID: String, page: Int? = nil, order: Int? = nil, folderID: String? = nil, folderOrder: Int? = nil) -> AppEntry {
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

    private func folderTileTitle(_ vm: LaunchpadViewModel, _ folderID: String) -> String? {
        for case .folder(let folder, _) in vm.pages.flatMap({ $0 }) where folder.id == folderID {
            return folder.title
        }
        return nil
    }

    @Test func renameUpdatesFolderTileAndKeepsLayout() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let folders = [FolderEntry(id: "F", title: "Tools", pageIndex: 0, orderIndex: 1)]
        let apps = [
            app("a", page: 0, order: 0),
            app("x", folderID: "F", folderOrder: 0),
            app("y", folderID: "F", folderOrder: 1)
        ]
        try db.saveFolders(folders)
        try db.saveApps(apps)
        let vm = LaunchpadViewModel(database: db)
        vm.folders = folders
        vm.apps = apps
        let idsBefore = vm.pages.map { $0.map(\.id) }

        let title = try #require(FolderRename.committedTitle(draft: " Work ", current: "Tools"))
        #expect(vm.renameFolder("F", to: title))

        #expect(folderTileTitle(vm, "F") == "Work")
        #expect(vm.pages.map { $0.map(\.id) } == idsBefore)
        #expect(vm.apps == apps)
        #expect(try db.fetchAllFolders().first?.title == "Work")
    }
}
