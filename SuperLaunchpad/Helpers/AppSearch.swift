import Foundation

// Filters and ranks apps for the launcher's search field. Pure, so it is
// tested directly; `LaunchpadViewModel` calls it whenever the query or the
// app list changes.
//
// Every app is a candidate, including apps inside folders. An app matches if
// its display name or its bundle file name (`Safari.app` → "Safari") contains
// the query, ignoring case and diacritics: with a Russian locale the display
// name is "Системные настройки", but the user may type "system".
enum AppSearch {
    // Lower is better.
    enum Rank: Int, Comparable {
        case namePrefix
        case wordPrefix
        case contains

        static func < (lhs: Rank, rhs: Rank) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    static func results(for query: String, in apps: [AppEntry]) -> [AppEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        return apps
            .compactMap { app in rank(of: app, for: query).map { (app, $0) } }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.displayName.localizedCaseInsensitiveCompare(rhs.0.displayName) == .orderedAscending
            }
            .map(\.0)
    }

    // Best rank over the display name and the bundle file name, or nil if
    // neither matches.
    static func rank(of app: AppEntry, for query: String) -> Rank? {
        [app.displayName, bundleFileName(of: app)]
            .compactMap { rank(of: $0, for: query) }
            .min()
    }

    private static func rank(of name: String, for query: String) -> Rank? {
        guard name.localizedStandardContains(query) else { return nil }
        if hasPrefix(name, query) { return .namePrefix }
        let words = name.split { !$0.isLetter && !$0.isNumber }
        if words.contains(where: { hasPrefix(String($0), query) }) { return .wordPrefix }
        return .contains
    }

    private static func hasPrefix(_ name: String, _ query: String) -> Bool {
        name.range(of: query, options: [.anchored, .caseInsensitive, .diacriticInsensitive], locale: .current) != nil
    }

    private static func bundleFileName(of app: AppEntry) -> String {
        URL(fileURLWithPath: app.appPath).deletingPathExtension().lastPathComponent
    }
}
