import Foundation

// Filters and ranks the launcher's search results. Pure, so it is tested
// directly; `SearchModel` calls it whenever the query, the apps or the
// folders change.
//
// Every app is a candidate, including apps inside folders and hidden apps,
// and so is every folder, by its title. An app matches by its display name or
// its bundle file name (`Safari.app` → "Safari"): with a Russian locale the
// display name is "Системные настройки", but the user may type "system".
// Matching ignores case and diacritics.
enum AppSearch {
    // How a name matches the query. Lower is better.
    enum Rank: Int, Comparable {
        // The name starts with the query.
        case namePrefix
        // A word of the name starts with the query: "code" → Visual Studio Code.
        case wordPrefix
        // The query is made of word beginnings, words in order, some may be
        // skipped: "vsc" → Visual Studio Code, "sysset" → System Settings.
        case initials
        // The query is anywhere in the name.
        case contains
        // The query's letters appear in the name in order: "sfri" → Safari.
        case fuzzy

        // Results are ordered by tier, then by launch count, then by rank:
        // a name prefix always comes first and a fuzzy match always last, but
        // in between an often launched app beats a better match.
        var tier: Int {
            switch self {
            case .namePrefix: 0
            case .wordPrefix, .initials, .contains: 1
            case .fuzzy: 2
            }
        }

        static func < (lhs: Rank, rhs: Rank) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    static func results(for query: String, in apps: [AppEntry], folders: [FolderEntry] = []) -> [LaunchpadItem] {
        let query = Query(query)
        guard !query.text.isEmpty else { return [] }

        var matches: [Match] = apps.compactMap { app in
            rank(of: app, for: query).map {
                Match(item: .app(app), name: app.displayName, rank: $0, launchCount: app.launchCount)
            }
        }

        let matchedFolders = folders.compactMap { folder in rank(of: folder.title, for: query).map { (folder, $0) } }
        if !matchedFolders.isEmpty {
            let appsByFolder = Dictionary(grouping: apps.filter { !$0.isHidden && $0.folderID != nil }) { $0.folderID ?? "" }
            for (folder, rank) in matchedFolders {
                let folderApps = (appsByFolder[folder.id] ?? []).sorted {
                    ($0.folderOrderIndex ?? Int.max) < ($1.folderOrderIndex ?? Int.max)
                }
                matches.append(Match(item: .folder(folder, apps: folderApps), name: folder.title, rank: rank, launchCount: 0))
            }
        }

        return matches.sorted(by: Match.precedes).map(\.item)
    }

    // The apps launched most often, most first; never-launched apps are left out.
    static func mostLaunched(_ apps: [AppEntry]) -> [AppEntry] {
        apps
            .filter { $0.launchCount > 0 }
            .sorted { lhs, rhs in
                if lhs.launchCount != rhs.launchCount { return lhs.launchCount > rhs.launchCount }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    // Best rank over the display name and the bundle file name, or nil if
    // neither matches.
    static func rank(of app: AppEntry, for query: String) -> Rank? {
        rank(of: app, for: Query(query))
    }

    private static func rank(of app: AppEntry, for query: Query) -> Rank? {
        [app.displayName, bundleFileName(of: app)]
            .compactMap { rank(of: $0, for: query) }
            .min()
    }

    private static func rank(of name: String, for query: Query) -> Rank? {
        if hasPrefix(name[...], query.text) { return .namePrefix }
        let words = wordRanges(of: name)
        if words.contains(where: { hasPrefix(name[$0.lowerBound...], query.text) }) { return .wordPrefix }
        guard !query.letters.isEmpty else {
            return name.localizedStandardContains(query.text) ? .contains : nil
        }
        if matchesInitials(query.letters, words: words.map { fold(name[$0]) }) { return .initials }
        if name.localizedStandardContains(query.text) { return .contains }
        if isSubsequence(query.letters, of: fold(name[...]).filter(isWordCharacter)) { return .fuzzy }
        return nil
    }

    // MARK: - Matching

    private struct Query {
        let text: String
        // Folded letters and digits only: "Sys Set" → "sysset".
        let letters: [Character]

        init(_ query: String) {
            text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            letters = fold(text[...]).filter(isWordCharacter)
        }
    }

    private struct Match {
        let item: LaunchpadItem
        let name: String
        let rank: Rank
        let launchCount: Int

        static func precedes(_ lhs: Match, _ rhs: Match) -> Bool {
            if lhs.rank.tier != rhs.rank.tier { return lhs.rank.tier < rhs.rank.tier }
            if lhs.launchCount != rhs.launchCount { return lhs.launchCount > rhs.launchCount }
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            switch lhs.name.localizedCaseInsensitiveCompare(rhs.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return lhs.item.id < rhs.item.id
            }
        }
    }

    private static func hasPrefix(_ name: Substring, _ query: String) -> Bool {
        name.range(of: query, options: [.anchored, .caseInsensitive, .diacriticInsensitive], locale: .current) != nil
    }

    // Runs of letters and digits, also split where a lowercase letter is
    // followed by an uppercase one: "FaceTime" → Face, Time.
    private static func wordRanges(of name: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        var previous: Character?
        for index in name.indices {
            let character = name[index]
            if isWordCharacter(character) {
                if let wordStart = start, previous?.isLowercase == true, character.isUppercase {
                    ranges.append(wordStart..<index)
                    start = index
                } else if start == nil {
                    start = index
                }
            } else if let wordStart = start {
                ranges.append(wordStart..<index)
                start = nil
            }
            previous = character
        }
        if let start {
            ranges.append(start..<name.endIndex)
        }
        return ranges
    }

    // Whether `query` splits into pieces that each begin a word, the words in
    // order. Failed (query offset, word) pairs are remembered, so a long name
    // can't make it exponential.
    private static func matchesInitials(_ query: [Character], words: [[Character]]) -> Bool {
        var failed = Set<Int>()

        func match(_ queryIndex: Int, _ wordIndex: Int) -> Bool {
            if queryIndex == query.count { return true }
            if wordIndex == words.count { return false }
            let key = queryIndex * (words.count + 1) + wordIndex
            if failed.contains(key) { return false }

            // Take a beginning of this word, then go on with the next one…
            let word = words[wordIndex]
            var length = 0
            while length < word.count, queryIndex + length < query.count, word[length] == query[queryIndex + length] {
                length += 1
                if match(queryIndex + length, wordIndex + 1) { return true }
            }
            // …or skip this word.
            if match(queryIndex, wordIndex + 1) { return true }
            failed.insert(key)
            return false
        }

        return match(0, 0)
    }

    private static func isSubsequence(_ query: [Character], of name: [Character]) -> Bool {
        var remaining = query[...]
        for character in name where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }

    private static func fold(_ text: Substring) -> [Character] {
        Array(text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current))
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    private static func bundleFileName(of app: AppEntry) -> String {
        URL(fileURLWithPath: app.appPath).deletingPathExtension().lastPathComponent
    }
}
