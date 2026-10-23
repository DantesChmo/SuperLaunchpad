import Foundation

// Settings → Layout: save the layout to a file, load one, reset, restore the
// previous layout. Reset and load replace the whole layout
// (`LaunchpadViewModel.replaceLayout`); both save the current one to
// `layoutBackups` first and change nothing when that fails.
@MainActor
@Observable
final class LayoutFileModel {
    private unowned let launchpad: LaunchpadViewModel

    init(launchpad: LaunchpadViewModel) {
        self.launchpad = launchpad
    }

    // Where a reset or a load saves the layout first. `nil`: no backup.
    @ObservationIgnored var layoutBackups: LayoutBackupStore?

    var layoutFile: LayoutFile {
        LayoutFile(apps: launchpad.apps, folders: launchpad.folders)
    }

    // Returns the backup.
    @discardableResult
    func resetLayout(
        _ mode: LayoutReset.Mode,
        systemOrdering: LaunchpadOrdering?,
        categoryOf: (AppEntry) -> AppCategory = AppCategory.of
    ) throws -> URL? {
        let backup = try layoutBackups?.save(layoutFile)
        let result = LayoutReset.build(mode, apps: launchpad.apps, systemOrdering: systemOrdering, categoryOf: categoryOf)
        launchpad.replaceLayout(apps: result.apps, folders: result.folders)
        return backup
    }

    @discardableResult
    func loadLayout(_ file: LayoutFile) throws -> (applied: LayoutFile.Applied, backup: URL?) {
        let backup = try layoutBackups?.save(layoutFile)
        let applied = file.apply(to: launchpad.apps)
        launchpad.replaceLayout(apps: applied.apps, folders: applied.folders)
        return (applied, backup)
    }

    // Loads the newest backup, after backing up the current layout: a second
    // restore undoes the first.
    @discardableResult
    func restorePreviousLayout() throws -> (applied: LayoutFile.Applied, backup: URL?)? {
        guard let url = layoutBackups?.latest else { return nil }
        let file = try LayoutFile.decode(Data(contentsOf: url))
        return try loadLayout(file)
    }
}
