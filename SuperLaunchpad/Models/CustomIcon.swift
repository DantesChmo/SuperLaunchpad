import Foundation
import GRDB

// An icon the user picked for an app, by bundle ID. Kept apart from
// `appEntry.iconData`, which every rescan rewrites, and without a foreign key,
// so it outlives the app's row: an app that is reinstalled gets it back.
// `imageData` is a PNG of `AppIcon.pixelSize` px.
struct CustomIcon: Identifiable, Equatable {
    var bundleIdentifier: String
    var imageData: Data

    var id: String { bundleIdentifier }
}

extension CustomIcon: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "customIcon"

    enum Columns: String, ColumnExpression {
        case bundleIdentifier, imageData
    }
}

// What a folder tile shows instead of its 3×3 preview.
enum FolderCover: Equatable {
    case emoji(String)
    // A PNG of `AppIcon.pixelSize` px.
    case image(Data)

    // The first character of `text` when it is an emoji, so a pasted word or
    // a digit is refused. Digits, `#` and `*` count as emoji only with a
    // variation selector or keycap after them.
    static func emoji(from text: String) -> String? {
        guard let character = text.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
        let scalars = character.unicodeScalars
        let isEmoji = scalars.contains { $0.properties.isEmojiPresentation }
            || (scalars.count > 1 && scalars.contains { $0.properties.isEmoji })
        return isEmoji ? String(character) : nil
    }
}
