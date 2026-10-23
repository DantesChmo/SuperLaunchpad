import Foundation
import Testing
@testable import SuperLaunchpad

extension LaunchpadItem {
    var appEntry: AppEntry? {
        if case .app(let app) = self { app } else { nil }
    }

    var name: String {
        switch self {
        case .app(let app): app.displayName
        case .folder(let folder, _): folder.title
        }
    }
}

struct AppSearchTests {

    private func app(
        _ name: String,
        file: String? = nil,
        folderID: String? = nil,
        folderOrder: Int? = nil,
        hidden: Bool = false,
        launches: Int = 0
    ) -> AppEntry {
        AppEntry(
            bundleIdentifier: "com.test.\(name)",
            displayName: name,
            appPath: "/Applications/\(file ?? name).app",
            folderID: folderID,
            folderOrderIndex: folderOrder,
            isHidden: hidden,
            launchCount: launches
        )
    }

    private func names(_ query: String, in apps: [AppEntry], folders: [FolderEntry] = []) -> [String] {
        AppSearch.results(for: query, in: apps, folders: folders).map(\.name)
    }

    @Test(arguments: ["", " ", "\n\t"])
    func blankQueryReturnsNothing(query: String) {
        #expect(AppSearch.results(for: query, in: [app("Safari")]).isEmpty)
    }

    @Test func nonMatchingAppsAreExcluded() {
        #expect(names("saf", in: [app("Safari"), app("Mail")]) == ["Safari"])
    }

    @Test func matchIgnoresCaseAndDiacritics() {
        let apps = [app("Café Bar"), app("SAFARI")]
        #expect(names("cafe", in: apps) == ["Café Bar"])
        #expect(names("safari", in: apps) == ["SAFARI"])
    }

    @Test func surroundingWhitespaceIsIgnored() {
        #expect(names("  mail ", in: [app("Mail")]) == ["Mail"])
    }

    @Test func matchesBundleFileNameWhenDisplayNameIsLocalized() {
        let settings = app("Системные настройки", file: "System Settings")
        #expect(names("system", in: [settings]) == ["Системные настройки"])
        #expect(names("настр", in: [settings]) == ["Системные настройки"])
        #expect(names("sysset", in: [settings]) == ["Системные настройки"])
    }

    @Test func appsInsideFoldersAreIncluded() {
        #expect(names("calc", in: [app("Calculator", folderID: "utilities")]) == ["Calculator"])
    }

    @Test func hiddenAppsAreIncluded() {
        let result = AppSearch.results(for: "secret", in: [app("Secret Agent", hidden: true)])
        #expect(result.first?.appEntry?.isHidden == true)
    }

    // MARK: - Matching

    struct MatchCase: CustomTestStringConvertible, Sendable {
        let name: String
        let query: String
        let rank: AppSearch.Rank?

        var testDescription: String { "\"\(query)\" in \"\(name)\"" }
    }

    @Test(arguments: [
        MatchCase(name: "Visual Studio Code", query: "visual", rank: .namePrefix),
        MatchCase(name: "Visual Studio Code", query: "visual st", rank: .namePrefix),
        MatchCase(name: "Système", query: "sys", rank: .namePrefix),
        MatchCase(name: "Visual Studio Code", query: "code", rank: .wordPrefix),
        MatchCase(name: "Visual Studio Code", query: "studio co", rank: .wordPrefix),
        MatchCase(name: "Font Book-Pro", query: "pro", rank: .wordPrefix),
        MatchCase(name: "FaceTime", query: "time", rank: .wordPrefix),
        MatchCase(name: "iTerm", query: "term", rank: .wordPrefix),
        MatchCase(name: "Visual Studio Code", query: "vsc", rank: .initials),
        MatchCase(name: "Visual Studio Code", query: "VSC", rank: .initials),
        MatchCase(name: "Visual Studio Code", query: "vscode", rank: .initials),
        MatchCase(name: "Microsoft Visual Studio Code", query: "vsc", rank: .initials),
        MatchCase(name: "System Settings", query: "sysset", rank: .initials),
        MatchCase(name: "System Settings", query: "sys set", rank: .initials),
        MatchCase(name: "FaceTime", query: "ft", rank: .initials),
        MatchCase(name: "Font Book-Pro", query: "fbp", rank: .initials),
        MatchCase(name: "Café Bar", query: "cb", rank: .initials),
        MatchCase(name: "Системные настройки", query: "снаст", rank: .initials),
        MatchCase(name: "Keynote", query: "yno", rank: .contains),
        MatchCase(name: "Keynote", query: "no", rank: .contains),
        MatchCase(name: "Safari", query: "sfri", rank: .fuzzy),
        MatchCase(name: "1Password 7", query: "pw7", rank: .fuzzy),
        MatchCase(name: "Visual Studio Code", query: "csv", rank: nil),
        MatchCase(name: "Safari", query: "xyz", rank: nil),
        MatchCase(name: "Mail", query: "-", rank: nil),
    ])
    func matching(_ match: MatchCase) {
        // The file name never matches, so only the display name counts.
        #expect(AppSearch.rank(of: app(match.name, file: "~"), for: match.query) == match.rank)
    }

    @Test func bestRankOfDisplayAndFileNameWins() {
        // The display name matches only at a word; the file name starts with it.
        let entry = app("Reset Settings", file: "Settings")
        #expect(AppSearch.rank(of: entry, for: "sett") == .namePrefix)
    }

    @Test func tiersGroupRanks() {
        #expect(AppSearch.Rank.namePrefix.tier == 0)
        #expect([AppSearch.Rank.wordPrefix, .initials, .contains].allSatisfy { $0.tier == 1 })
        #expect(AppSearch.Rank.fuzzy.tier == 2)
    }

    // MARK: - Ranking

    @Test func prefixMatchesComeBeforeWordPrefixBeforeContains() {
        let apps = [app("Xcode Notes"), app("Keynote"), app("Notes")]
        #expect(names("note", in: apps) == ["Notes", "Xcode Notes", "Keynote"])
    }

    @Test func namePrefixBeatsLaunchCount() {
        let apps = [app("Keynote", launches: 100), app("Notes")]
        #expect(names("note", in: apps) == ["Notes", "Keynote"])
    }

    @Test func launchCountOrdersNamePrefixMatches() {
        let apps = [app("Safari", launches: 1), app("Stocks", launches: 9), app("Slack", launches: 3), app("Shortcuts")]
        #expect(names("s", in: apps) == ["Stocks", "Slack", "Safari", "Shortcuts"])
    }

    @Test func launchCountBeatsBetterMatchBelowNamePrefix() {
        let apps = [app("Xcode Notes"), app("Keynote", launches: 5), app("Notes")]
        #expect(names("note", in: apps) == ["Notes", "Keynote", "Xcode Notes"])
    }

    @Test func fuzzyMatchesComeLastWhateverTheirLaunches() {
        let apps = [app("Safari", launches: 50), app("SF Remote Inspector")]
        #expect(names("sfri", in: apps) == ["SF Remote Inspector", "Safari"])
    }

    @Test func sameRankSortsWithLocalizedCaseInsensitiveCompare() {
        let apps = [app("maps"), app("Mail"), app("Éditeur"), app("Music")]
        #expect(names("m", in: apps) == ["Mail", "maps", "Music"])
        #expect(names("e", in: [app("Zed Editor"), app("Éditeur"), app("eBook")]) == ["eBook", "Éditeur", "Zed Editor"])
    }

    // MARK: - Folders

    @Test func folderIsFoundByTitleWithItsVisibleAppsInOrder() throws {
        let folder = FolderEntry(id: "F", title: "Utilities", pageIndex: 0, orderIndex: 0)
        let apps = [
            app("Calculator", folderID: "F", folderOrder: 1),
            app("Terminal", folderID: "F", folderOrder: 0),
            app("Mail"),
        ]

        let results = AppSearch.results(for: "util", in: apps, folders: [folder])

        #expect(results.count == 1)
        guard case .folder(let found, let folderApps) = try #require(results.first) else {
            Issue.record("expected a folder result")
            return
        }
        #expect(found == folder)
        #expect(folderApps.map(\.displayName) == ["Terminal", "Calculator"])
    }

    @Test(arguments: ["dt", "tools", "devtl"])
    func folderTitleUsesTheSameMatching(query: String) {
        let folder = FolderEntry(id: "F", title: "Developer Tools", pageIndex: 0, orderIndex: 0)
        #expect(names(query, in: [], folders: [folder]) == ["Developer Tools"])
    }

    @Test func foldersRankAmongAppsWithoutLaunches() {
        let folders = [FolderEntry(id: "F", title: "Games", pageIndex: 0, orderIndex: 0)]
        let apps = [app("GarageBand", launches: 3), app("Gapplin"), app("Mega Tool")]
        #expect(names("ga", in: apps, folders: folders) == ["GarageBand", "Games", "Gapplin", "Mega Tool"])
    }

    // MARK: - Most launched

    @Test func mostLaunchedSortsByLaunchesAndSkipsNeverLaunched() {
        let apps = [app("Mail", launches: 2), app("Notes"), app("Safari", launches: 7), app("Maps", launches: 2)]
        #expect(AppSearch.mostLaunched(apps).map(\.displayName) == ["Safari", "Mail", "Maps"])
    }
}
