import Foundation

// First-run layout used when there is no system Launchpad DB to import.
//
// Classic Launchpad shape: Apple apps from /System/Applications loose on the
// first page(s) plus an "Other" folder with /System/Applications/Utilities.
// Third-party apps start on a fresh page: every category with at least
// `minFolderSize` apps becomes a folder, the rest stay loose.
enum InitialLayout {
    static let minFolderSize = 2

    private static let systemAppsPath = "/System/Applications"
    private static let systemUtilitiesPath = "/System/Applications/Utilities"

    private enum Item {
        case app(AppEntry)
        case folder(title: String, apps: [AppEntry])
    }

    static func build(
        _ apps: [AppEntry],
        categoryOf: (AppEntry) -> AppCategory
    ) -> ([AppEntry], [FolderEntry]) {
        var appleApps: [AppEntry] = []
        var appleUtilities: [AppEntry] = []
        var thirdParty: [AppEntry] = []
        for app in apps {
            let parent = URL(fileURLWithPath: app.appPath).deletingLastPathComponent().path
            if parent == systemUtilitiesPath {
                appleUtilities.append(app)
            } else if parent == systemAppsPath || parent.hasPrefix(systemAppsPath + "/") {
                appleApps.append(app)
            } else {
                thirdParty.append(app)
            }
        }

        var appleItems: [Item] = sortedByName(appleApps).map { .app($0) }
        if !appleUtilities.isEmpty {
            appleItems.append(.folder(title: AppCategory.uncategorized.folderTitle, apps: appleUtilities))
        }

        let byCategory = Dictionary(grouping: thirdParty, by: categoryOf)
        var thirdPartyFolders: [Item] = []
        var thirdPartyLoose: [AppEntry] = []
        for (category, members) in byCategory {
            if category != .uncategorized && members.count >= minFolderSize {
                thirdPartyFolders.append(.folder(title: category.folderTitle, apps: members))
            } else {
                thirdPartyLoose.append(contentsOf: members)
            }
        }
        thirdPartyFolders.sort { title(of: $0).localizedCaseInsensitiveCompare(title(of: $1)) == .orderedAscending }
        let thirdPartyItems = thirdPartyFolders + sortedByName(thirdPartyLoose).map { .app($0) }

        var resultApps: [AppEntry] = []
        var resultFolders: [FolderEntry] = []
        var page = 0
        var slot = 0

        func place(_ items: [Item]) {
            for item in items {
                if slot == Grid.appsPerPage {
                    page += 1
                    slot = 0
                }
                switch item {
                case .app(var app):
                    app.pageIndex = page
                    app.orderIndex = slot
                    app.folderID = nil
                    app.folderOrderIndex = nil
                    resultApps.append(app)
                case .folder(let title, let members):
                    let folderID = UUID().uuidString
                    resultFolders.append(FolderEntry(id: folderID, title: title, pageIndex: page, orderIndex: slot))
                    for (index, var app) in sortedByName(members).enumerated() {
                        app.pageIndex = nil
                        app.orderIndex = nil
                        app.folderID = folderID
                        app.folderOrderIndex = index
                        resultApps.append(app)
                    }
                }
                slot += 1
            }
        }

        place(appleItems)
        if slot > 0 {
            page += 1
            slot = 0
        }
        place(thirdPartyItems)

        return (resultApps, resultFolders)
    }

    private static func sortedByName(_ apps: [AppEntry]) -> [AppEntry] {
        apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private static func title(of item: Item) -> String {
        switch item {
        case .app(let app): app.displayName
        case .folder(let title, _): title
        }
    }
}
