import Foundation
import Testing
@testable import SuperLaunchpad

struct AppSearchTests {

    private func app(_ name: String, file: String? = nil, folderID: String? = nil) -> AppEntry {
        AppEntry(
            bundleIdentifier: "com.test.\(name)",
            displayName: name,
            appPath: "/Applications/\(file ?? name).app",
            folderID: folderID
        )
    }

    private func names(_ query: String, in apps: [AppEntry]) -> [String] {
        AppSearch.results(for: query, in: apps).map(\.displayName)
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
    }

    @Test func appsInsideFoldersAreIncluded() {
        #expect(names("calc", in: [app("Calculator", folderID: "utilities")]) == ["Calculator"])
    }

    @Test func prefixMatchesComeBeforeWordPrefixBeforeContains() {
        let apps = [app("Xcode Notes"), app("Keynote"), app("Notes")]
        #expect(names("note", in: apps) == ["Notes", "Xcode Notes", "Keynote"])
    }

    @Test func ranksAreClassified() {
        #expect(AppSearch.rank(of: app("Notes"), for: "no") == .namePrefix)
        #expect(AppSearch.rank(of: app("Xcode Notes"), for: "no") == .wordPrefix)
        #expect(AppSearch.rank(of: app("Font Book-Pro"), for: "pro") == .wordPrefix)
        #expect(AppSearch.rank(of: app("Keynote"), for: "no") == .contains)
        #expect(AppSearch.rank(of: app("Mail"), for: "no") == nil)
    }

    @Test func bestRankOfDisplayAndFileNameWins() {
        // The display name matches only at a word; the file name starts with it.
        let entry = app("Reset Settings", file: "Settings")
        #expect(AppSearch.rank(of: entry, for: "sett") == .namePrefix)
    }

    @Test func sameRankSortsWithLocalizedCaseInsensitiveCompare() {
        let apps = [app("maps"), app("Mail"), app("Éditeur"), app("Music")]
        #expect(names("m", in: apps) == ["Mail", "maps", "Music"])
        #expect(names("e", in: [app("Zed Editor"), app("Éditeur"), app("eBook")]) == ["eBook", "Éditeur", "Zed Editor"])
    }
}
