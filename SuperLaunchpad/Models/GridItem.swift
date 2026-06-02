import Foundation

enum LaunchpadItem: Identifiable {
    case app(AppEntry)
    case folder(FolderEntry, apps: [AppEntry])

    var id: String {
        switch self {
        case .app(let app): app.id
        case .folder(let folder, _): folder.id
        }
    }

    var pageIndex: Int {
        switch self {
        case .app(let app): app.pageIndex ?? 0
        case .folder(let folder, _): folder.pageIndex
        }
    }

    var orderIndex: Int {
        switch self {
        case .app(let app): app.orderIndex ?? Int.max
        case .folder(let folder, _): folder.orderIndex
        }
    }
}
