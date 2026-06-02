import Foundation

// Sum type ("tagged union") representing one cell on the launcher grid:
// either a single app or a folder bundling several apps. SwiftUI's `ForEach`
// can iterate over `[LaunchpadItem]` and the consumer uses `switch` to render
// the right cell variant — see `AppGridPageView`.
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
        // Top-level apps SHOULD have a page index after `applyOrdering`. The
        // `?? 0` is defensive — a freshly enumerated app with no ordering yet
        // falls back to the first page rather than crashing.
        case .app(let app): app.pageIndex ?? 0
        case .folder(let folder, _): folder.pageIndex
        }
    }

    var orderIndex: Int {
        switch self {
        // `Int.max` pushes unsorted apps to the end of their page when used as
        // a sort key — preferable to crashing on a missing index.
        case .app(let app): app.orderIndex ?? Int.max
        case .folder(let folder, _): folder.orderIndex
        }
    }
}
