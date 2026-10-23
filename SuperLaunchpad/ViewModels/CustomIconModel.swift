import Foundation

// The user's own app icons and folder covers: Change Icon… / Restore Default
// Icon in an app's menu, a file dropped on an icon in edit mode, and the
// Change Cover… dialog for a folder. Owned by `LaunchpadViewModel`, which
// stores them (`setCustomIcon` / `setFolderCover`). Work that waits for the
// file panel or decodes a file returns its `Task`, so tests can await it.
@MainActor
@Observable
final class CustomIconModel {
    private unowned let launchpad: LaunchpadViewModel

    init(launchpad: LaunchpadViewModel) {
        self.launchpad = launchpad
    }

    @ObservationIgnored var picker = CustomIconImage.Picker.live

    // MARK: - App icons

    @discardableResult
    func chooseIcon(for appID: String) -> Task<Void, Never> {
        Task {
            guard let url = await picker.choose() else { return }
            await setIcon(contentsOf: url, for: appID)
        }
    }

    // A file dropped on the icon. Only in edit mode, where a click doesn't
    // launch; `nil` when the drop is refused.
    @discardableResult
    func dropFiles(_ urls: [URL], on appID: String) -> Task<Bool, Never>? {
        guard launchpad.editing.isEditing, let url = urls.first(where: CustomIconImage.isAllowed) else { return nil }
        return Task { await setIcon(contentsOf: url, for: appID) }
    }

    // False (and nothing changes) when the file isn't an image or app.
    @discardableResult
    func setIcon(contentsOf url: URL, for appID: String) async -> Bool {
        guard let data = await Self.pngData(contentsOf: url) else { return false }
        launchpad.setCustomIcon(data, for: appID)
        return true
    }

    func restoreIcon(for appID: String) {
        launchpad.setCustomIcon(nil, for: appID)
    }

    // MARK: - Folder covers

    // The folder the Change Cover… dialog is open for.
    private(set) var coverEditFolderID: String?

    var coverEditFolder: FolderEntry? {
        guard let coverEditFolderID else { return nil }
        return launchpad.folders.first { $0.id == coverEditFolderID }
    }

    func beginCoverEdit(_ folderID: String) {
        coverEditFolderID = folderID
    }

    // Returns whether the dialog was open.
    @discardableResult
    func cancelCoverEdit() -> Bool {
        guard coverEditFolderID != nil else { return false }
        coverEditFolderID = nil
        return true
    }

    // The first character of `text`, when it is an emoji, becomes the cover
    // and the dialog closes. Otherwise nothing changes.
    @discardableResult
    func setCoverEmoji(_ text: String) -> Bool {
        guard let folderID = coverEditFolderID, let emoji = FolderCover.emoji(from: text) else { return false }
        launchpad.setFolderCover(.emoji(emoji), for: folderID)
        coverEditFolderID = nil
        return true
    }

    // The dialog stays open behind the file panel; a chosen image closes it.
    @discardableResult
    func chooseCoverImage() -> Task<Void, Never>? {
        guard let folderID = coverEditFolderID else { return nil }
        return Task {
            guard let url = await picker.choose() else { return }
            await setCoverImage(contentsOf: url, for: folderID)
        }
    }

    @discardableResult
    func setCoverImage(contentsOf url: URL, for folderID: String) async -> Bool {
        guard let data = await Self.pngData(contentsOf: url) else { return false }
        launchpad.setFolderCover(.image(data), for: folderID)
        if coverEditFolderID == folderID {
            coverEditFolderID = nil
        }
        return true
    }

    func restoreCover(for folderID: String) {
        launchpad.setFolderCover(nil, for: folderID)
        if coverEditFolderID == folderID {
            coverEditFolderID = nil
        }
    }

    // Decoding a large photo takes a moment: off the main thread.
    private static func pngData(contentsOf url: URL) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            CustomIconImage.pngData(contentsOf: url)
        }.value
    }
}
