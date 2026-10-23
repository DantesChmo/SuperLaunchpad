import AppKit
import Foundation
import GRDB
import Testing
@testable import SuperLaunchpad

struct RetinaIconsTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // An image whose point size differs from both its pixel size and the
    // requested output, so the test catches either leaking into the PNG.
    private func image(points: CGFloat, pixels: Int) throws -> NSImage {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = NSSize(width: points, height: points)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    private func decodedBitmap(_ data: Data?) throws -> NSBitmapImageRep {
        let data = try #require(data)
        return try #require(NSBitmapImageRep(data: data))
    }

    // MARK: - Rendering

    @Test(arguments: [64, AppIcon.pixelSize])
    func pngHasRequestedPixelSize(side: Int) throws {
        let source = try image(points: 512, pixels: 1024)

        let bitmap = try decodedBitmap(source.pngData(pixelSize: side))

        #expect(bitmap.pixelsWide == side)
        #expect(bitmap.pixelsHigh == side)
        #expect(bitmap.bitsPerSample == 8)
    }

    // Doesn't depend on the machine's apps: for a missing path
    // `NSWorkspace.icon(forFile:)` returns the generic app icon.
    @Test func appIconIsStoredAtRetinaSize() throws {
        let bitmap = try decodedBitmap(AppEnumerator.iconData(forAppAt: "/System/Applications/Calculator.app"))

        #expect(AppIcon.pixelSize == 256)
        #expect(bitmap.pixelsWide == AppIcon.pixelSize)
        #expect(bitmap.pixelsHigh == AppIcon.pixelSize)
    }

    // A 16" MacBook Pro at its default 1728 × 1117 pt draws icons at ~109 pt:
    // the stored icon must have at least 2 px per point there.
    @Test func storedIconCoversRetinaGridIcon() {
        let metrics = LayoutMetrics(screenWidth: 1728, screenHeight: 1117)

        #expect(metrics.iconSize * 2 <= CGFloat(AppIcon.pixelSize))
    }

    // MARK: - Migration v7

    // A v6 database with an app on a page, one in a folder, a hidden one and
    // a new one, all with old icons, is opened by `AppDatabase`, which runs v7.
    @Test func v7ClearsIconsAndKeepsLayoutAndFlags() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("test.db").path
        let oldIcon = Data([0x01, 0x02, 0x03])

        let queue = try DatabaseQueue(path: path)
        try AppDatabase.migrator.migrate(queue, upTo: "v6")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO folderEntry (id, title, pageIndex, orderIndex) VALUES ('f1', 'Utilities', 0, 1)")
            let rows: [(String, Int?, Int?, String?, Int?, Bool, Bool)] = [
                ("com.page", 0, 0, nil, nil, false, false),
                ("com.folder", nil, nil, "f1", 0, false, false),
                ("com.hidden", nil, nil, nil, nil, true, false),
                ("com.new", 0, 2, nil, nil, false, true),
            ]
            for (id, page, order, folder, folderOrder, hidden, new) in rows {
                try db.execute(
                    sql: """
                    INSERT INTO appEntry (bundleIdentifier, displayName, appPath, iconData,
                        pageIndex, orderIndex, folderID, folderOrderIndex, isHidden, isNew)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [id, id, "/Applications/\(id).app", oldIcon, page, order, folder, folderOrder, hidden, new]
                )
            }
            try db.execute(sql: "INSERT INTO appSetting (key, value) VALUES (?, '1'), (?, '1')",
                           arguments: [AppSetting.Key.folderImportDone.rawValue, AppSetting.Key.newAppTracking.rawValue])
        }
        try queue.close()

        let db = try AppDatabase(path: path)
        let apps = Dictionary(uniqueKeysWithValues: try db.fetchAllApps().map { ($0.bundleIdentifier, $0) })

        #expect(apps.count == 4)
        #expect(apps.values.allSatisfy { $0.iconData == nil })

        let page = try #require(apps["com.page"])
        #expect(page.pageIndex == 0 && page.orderIndex == 0 && page.folderID == nil)
        let inFolder = try #require(apps["com.folder"])
        #expect(inFolder.folderID == "f1" && inFolder.folderOrderIndex == 0 && inFolder.pageIndex == nil)
        let hidden = try #require(apps["com.hidden"])
        #expect(hidden.isHidden && hidden.pageIndex == nil && hidden.folderID == nil)
        let new = try #require(apps["com.new"])
        #expect(new.isNew && !new.isHidden && new.pageIndex == 0 && new.orderIndex == 2)
        #expect(apps.values.filter(\.isHidden).count == 1)
        #expect(apps.values.filter(\.isNew).count == 1)

        #expect(try db.fetchAllFolders().map(\.id) == ["f1"])
        #expect(try db.setting(.folderImportDone) == "1")
        #expect(try db.setting(.newAppTracking) == "1")
    }

    // After v7 the next rescan writes the new icons back into the same rows.
    @Test func rescanAfterV7RestoresIconsInPlace() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("test.db").path

        let queue = try DatabaseQueue(path: path)
        try AppDatabase.migrator.migrate(queue, upTo: "v6")
        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO appEntry (bundleIdentifier, displayName, appPath, iconData, pageIndex, orderIndex, isHidden)
                VALUES ('com.a', 'A', '/Applications/A.app', ?, 1, 3, 0), ('com.b', 'B', '/Applications/B.app', ?, NULL, NULL, 1)
                """,
                arguments: [Data([0x01]), Data([0x02])]
            )
        }
        try queue.close()

        let db = try AppDatabase(path: path)
        let freshIcon = try image(points: 512, pixels: 1024).pngData(pixelSize: AppIcon.pixelSize)
        let scanned = ["com.a", "com.b"].map {
            AppEntry(bundleIdentifier: $0, displayName: $0, appPath: "/Applications/\($0).app", iconData: freshIcon)
        }

        let (apps, _) = LaunchpadViewModel.syncScan(scanned, systemOrdering: nil, placement: .end, database: db)
        let byID = Dictionary(uniqueKeysWithValues: apps.map { ($0.bundleIdentifier, $0) })

        #expect(byID.values.allSatisfy { $0.iconData == freshIcon })
        #expect(try decodedBitmap(byID["com.a"]?.iconData).pixelsWide == AppIcon.pixelSize)
        #expect(byID["com.a"]?.pageIndex == 1 && byID["com.a"]?.orderIndex == 3)
        #expect(byID["com.b"]?.isHidden == true && byID["com.b"]?.pageIndex == nil)
        #expect(byID.values.allSatisfy { !$0.isNew })
    }
}
