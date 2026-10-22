import Foundation
import GRDB

// One key/value row of app-wide state that belongs with the layout in the DB
// (as opposed to user preferences, which live in UserDefaults).
struct AppSetting: Identifiable, Equatable {
    enum Key: String {
        // Set once the system Launchpad folders have been imported, or the user
        // edited the layout. From then on a rescan never re-imports them, so a
        // folder the user dissolved stays dissolved.
        case folderImportDone
    }

    var key: String
    var value: String

    var id: String { key }
}

extension AppSetting: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "appSetting"

    enum Columns: String, ColumnExpression {
        case key, value
    }
}
