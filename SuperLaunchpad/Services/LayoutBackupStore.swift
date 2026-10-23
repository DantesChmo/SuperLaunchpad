import Foundation

// Layout files saved automatically before a reset or a load, so either can be
// undone. One JSON file per backup, named by date; only the newest
// `keepCount` are kept. Tests pass a temp directory.
struct LayoutBackupStore {
    let directory: URL
    var keepCount = LayoutBackup.keepCount

    // ~/Library/Application Support/com.dantes.SuperLaunchpad/Layout Backups
    static var standard: LayoutBackupStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LayoutBackupStore(directory: support
            .appendingPathComponent("com.dantes.SuperLaunchpad", isDirectory: true)
            .appendingPathComponent("Layout Backups", isDirectory: true))
    }

    private static let namePrefix = "Layout "
    private static let nameExtension = "json"

    // Milliseconds keep two backups in the same second apart; the fixed-width
    // date makes name order the date order.
    private static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
        return namePrefix + formatter.string(from: date) + "." + nameExtension
    }

    @discardableResult
    func save(_ file: LayoutFile, date: Date = .now) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Two backups in the same millisecond (a load, then an instant
        // restore) would share a name: step forward a millisecond instead,
        // so name order stays date order and neither overwrites the other.
        var date = date
        var url = directory.appendingPathComponent(Self.fileName(for: date))
        while FileManager.default.fileExists(atPath: url.path) {
            date += 0.001
            url = directory.appendingPathComponent(Self.fileName(for: date))
        }
        try file.encoded().write(to: url, options: .atomic)
        for old in backups().dropFirst(keepCount) {
            try? FileManager.default.removeItem(at: old)
        }
        return url
    }

    // Newest first.
    func backups() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.lastPathComponent.hasPrefix(Self.namePrefix) && $0.pathExtension == Self.nameExtension }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    var latest: URL? { backups().first }
}
