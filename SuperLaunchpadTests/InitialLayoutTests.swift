import Foundation
import Testing
@testable import SuperLaunchpad

struct InitialLayoutTests {

    private func app(_ name: String, dir: String = "/Applications") -> AppEntry {
        AppEntry(
            bundleIdentifier: "com.test.\(name)",
            displayName: name,
            appPath: "\(dir)/\(name).app"
        )
    }

    private func build(
        _ apps: [AppEntry],
        categories: [String: AppCategory] = [:]
    ) -> ([AppEntry], [FolderEntry]) {
        InitialLayout.build(apps) { categories[$0.displayName] ?? .uncategorized }
    }

    private func members(of folder: FolderEntry, in apps: [AppEntry]) -> [String] {
        apps.filter { $0.folderID == folder.id }
            .sorted { ($0.folderOrderIndex ?? 0) < ($1.folderOrderIndex ?? 0) }
            .map(\.displayName)
    }

    @Test func categoryWithTwoAppsBecomesFolderSingletonStaysLoose() throws {
        let (apps, folders) = build(
            [app("Xcode"), app("Tower"), app("Slack")],
            categories: ["Xcode": .developerTools, "Tower": .developerTools, "Slack": .social]
        )
        #expect(folders.count == 1)
        let folder = try #require(folders.first)
        #expect(folder.title == AppCategory.developerTools.folderTitle)
        #expect(members(of: folder, in: apps) == ["Tower", "Xcode"])
        let slack = try #require(apps.first { $0.displayName == "Slack" })
        #expect(slack.folderID == nil)
        #expect(slack.pageIndex == 0)
    }

    @Test func uncategorizedAppsNeverFormFolder() {
        let (apps, folders) = build([app("A"), app("B"), app("C")])
        #expect(folders.isEmpty)
        #expect(apps.allSatisfy { $0.folderID == nil && $0.pageIndex == 0 })
    }

    @Test func folderAppsHaveNoPagePosition() {
        let (apps, _) = build(
            [app("A"), app("B"), app("C"), app("Calculator", dir: "/System/Applications"),
             app("Terminal", dir: "/System/Applications/Utilities")],
            categories: ["A": .games, "B": .games]
        )
        for app in apps {
            if app.folderID != nil {
                #expect(app.pageIndex == nil && app.orderIndex == nil)
                #expect(app.folderOrderIndex != nil)
            } else {
                #expect(app.pageIndex != nil && app.orderIndex != nil)
                #expect(app.folderOrderIndex == nil)
            }
        }
    }

    @Test func foldersComeBeforeLooseAppsAlphabetically() {
        let (apps, folders) = build(
            [app("Zed"), app("Alpha"), app("G1"), app("G2"), app("D1"), app("D2")],
            categories: ["G1": .games, "G2": .games, "D1": .developerTools, "D2": .developerTools]
        )
        var slots: [(Int, String)] = folders.map { ($0.orderIndex, $0.title) }
        for app in apps where app.folderID == nil {
            slots.append((app.orderIndex ?? 0, app.displayName))
        }
        let titles = slots.sorted { $0.0 < $1.0 }.map { $0.1 }
        #expect(titles == [AppCategory.developerTools.folderTitle, AppCategory.games.folderTitle, "Alpha", "Zed"])
    }

    @Test func appleAppsComeFirstThenThirdPartyOnNewPage() throws {
        let (apps, folders) = build([
            app("Aardvark"),
            app("Safari", dir: "/System/Applications"),
            app("Mail", dir: "/System/Applications"),
            app("Terminal", dir: "/System/Applications/Utilities"),
            app("Console", dir: "/System/Applications/Utilities"),
        ])
        let mail = try #require(apps.first { $0.displayName == "Mail" })
        let safari = try #require(apps.first { $0.displayName == "Safari" })
        #expect(mail.pageIndex == 0 && mail.orderIndex == 0)
        #expect(safari.pageIndex == 0 && safari.orderIndex == 1)

        let other = try #require(folders.first)
        #expect(folders.count == 1)
        #expect(other.pageIndex == 0 && other.orderIndex == 2)
        #expect(members(of: other, in: apps) == ["Console", "Terminal"])

        let aardvark = try #require(apps.first { $0.displayName == "Aardvark" })
        #expect(aardvark.pageIndex == 1 && aardvark.orderIndex == 0)
    }

    @Test func thirdPartyStartsOnFirstPageWithoutAppleApps() throws {
        let (apps, _) = build([app("Only")])
        let only = try #require(apps.first)
        #expect(only.pageIndex == 0 && only.orderIndex == 0)
    }

    @Test func packsItemsIntoPages() {
        let names = (0..<(Grid.appsPerPage + 2)).map { String(format: "App %02d", $0) }
        let (apps, _) = build(names.map { app($0) })
        let sorted = apps.sorted { ($0.pageIndex ?? 0, $0.orderIndex ?? 0) < ($1.pageIndex ?? 0, $1.orderIndex ?? 0) }
        #expect(sorted.map(\.displayName) == names)
        #expect(sorted.prefix(Grid.appsPerPage).allSatisfy { $0.pageIndex == 0 })
        #expect(sorted.suffix(2).map(\.pageIndex) == [1, 1])
        #expect(sorted.suffix(2).map(\.orderIndex) == [0, 1])
    }

    @Test func appleSectionFillingPageExactlyLeavesNoGap() throws {
        let appleApps = (0..<Grid.appsPerPage).map { app(String(format: "Apple %02d", $0), dir: "/System/Applications") }
        let (apps, _) = build(appleApps + [app("Third")])
        let third = try #require(apps.first { $0.displayName == "Third" })
        #expect(third.pageIndex == 1 && third.orderIndex == 0)
    }

    @Test func sortsWithLocalizedCaseInsensitiveCompare() {
        let (apps, _) = build([app("Edge"), app("beta"), app("Éclair"), app("alpha"), app("Ebb")])
        let order = apps.sorted { ($0.orderIndex ?? 0) < ($1.orderIndex ?? 0) }.map(\.displayName)
        #expect(order == ["alpha", "beta", "Ebb", "Éclair", "Edge"])
    }

    @Test(arguments: [
        ("public.app-category.developer-tools", AppCategory.developerTools),
        ("public.app-category.games", .games),
        ("public.app-category.board-games", .games),
        ("public.app-category.puzzle-games", .games),
        ("public.app-category.business", .productivity),
        ("public.app-category.photography", .creativity),
        ("public.app-category.unknown-thing", .uncategorized),
        ("com.example.not-a-category", .uncategorized),
    ])
    func mapsCategoryType(type: String, expected: AppCategory) {
        #expect(AppCategory.from(categoryType: type) == expected)
    }
}
