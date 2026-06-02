import Foundation
import GRDB

// A folder shown on the launcher grid.
// Unlike `AppEntry`, `id` here is generated in code (`UUID().uuidString`) — SQLite
// does NOT autoincrement it. New folders must have `id` set before `save(db)`.
struct FolderEntry: Identifiable, Equatable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "folderEntry"

    var id: String
    var title: String
    // Page/order are non-optional because a folder always sits on the main grid
    // (it can't be "inside another folder" the way an app can be inside this one).
    var pageIndex: Int
    var orderIndex: Int

    enum Columns: String, ColumnExpression {
        case id, title, pageIndex, orderIndex
    }
}
