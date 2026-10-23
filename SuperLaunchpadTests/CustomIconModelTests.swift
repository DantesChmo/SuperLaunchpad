import AppKit
import GRDB
import Testing
@testable import SuperLaunchpad

@MainActor
struct CustomIconModelTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeTempDB() throws -> (AppDatabase, URL) {
        let dir = try makeTempDir()
        return (try AppDatabase(path: dir.appendingPathComponent("test.db").path), dir)
    }

    private func app(_ bundleID: String, page: Int? = nil, order: Int? = nil, folderID: String? = nil, folderOrder: Int? = nil, icon: Data? = nil) -> AppEntry {
        AppEntry(
            bundleIdentifier: bundleID,
            displayName: bundleID,
            appPath: "/Applications/\(bundleID).app",
            iconData: icon,
            pageIndex: page,
            orderIndex: order,
            folderID: folderID,
            folderOrderIndex: folderOrder
        )
    }

    // Solid-color PNG; a different size or color gives different bytes.
    private func png(width: Int, height: Int, color: NSColor = .systemBlue) throws -> Data {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        for x in 0..<width {
            for y in 0..<height {
                rep.setColor(color, atX: x, y: y)
            }
        }
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    private func writeFile(_ data: Data, named name: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func pixelSize(of data: Data?) throws -> (Int, Int) {
        let bytes = try #require(data)
        let rep = try #require(NSBitmapImageRep(data: bytes))
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    // Page: a, folder F(x, y).
    private let folders = [FolderEntry(id: "F", title: "Tools", pageIndex: 0, orderIndex: 1)]

    private func makeViewModel(_ db: AppDatabase?, picked: URL? = nil) throws -> LaunchpadViewModel {
        let apps = [
            app("a", page: 0, order: 0, icon: try png(width: 8, height: 8)),
            app("x", folderID: "F", folderOrder: 0),
            app("y", folderID: "F", folderOrder: 1)
        ]
        try db?.saveLayout(apps: apps, folders: folders)
        let vm = LaunchpadViewModel(database: db)
        vm.folders = folders
        vm.apps = apps
        vm.customIcons.picker = CustomIconImage.Picker(choose: { picked })
        return vm
    }

    private func entry(_ vm: LaunchpadViewModel, _ id: String) throws -> AppEntry {
        try #require(vm.apps.first { $0.bundleIdentifier == id })
    }

    private func storedApp(_ db: AppDatabase, _ id: String) throws -> AppEntry {
        try #require(try db.fetchAllApps().first { $0.bundleIdentifier == id })
    }

    private func storedFolder(_ db: AppDatabase, _ id: String = "F") throws -> FolderEntry {
        try #require(try db.fetchAllFolders().first { $0.id == id })
    }

    // MARK: - App icons

    @Test func chosenImageBecomesA256PixelIconBesideTheScannedOne() async throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = try writeFile(try png(width: 100, height: 50), named: "wide.png", in: dir)
        let vm = try makeViewModel(db, picked: file)
        let scanned = try entry(vm, "a").iconData

        await vm.customIcons.chooseIcon(for: "a").value

        let a = try entry(vm, "a")
        #expect(try pixelSize(of: a.customIconData) == (AppIcon.pixelSize, AppIcon.pixelSize))
        #expect(a.iconData == scanned)
        #expect(a.displayedIconData == a.customIconData)
        let stored = try storedApp(db, "a")
        #expect(stored.customIconData == a.customIconData)
        #expect(stored.iconData == scanned)
    }

    @Test func cancelledPanelChangesNothing() async throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db, picked: nil)

        await vm.customIcons.chooseIcon(for: "a").value

        #expect(try entry(vm, "a").customIconData == nil)
        #expect(try db.fetchCustomIcons().isEmpty)
    }

    @Test func appBundleLendsItsIcon() async throws {
        let vm = try makeViewModel(nil)
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")

        #expect(await vm.customIcons.setIcon(contentsOf: finder, for: "a"))
        #expect(try pixelSize(of: try entry(vm, "a").customIconData) == (AppIcon.pixelSize, AppIcon.pixelSize))
    }

    @Test func fileOfAnotherTypeIsRefused() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let text = try writeFile(Data("hello".utf8), named: "notes.txt", in: dir)
        let damaged = try writeFile(Data("not a png".utf8), named: "broken.png", in: dir)
        let vm = try makeViewModel(nil)

        #expect(await vm.customIcons.setIcon(contentsOf: text, for: "a") == false)
        #expect(await vm.customIcons.setIcon(contentsOf: damaged, for: "a") == false)
        #expect(try entry(vm, "a").customIconData == nil)
    }

    @Test func restoreDefaultIconDropsTheCustomOne() async throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = try writeFile(try png(width: 20, height: 20), named: "icon.png", in: dir)
        let vm = try makeViewModel(db)
        #expect(await vm.customIcons.setIcon(contentsOf: file, for: "a"))
        let revision = vm.layoutRevision

        #expect(vm.itemActions.perform(.restoreIcon, on: try entry(vm, "a")) == false)

        #expect(try entry(vm, "a").customIconData == nil)
        #expect(try storedApp(db, "a").customIconData == nil)
        #expect(try db.fetchCustomIcons().isEmpty)
        #expect(vm.layoutRevision == revision + 1)
    }

    @Test func dropTakesAnImageOnlyInEditMode() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let image = try writeFile(try png(width: 20, height: 20), named: "icon.png", in: dir)
        let text = try writeFile(Data("hello".utf8), named: "notes.txt", in: dir)
        let vm = try makeViewModel(nil)

        #expect(vm.customIcons.dropFiles([image], on: "a") == nil)
        vm.editing.enterEditMode()
        #expect(vm.customIcons.dropFiles([text], on: "a") == nil)
        let task = try #require(vm.customIcons.dropFiles([text, image], on: "a"))

        #expect(await task.value)
        #expect(try entry(vm, "a").customIconData != nil)
    }

    @Test func customIconSurvivesRescan() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let custom = try png(width: 16, height: 16, color: .systemRed)
        let vm = try makeViewModel(db)
        vm.setCustomIcon(custom, for: "a")
        let rescanned = try png(width: 12, height: 12)
        let enumerated = [app("a", icon: rescanned), app("x"), app("y")]

        let (apps, _) = LaunchpadViewModel.syncScan(enumerated, systemOrdering: nil, placement: .end, database: db)

        let a = try #require(apps.first { $0.bundleIdentifier == "a" })
        #expect(a.iconData == rescanned)
        #expect(a.customIconData == custom)
    }

    @Test func customIconComesBackWhenTheAppIsReinstalled() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let custom = try png(width: 16, height: 16, color: .systemRed)
        let vm = try makeViewModel(db)
        vm.setCustomIcon(custom, for: "a")

        let (uninstalled, _) = LaunchpadViewModel.syncScan([app("x"), app("y")], systemOrdering: nil, placement: .end, database: db)
        #expect(!uninstalled.contains { $0.bundleIdentifier == "a" })
        let (reinstalled, _) = LaunchpadViewModel.syncScan([app("a"), app("x"), app("y")], systemOrdering: nil, placement: .end, database: db)

        #expect(reinstalled.first { $0.bundleIdentifier == "a" }?.customIconData == custom)
    }

    @Test func layoutEditKeepsCustomIcon() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let custom = try png(width: 16, height: 16, color: .systemRed)
        let vm = try makeViewModel(db)
        vm.setCustomIcon(custom, for: "x")

        vm.editing.disbandFolder("F")

        #expect(try entry(vm, "x").customIconData == custom)
        #expect(try storedApp(db, "x").customIconData == custom)
    }

    @Test func iconCacheShowsTheCustomIconAndFollowsChanges() throws {
        let cache = IconCache()
        var entry = app("a", icon: try png(width: 8, height: 8))
        let scanned = try #require(cache.image(for: entry))

        entry.customIconData = try png(width: 24, height: 24)
        let custom = try #require(cache.image(for: entry))
        #expect(custom !== scanned)
        #expect(custom.size == NSSize(width: 24, height: 24))
        #expect(cache.containsCurrentIcon(for: entry))

        entry.customIconData = nil
        let restored = try #require(cache.image(for: entry))
        #expect(restored.size == NSSize(width: 8, height: 8))
    }

    // MARK: - Menu

    @Test func appMenuOffersRestoreOnlyWithACustomIcon() throws {
        let vm = try makeViewModel(nil)
        func actions(_ id: String) throws -> [ItemMenu.Action] {
            vm.itemActions.menuItems(for: try entry(vm, id)).joined().map(\.action)
        }
        #expect(try actions("a").contains(.changeIcon))
        #expect(try !actions("a").contains(.restoreIcon))

        vm.setCustomIcon(try png(width: 8, height: 8), for: "a")
        #expect(try actions("a").contains(.restoreIcon))
    }

    @Test func folderMenuOffersRestoreOnlyWithACover() throws {
        let vm = try makeViewModel(nil)
        func actions() throws -> [ItemMenu.Action] {
            vm.itemActions.menuItems(for: try #require(vm.folders.first)).joined().map(\.action)
        }
        #expect(try actions().contains(.changeCover))
        #expect(try !actions().contains(.restoreCover))

        vm.setFolderCover(.emoji("🎮"), for: "F")
        #expect(try actions().contains(.restoreCover))
    }

    // MARK: - Folder covers

    @Test func changeCoverOpensTheDialogAndEscapeClosesIt() throws {
        let vm = try makeViewModel(nil)
        vm.itemActions.perform(.changeCover, on: try #require(vm.folders.first))
        #expect(vm.customIcons.coverEditFolder?.id == "F")

        #expect(vm.handleEscape() == .cancelledCoverEdit)
        #expect(vm.customIcons.coverEditFolderID == nil)

        vm.customIcons.beginCoverEdit("F")
        vm.hide()
        #expect(vm.customIcons.coverEditFolderID == nil)
    }

    @Test func emojiCoverIsStoredAndClosesTheDialog() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        vm.customIcons.beginCoverEdit("F")

        #expect(vm.customIcons.setCoverEmoji("abc") == false)
        #expect(vm.customIcons.coverEditFolderID == "F")
        #expect(vm.customIcons.setCoverEmoji(" 🎮 games"))

        #expect(vm.customIcons.coverEditFolderID == nil)
        #expect(vm.folders.first?.cover == .emoji("🎮"))
        #expect(try storedFolder(db).cover == .emoji("🎮"))
    }

    @Test func imageCoverReplacesEmojiAndRestoreBringsThePreviewBack() async throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = try writeFile(try png(width: 40, height: 40), named: "cover.png", in: dir)
        let vm = try makeViewModel(db, picked: file)
        vm.setFolderCover(.emoji("🎮"), for: "F")
        vm.customIcons.beginCoverEdit("F")

        await vm.customIcons.chooseCoverImage()?.value

        #expect(vm.customIcons.coverEditFolderID == nil)
        let stored = try storedFolder(db)
        #expect(stored.coverEmoji == nil)
        #expect(try pixelSize(of: stored.coverImageData) == (AppIcon.pixelSize, AppIcon.pixelSize))
        #expect(vm.folders.first?.cover == stored.cover)

        vm.itemActions.perform(.restoreCover, on: try #require(vm.folders.first))
        #expect(vm.folders.first?.cover == nil)
        #expect(try storedFolder(db).cover == nil)
    }

    @Test func coverSurvivesLayoutEditsAndRescan() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db)
        vm.setFolderCover(.emoji("🛠️"), for: "F")

        vm.editing.sortFolderByName("F")
        vm.editing.renameFolder("F", to: "Utilities")
        let (_, folders) = LaunchpadViewModel.syncScan([app("a"), app("x"), app("y")], systemOrdering: nil, placement: .end, database: db)

        #expect(vm.folders.first?.cover == .emoji("🛠️"))
        #expect(folders.first?.cover == .emoji("🛠️"))
    }

    @Test(arguments: [
        ("🎮", "🎮"), (" 🎮 games", "🎮"), ("❤️", "❤️"), ("1️⃣", "1️⃣"), ("👩‍💻", "👩‍💻"),
        ("a", nil), ("1", nil), ("#", nil), ("", nil), ("   ", nil)
    ] as [(String, String?)])
    func emojiIsTheFirstCharacterWhenItIsAnEmoji(text: String, expected: String?) {
        #expect(FolderCover.emoji(from: text) == expected)
    }

    // MARK: - Migration v9

    // A v8 database is filled, then opened by `AppDatabase`, which runs v9:
    // rows keep their positions and nothing has a custom icon or cover.
    @Test func v9AddsCustomIconsAndCoversWithoutTouchingRows() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("test.db").path
        let icon = try png(width: 8, height: 8)

        let queue = try DatabaseQueue(path: path)
        try AppDatabase.migrator.migrate(queue, upTo: "v8")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO folderEntry (id, title, pageIndex, orderIndex) VALUES ('F', 'Tools', 0, 1)")
            try db.execute(
                sql: "INSERT INTO appEntry (bundleIdentifier, displayName, appPath, iconData, pageIndex, orderIndex) VALUES ('a', 'a', '/a.app', ?, 0, 0)",
                arguments: [icon]
            )
            try db.execute(sql: "INSERT INTO appEntry (bundleIdentifier, displayName, appPath, folderID, folderOrderIndex) VALUES ('x', 'x', '/x.app', 'F', 0)")
        }
        try queue.close()

        let db = try AppDatabase(path: path)
        let apps = try db.fetchAllApps()
        #expect(apps.allSatisfy { $0.customIconData == nil })
        #expect(apps.first { $0.bundleIdentifier == "a" }?.iconData == icon)
        #expect(apps.first { $0.bundleIdentifier == "x" }?.folderID == "F")
        let folder = try storedFolder(db)
        #expect(folder.cover == nil && folder.title == "Tools" && folder.orderIndex == 1)
        #expect(try db.fetchCustomIcons().isEmpty)

        try db.setCustomIcon(icon, bundleIdentifier: "a")
        try db.setFolderCover(id: "F", cover: .emoji("🎮"))
        #expect(try storedApp(db, "a").customIconData == icon)
        #expect(try storedFolder(db).cover == .emoji("🎮"))
    }
}
