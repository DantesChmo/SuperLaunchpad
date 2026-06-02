import Foundation
import GRDB

struct AppEntry: Identifiable, Equatable {
    var bundleIdentifier: String
    var displayName: String
    var appPath: String
    var iconData: Data?
    var pageIndex: Int?
    var orderIndex: Int?
    var folderID: String?
    var folderOrderIndex: Int?

    var id: String { bundleIdentifier }
}

extension AppEntry: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "appEntry"

    enum Columns: String, ColumnExpression {
        case bundleIdentifier, displayName, appPath, iconData, pageIndex, orderIndex
        case folderID, folderOrderIndex
    }
}
