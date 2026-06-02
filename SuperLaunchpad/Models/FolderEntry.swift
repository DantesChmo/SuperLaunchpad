import Foundation
import GRDB

struct FolderEntry: Identifiable, Equatable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "folderEntry"

    var id: String
    var title: String
    var pageIndex: Int
    var orderIndex: Int

    enum Columns: String, ColumnExpression {
        case id, title, pageIndex, orderIndex
    }
}
