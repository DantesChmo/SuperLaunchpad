import Foundation

// Where a rescan puts an app installed since the last one (Settings → New Apps).
// Applied by `LaunchpadViewModel.mergeNewApps`.
enum NewAppPlacement: String, CaseIterable, Identifiable {
    // After the last item on the last page.
    case end
    // Into the folder titled after the app's category, when the grid has one;
    // otherwise at the end.
    case categoryFolder
    // Into the "New" folder, made after the last item when there is none.
    case newFolder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .end: String(localized: "At the end")
        case .categoryFolder: String(localized: "In the folder for their category")
        case .newFolder: String(localized: "In a “New” folder")
        }
    }

    static let newFolderTitle = String(localized: "New")

    // Folder titles that match the app's category: the first-run folder name
    // (`AppCategory`) and the name a folder made by dropping one app on
    // another gets (`AppCategoryTitle`). Empty for an app without a category.
    static func categoryFolderTitles(of app: AppEntry) -> [String] {
        var titles: [String] = []
        let category = AppCategory.of(app)
        if category != .uncategorized {
            titles.append(category.folderTitle)
        }
        let type = Bundle(path: app.appPath)?.object(forInfoDictionaryKey: AppCategoryTitle.typeKey) as? String
        if let title = AppCategoryTitle.title(forCategoryType: type) {
            titles.append(title)
        }
        return titles
    }
}
