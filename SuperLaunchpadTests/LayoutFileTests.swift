import Foundation
import Testing
@testable import SuperLaunchpad

@MainActor
struct LayoutFileTests {

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

    // Page 0: a, folder Tools(x, y), b. Page 1: c. Hidden: h.
    private let folders = [FolderEntry(id: "F", title: "Tools", pageIndex: 0, orderIndex: 1)]
    private var apps: [AppEntry] {
        [
            app("a", page: 0, order: 0),
            app("b", page: 0, order: 2),
            app("c", page: 1, order: 0),
            app("x", folderID: "F", folderOrder: 0),
            app("y", folderID: "F", folderOrder: 1),
            app("h", hidden: true)
        ]
    }

    private func entry(_ apps: [AppEntry], _ id: String) throws -> AppEntry {
        try #require(apps.first { $0.bundleIdentifier == id })
    }

    // MARK: - Encoding

    @Test func fileFromRowsHasPagesFoldersAndHiddenApps() {
        let file = LayoutFile(apps: apps, folders: folders)
        #expect(file.formatVersion == LayoutFile.currentFormatVersion)
        #expect(file.pages == [
            [.app("a"), .folder(title: "Tools", apps: ["x", "y"]), .app("b")],
            [.app("c")]
        ])
        #expect(file.hiddenApps == ["h"])
    }

    @Test func roundTripThroughJSON() throws {
        let file = LayoutFile(apps: apps, folders: folders)
        let decoded = try LayoutFile.decode(file.encoded())
        #expect(decoded == file)
    }

    @Test func roundTripThroughApplyReproducesLayout() throws {
        let file = LayoutFile(apps: apps, folders: folders)
        let applied = try LayoutFile.decode(file.encoded()).apply(to: apps)
        #expect(LayoutFile(apps: applied.apps, folders: applied.folders) == file)
        #expect(applied.skippedApps.isEmpty)
        #expect(applied.appendedApps.isEmpty)
    }

    @Test func jsonCarriesFormatVersionAndNoScannedIcons() throws {
        var withIcon = apps
        withIcon[0].iconData = Data([1, 2, 3])
        let data = try LayoutFile(apps: withIcon, folders: folders).encoded()
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["formatVersion"] as? Int == 1)
        #expect(Set(object.keys) == ["formatVersion", "pages", "hiddenApps", "customIcons"])
        #expect((object["customIcons"] as? [String: Any])?.isEmpty == true)
    }

    // MARK: - Custom icons and covers

    // a and the hidden h have custom icons; Tools has an emoji cover, Games
    // (on page 1) an image one.
    private var decorated: (apps: [AppEntry], folders: [FolderEntry]) {
        var rows = apps + [app("g", folderID: "G", folderOrder: 0)]
        rows[0].customIconData = Data([1, 2, 3])
        rows[5].customIconData = Data([4, 5])
        var tools = folders[0]
        tools.cover = .emoji("🛠️")
        var games = FolderEntry(id: "G", title: "Games", pageIndex: 1, orderIndex: 1)
        games.cover = .image(Data([6, 7, 8]))
        return (rows, [tools, games])
    }

    @Test func customIconsAndCoversRoundTrip() throws {
        let (rows, folderRows) = decorated
        let file = LayoutFile(apps: rows, folders: folderRows)
        #expect(file.customIcons == ["a": Data([1, 2, 3]), "h": Data([4, 5])])
        #expect(file.pages[0][1] == .folder(title: "Tools", apps: ["x", "y"], cover: .emoji("🛠️")))
        #expect(file.pages[1][1] == .folder(title: "Games", apps: ["g"], cover: .image(Data([6, 7, 8]))))

        let decoded = try LayoutFile.decode(file.encoded())
        #expect(decoded == file)

        var plain = rows
        for index in plain.indices {
            plain[index].customIconData = nil
        }
        let applied = decoded.apply(to: plain)
        #expect(LayoutFile(apps: applied.apps, folders: applied.folders) == file)
        #expect(try entry(applied.apps, "a").customIconData == Data([1, 2, 3]))
        #expect(applied.folders.map(\.cover) == [.emoji("🛠️"), .image(Data([6, 7, 8]))])
    }

    @Test func jsonStoresCoversAndIconsAsBase64() throws {
        let (rows, folderRows) = decorated
        let data = try LayoutFile(apps: rows, folders: folderRows).encoded()
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let icons = try #require(object["customIcons"] as? [String: String])
        #expect(icons["a"] == Data([1, 2, 3]).base64EncodedString())
        let pages = try #require(object["pages"] as? [[[String: Any]]])
        #expect(pages[0][1]["cover"] as? [String: String] == ["emoji": "🛠️"])
        #expect(pages[1][1]["cover"] as? [String: String] == ["image": Data([6, 7, 8]).base64EncodedString()])
    }

    // A 1.7 file has neither: it loads, and the icons set here stay.
    @Test func fileWithoutIconsKeepsTheCustomIconsHere() throws {
        let json = """
        {
          "formatVersion": 1,
          "pages": [[{ "app": "a" }, { "folder": "Tools", "apps": ["x", "y"] }]],
          "hiddenApps": []
        }
        """
        let file = try LayoutFile.decode(Data(json.utf8))
        #expect(file.customIcons == nil)
        #expect(file.pages == [[.app("a"), .folder(title: "Tools", apps: ["x", "y"])]])

        let applied = file.apply(to: decorated.apps)
        #expect(try entry(applied.apps, "a").customIconData == Data([1, 2, 3]))
        #expect(applied.folders.allSatisfy { $0.cover == nil })
    }

    // A file saved with icons sets exactly its own.
    @Test func fileWithIconsReplacesTheCustomIconsHere() throws {
        let file = LayoutFile(pages: [[.app("a"), .app("b")]], customIcons: ["b": Data([9])])
        let applied = file.apply(to: decorated.apps)
        #expect(try entry(applied.apps, "a").customIconData == nil)
        #expect(try entry(applied.apps, "b").customIconData == Data([9]))
    }

    @Test func loadLayoutStoresIconsAndCovers() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try AppDatabase(path: dir.appendingPathComponent("test.db").path)
        let (rows, folderRows) = decorated
        try db.saveLayout(apps: apps, folders: folders)
        try db.setCustomIcon(Data([0]), bundleIdentifier: "c")
        let vm = LaunchpadViewModel(database: db, layoutBackups: LayoutBackupStore(directory: dir.appendingPathComponent("backups")))
        vm.folders = folders
        vm.apps = try db.fetchAllApps()

        try vm.layoutFiles.loadLayout(LayoutFile(apps: rows, folders: folderRows))

        let stored = try db.fetchAllApps()
        #expect(try entry(stored, "a").customIconData == Data([1, 2, 3]))
        #expect(try entry(stored, "h").customIconData == Data([4, 5]))
        #expect(try entry(stored, "c").customIconData == nil)
        #expect(try db.fetchAllFolders().map(\.cover) == [.emoji("🛠️")])
        #expect(LayoutFile(apps: stored, folders: try db.fetchAllFolders()) == vm.layoutFiles.layoutFile)
    }

    @Test func decodesHandWrittenFile() throws {
        let json = """
        {
          "formatVersion": 1,
          "pages": [[{ "app": "a" }, { "folder": "Tools", "apps": ["x"] }]],
          "hiddenApps": ["h"]
        }
        """
        let file = try LayoutFile.decode(Data(json.utf8))
        #expect(file.pages == [[.app("a"), .folder(title: "Tools", apps: ["x"])]])
        #expect(file.hiddenApps == ["h"])
    }

    @Test func newerFormatIsRejected() {
        let json = #"{ "formatVersion": 2, "grid": { "columns": 8 }, "pages": "whatever" }"#
        #expect(throws: LayoutFileError.newerFormat(2)) {
            try LayoutFile.decode(Data(json.utf8))
        }
    }

    @Test(arguments: [
        #"{ "pages": [] }"#,
        #"{ "formatVersion": 0, "pages": [] }"#,
        #"{ "formatVersion": 1, "pages": [[{ "folder": "No apps key" }]] }"#,
        "not json"
    ])
    func malformedFileIsRejected(_ json: String) {
        #expect(throws: LayoutFileError.notALayoutFile) {
            try LayoutFile.decode(Data(json.utf8))
        }
    }

    // MARK: - Applying

    @Test func applySkipsMissingAppsAndAppendsUnknownOnesByName() throws {
        let file = LayoutFile(pages: [
            [.app("a"), .app("gone"), .folder(title: "Tools", apps: ["gone2", "x"])],
            [.folder(title: "Empty here", apps: ["gone3"])]
        ])
        let installed = [app("zed", page: 0, order: 0), app("x", page: 0, order: 1), app("a", page: 0, order: 2), app("b", page: 0, order: 3)]
        var ids = ["F1", "F2"].makeIterator()
        let applied = file.apply(to: installed, makeFolderID: { ids.next() ?? "?" })

        #expect(applied.skippedApps == ["gone", "gone2", "gone3"])
        #expect(applied.appendedApps == ["b", "zed"])
        #expect(applied.folders == [FolderEntry(id: "F1", title: "Tools", pageIndex: 0, orderIndex: 1)])
        #expect(LayoutFile(apps: applied.apps, folders: applied.folders).pages == [
            [.app("a"), .folder(title: "Tools", apps: ["x"]), .app("b"), .app("zed")]
        ])
        let x = try entry(applied.apps, "x")
        #expect(x.folderID == "F1" && x.folderOrderIndex == 0 && x.pageIndex == nil && x.orderIndex == nil)
    }

    @Test func applyKeepsHiddenApps() throws {
        let file = LayoutFile(pages: [[.app("a")]], hiddenApps: ["h", "notInstalled"])
        let installed = [
            app("a", page: 0, order: 1),
            app("h", page: 0, order: 0),
            app("localHidden", hidden: true),
            app("wasHidden", hidden: true)
        ]
        let fileWithUnhide = LayoutFile(pages: [[.app("a"), .app("wasHidden")]], hiddenApps: file.hiddenApps)

        let applied = fileWithUnhide.apply(to: installed)

        let h = try entry(applied.apps, "h")
        #expect(h.isHidden && h.pageIndex == nil && h.orderIndex == nil && h.folderID == nil)
        // Hidden here and not in the file: stays hidden.
        #expect(try entry(applied.apps, "localHidden").isHidden)
        // Placed by the file: shown.
        let wasHidden = try entry(applied.apps, "wasHidden")
        #expect(!wasHidden.isHidden && wasHidden.pageIndex == 0 && wasHidden.orderIndex == 1)
        #expect(applied.skippedApps == ["notInstalled"])
        #expect(applied.appendedApps.isEmpty)
    }

    @Test func applyKeepsFirstPlaceOfDuplicateApp() {
        let file = LayoutFile(pages: [[.app("a"), .folder(title: "T", apps: ["a", "b"]), .app("b")]])
        let applied = file.apply(to: [app("a"), app("b")], makeFolderID: { "F" })
        #expect(LayoutFile(apps: applied.apps, folders: applied.folders).pages == [
            [.app("a"), .folder(title: "T", apps: ["b"])]
        ])
    }

    @Test func applySpillsOverfullPage() {
        let ids = (0..<5).map { "app\($0)" }
        let file = LayoutFile(pages: [ids.map { .app($0) }])
        let applied = file.apply(to: ids.map { app($0) }, pageCapacity: 2)
        let byID = Dictionary(uniqueKeysWithValues: applied.apps.map { ($0.bundleIdentifier, $0) })
        #expect(ids.map { byID[$0]?.pageIndex } == [0, 0, 1, 1, 2])
        #expect(ids.map { byID[$0]?.orderIndex } == [0, 1, 0, 1, 0])
    }

    @Test func applyNamesUntitledFolder() {
        let file = LayoutFile(pages: [[.folder(title: "  ", apps: ["a"])]])
        let applied = file.apply(to: [app("a")])
        #expect(applied.folders.map(\.title) == [EditingModel.defaultFolderTitle])
    }

    // MARK: - View model

    @Test func loadLayoutBacksUpAndPersists() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try AppDatabase(path: dir.appendingPathComponent("test.db").path)
        let backups = LayoutBackupStore(directory: dir.appendingPathComponent("backups"))
        try db.saveLayout(apps: apps, folders: folders)
        let vm = LaunchpadViewModel(database: db, layoutBackups: backups)
        vm.folders = folders
        vm.apps = apps
        let before = vm.layoutFiles.layoutFile

        let file = LayoutFile(pages: [[.app("c"), .folder(title: "New", apps: ["a", "b"])]], hiddenApps: ["x"])
        let result = try vm.layoutFiles.loadLayout(file)

        let backup = try #require(result.backup)
        #expect(try LayoutFile.decode(Data(contentsOf: backup)) == before)
        #expect(vm.folders.map(\.title) == ["New"])
        #expect(LayoutFile(apps: try db.fetchAllApps(), folders: try db.fetchAllFolders()) == vm.layoutFiles.layoutFile)
        #expect(vm.layoutFiles.layoutFile.pages == [[.app("c"), .folder(title: "New", apps: ["a", "b"]), .app("y")]])
        #expect(vm.layoutFiles.layoutFile.hiddenApps.sorted() == ["h", "x"])
    }

    @Test func restorePreviousLayoutUndoesLoad() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let backups = LayoutBackupStore(directory: dir)
        let vm = LaunchpadViewModel(database: nil, layoutBackups: backups)
        vm.folders = folders
        vm.apps = apps
        let before = vm.layoutFiles.layoutFile

        try vm.layoutFiles.loadLayout(LayoutFile(pages: [[.app("y"), .app("x")]]))
        #expect(vm.layoutFiles.layoutFile != before)
        try vm.layoutFiles.restorePreviousLayout()

        #expect(vm.layoutFiles.layoutFile == before)
        #expect(backups.backups().count == 2)
    }

    @Test func restoreWithoutBackupDoesNothing() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = LaunchpadViewModel(database: nil, layoutBackups: LayoutBackupStore(directory: dir))
        vm.folders = folders
        vm.apps = apps
        #expect(try vm.layoutFiles.restorePreviousLayout() == nil)
        #expect(vm.apps == apps)
    }
}
