import Foundation
import GRDB

// A single application row.
//
// Position invariant (enforced in code, not by SQL constraints):
//   • Top-level app   → `pageIndex` + `orderIndex` set, `folderID == nil`
//   • Inside a folder → `folderID` + `folderOrderIndex` set, page/order are nil
// Setting both at once is a bug — see AGENTS.md > "Domain gotchas".
struct AppEntry: Identifiable, Equatable {
    var bundleIdentifier: String
    var displayName: String
    var appPath: String
    var iconData: Data?
    var pageIndex: Int?
    var orderIndex: Int?
    var folderID: String?
    var folderOrderIndex: Int?
    // Hidden from the grid (still found by search): no position at all, so it
    // takes no slot on a page or in a folder.
    var isHidden = false

    // `Identifiable.id` lets SwiftUI's `ForEach` track this row across rebuilds.
    // Bundle ID is globally unique on macOS, so it doubles as our primary key.
    var id: String { bundleIdentifier }
}

// Persistence conformances live in a separate extension to keep the model
// struct itself free of framework concerns (project convention — see AGENTS.md).
extension AppEntry: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "appEntry"

    // `ColumnExpression` lets GRDB use this enum in type-safe query builders,
    // e.g. `AppEntry.filter(Columns.pageIndex != nil)`. The raw-string backing
    // matches the column names exactly — never reference columns as raw strings.
    enum Columns: String, ColumnExpression {
        case bundleIdentifier, displayName, appPath, iconData, pageIndex, orderIndex
        case folderID, folderOrderIndex, isHidden
    }
}
