import Foundation
import Testing
@testable import SuperLaunchpad

struct ModelsTests {

    // MARK: - AppEntry

    @Test func appEntryIdEqualsBundleIdentifier() {
        let app = AppEntry(
            bundleIdentifier: "com.example.app",
            displayName: "Example",
            appPath: "/Applications/Example.app"
        )
        #expect(app.id == "com.example.app")
    }

    @Test func appEntryEquatableSameFields() {
        let a = AppEntry(
            bundleIdentifier: "com.a",
            displayName: "A",
            appPath: "/Applications/A.app",
            iconData: nil,
            pageIndex: 0,
            orderIndex: 1,
            folderID: nil,
            folderOrderIndex: nil
        )
        let b = AppEntry(
            bundleIdentifier: "com.a",
            displayName: "A",
            appPath: "/Applications/A.app",
            iconData: nil,
            pageIndex: 0,
            orderIndex: 1,
            folderID: nil,
            folderOrderIndex: nil
        )
        #expect(a == b)
    }

    @Test func appEntryEquatableDifferentBundle() {
        let a = AppEntry(bundleIdentifier: "com.a", displayName: "A", appPath: "/A.app")
        let b = AppEntry(bundleIdentifier: "com.b", displayName: "A", appPath: "/A.app")
        #expect(a != b)
    }

    @Test func appEntryCodableRoundTripFull() throws {
        let original = AppEntry(
            bundleIdentifier: "com.example",
            displayName: "Example",
            appPath: "/Applications/Example.app",
            iconData: Data([0xDE, 0xAD, 0xBE, 0xEF]),
            pageIndex: 2,
            orderIndex: 7,
            folderID: "folder-uuid",
            folderOrderIndex: 3
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppEntry.self, from: data)
        #expect(decoded == original)
    }

    @Test func appEntryCodableRoundTripWithNils() throws {
        let original = AppEntry(
            bundleIdentifier: "com.minimal",
            displayName: "Minimal",
            appPath: "/Applications/Minimal.app"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppEntry.self, from: data)
        #expect(decoded == original)
        #expect(decoded.iconData == nil)
        #expect(decoded.pageIndex == nil)
        #expect(decoded.folderID == nil)
    }

    // MARK: - FolderEntry

    @Test func folderEntryIdProperty() {
        let folder = FolderEntry(id: "abc-123", title: "Utilities", pageIndex: 0, orderIndex: 5)
        #expect(folder.id == "abc-123")
    }

    @Test func folderEntryEquatable() {
        let a = FolderEntry(id: "id1", title: "Games", pageIndex: 1, orderIndex: 2)
        let b = FolderEntry(id: "id1", title: "Games", pageIndex: 1, orderIndex: 2)
        let c = FolderEntry(id: "id1", title: "Games", pageIndex: 1, orderIndex: 3)
        #expect(a == b)
        #expect(a != c)
    }

    @Test func folderEntryCodableRoundTrip() throws {
        let original = FolderEntry(id: "folder-1", title: "Work", pageIndex: 2, orderIndex: 0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FolderEntry.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - LaunchpadItem

    @Test func launchpadItemAppIdMatchesBundle() {
        let app = AppEntry(bundleIdentifier: "com.x", displayName: "X", appPath: "/X.app")
        let item = LaunchpadItem.app(app)
        #expect(item.id == "com.x")
    }

    @Test func launchpadItemFolderIdMatchesFolder() {
        let folder = FolderEntry(id: "fld-1", title: "F", pageIndex: 0, orderIndex: 0)
        let item = LaunchpadItem.folder(folder, apps: [])
        #expect(item.id == "fld-1")
    }

    @Test func launchpadItemAppPageIndexNilDefaultsToZero() {
        let app = AppEntry(bundleIdentifier: "c", displayName: "C", appPath: "/C.app",
                           pageIndex: nil, orderIndex: nil)
        let item = LaunchpadItem.app(app)
        #expect(item.pageIndex == 0)
    }

    @Test func launchpadItemAppPageIndexUsesValue() {
        let app = AppEntry(bundleIdentifier: "c", displayName: "C", appPath: "/C.app",
                           pageIndex: 3, orderIndex: 5)
        let item = LaunchpadItem.app(app)
        #expect(item.pageIndex == 3)
    }

    @Test func launchpadItemFolderPageIndexUsesFolder() {
        let folder = FolderEntry(id: "f", title: "F", pageIndex: 4, orderIndex: 1)
        let item = LaunchpadItem.folder(folder, apps: [])
        #expect(item.pageIndex == 4)
    }

    @Test func launchpadItemAppOrderIndexNilDefaultsToMax() {
        let app = AppEntry(bundleIdentifier: "c", displayName: "C", appPath: "/C.app",
                           pageIndex: 0, orderIndex: nil)
        let item = LaunchpadItem.app(app)
        #expect(item.orderIndex == Int.max)
    }

    @Test func launchpadItemAppOrderIndexUsesValue() {
        let app = AppEntry(bundleIdentifier: "c", displayName: "C", appPath: "/C.app",
                           pageIndex: 0, orderIndex: 9)
        let item = LaunchpadItem.app(app)
        #expect(item.orderIndex == 9)
    }

    @Test func launchpadItemFolderOrderIndexUsesFolder() {
        let folder = FolderEntry(id: "f", title: "F", pageIndex: 0, orderIndex: 11)
        let item = LaunchpadItem.folder(folder, apps: [])
        #expect(item.orderIndex == 11)
    }
}
