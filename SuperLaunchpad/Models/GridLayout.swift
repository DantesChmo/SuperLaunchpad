import Foundation

// Pure value-type model of the launcher layout, used for every edit
// (reorder, folders, rename). It holds only IDs and titles, never touches the
// DB, and is normalized after each operation:
//   • no page holds more than `pageCapacity` items — the overflow spills onto
//     the next page, cascading;
//   • no page is empty.
// `apply(to:folders:)` turns it back into rows with dense positions.
struct GridLayout: Equatable {
    enum Item: Hashable {
        case app(String)
        case folder(String)
    }

    struct Folder: Equatable {
        var title: String
        var appIDs: [String]
    }

    enum Location: Equatable {
        case page(Int, slot: Int)
        case folder(String, index: Int)
    }

    var pages: [[Item]]
    var folders: [String: Folder]
    var pageCapacity: Int

    init(pages: [[Item]], folders: [String: Folder] = [:], pageCapacity: Int = Grid.appsPerPage) {
        self.pages = pages
        self.folders = folders
        self.pageCapacity = pageCapacity
    }

    // Groups rows the same way `LaunchpadViewModel.rebuildPages` does, so the
    // layout matches what is on screen. Sparse page indices collapse; ties in
    // order fall back to the order of the input arrays. Apps whose folder is
    // missing are left out (they are not shown either).
    init(apps: [AppEntry], folders folderEntries: [FolderEntry], pageCapacity: Int = Grid.appsPerPage) {
        struct Placed {
            let item: Item
            let page: Int
            let order: Int
            let sequence: Int
        }

        let folderIDs = Set(folderEntries.map(\.id))
        var placed: [Placed] = []
        var folderMembers: [String: [(app: AppEntry, sequence: Int)]] = [:]

        for (sequence, app) in apps.enumerated() {
            if let folderID = app.folderID {
                guard folderIDs.contains(folderID) else { continue }
                folderMembers[folderID, default: []].append((app, sequence))
            } else {
                placed.append(Placed(
                    item: .app(app.bundleIdentifier),
                    page: app.pageIndex ?? 0,
                    order: app.orderIndex ?? Int.max,
                    sequence: sequence
                ))
            }
        }
        for (offset, folder) in folderEntries.enumerated() {
            placed.append(Placed(
                item: .folder(folder.id),
                page: folder.pageIndex,
                order: folder.orderIndex,
                sequence: apps.count + offset
            ))
        }

        let grouped = Dictionary(grouping: placed, by: \.page)
        pages = grouped.keys.sorted().map { page in
            (grouped[page] ?? [])
                .sorted { ($0.order, $0.sequence) < ($1.order, $1.sequence) }
                .map(\.item)
        }

        var folders: [String: Folder] = [:]
        for folder in folderEntries {
            let members = (folderMembers[folder.id] ?? []).sorted {
                ($0.app.folderOrderIndex ?? Int.max, $0.sequence) < ($1.app.folderOrderIndex ?? Int.max, $1.sequence)
            }
            folders[folder.id] = Folder(title: folder.title, appIDs: members.map(\.app.bundleIdentifier))
        }
        self.folders = folders
        self.pageCapacity = pageCapacity
    }

    // MARK: - Queries

    func location(of item: Item) -> Location? {
        for (pageIndex, page) in pages.enumerated() {
            if let slot = page.firstIndex(of: item) {
                return .page(pageIndex, slot: slot)
            }
        }
        guard case .app(let appID) = item else { return nil }
        for (folderID, folder) in folders {
            if let index = folder.appIDs.firstIndex(of: appID) {
                return .folder(folderID, index: index)
            }
        }
        return nil
    }

    // MARK: - Operations
    //
    // Each returns false and leaves the layout untouched when the edit is not
    // possible (unknown ID, folder into folder, …).

    // Moves a top-level item, or an app out of its folder, to `slot` on page
    // `page`. `page == pages.count` opens a new last page; slots past the end
    // of a page clamp to its end.
    @discardableResult
    mutating func move(_ item: Item, toPage page: Int, slot: Int) -> Bool {
        guard page >= 0, page <= pages.count, slot >= 0, take(item) != nil else { return false }
        insert(item, page: page, slot: slot)
        normalize()
        return true
    }

    // Drops `appID` onto the top-level app `targetAppID`: a new folder takes the
    // target's place and holds the target followed by the dropped app.
    @discardableResult
    mutating func merge(_ appID: String, onto targetAppID: String, folderID: String, title: String) -> Bool {
        guard appID != targetAppID,
              folders[folderID] == nil,
              location(of: .app(appID)) != nil,
              case .page = location(of: .app(targetAppID)) else { return false }
        take(.app(appID))
        guard case .page(let page, let slot) = location(of: .app(targetAppID)) else { return false }
        pages[page][slot] = .folder(folderID)
        folders[folderID] = Folder(title: title, appIDs: [targetAppID, appID])
        normalize()
        return true
    }

    // Puts `appID` into an existing folder at `index` (clamped; nil = at the
    // end). Within the same folder this reorders.
    @discardableResult
    mutating func add(_ appID: String, toFolder folderID: String, at index: Int? = nil) -> Bool {
        guard folders[folderID] != nil, take(.app(appID)) != nil, var folder = folders[folderID] else { return false }
        let position = min(max(index ?? folder.appIDs.count, 0), folder.appIDs.count)
        folder.appIDs.insert(appID, at: position)
        folders[folderID] = folder
        normalize()
        return true
    }

    // Takes `appID` out of `folderID` and places it at `slot` on page `page`.
    // The folder stays, even when empty — see `dissolveEmptyFolders()`.
    @discardableResult
    mutating func remove(_ appID: String, fromFolder folderID: String, toPage page: Int, slot: Int) -> Bool {
        guard case .folder(folderID, _) = location(of: .app(appID)) else { return false }
        return move(.app(appID), toPage: page, slot: slot)
    }

    // Drops `appID` from the layout (the app was uninstalled), closing its
    // gap. A folder it leaves empty stays — see `dissolveEmptyFolders()`.
    @discardableResult
    mutating func delete(_ appID: String) -> Bool {
        guard take(.app(appID)) != nil else { return false }
        normalize()
        return true
    }

    // Removes every folder without apps, closing its gap on the page.
    mutating func dissolveEmptyFolders() {
        let emptyIDs = Set(folders.filter { $0.value.appIDs.isEmpty }.keys)
        guard !emptyIDs.isEmpty else { return }
        for id in emptyIDs {
            folders[id] = nil
        }
        pages = pages.map { page in
            page.filter { item in
                guard case .folder(let id) = item else { return true }
                return !emptyIDs.contains(id)
            }
        }
        normalize()
    }

    // Empty or whitespace-only titles are rejected, so the old title stays.
    @discardableResult
    mutating func rename(folder folderID: String, to title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, folders[folderID] != nil else { return false }
        folders[folderID]?.title = trimmed
        return true
    }

    // MARK: - Rows

    // Writes the layout back into rows: top-level items get `pageIndex` = page
    // and `orderIndex` = slot, folder apps get dense `folderOrderIndex` with
    // page/order cleared. Apps the layout does not know keep their fields.
    // The returned folders are exactly the ones in the layout, in grid order;
    // new folders get their rows here.
    func apply(to apps: [AppEntry], folders folderEntries: [FolderEntry]) -> (apps: [AppEntry], folders: [FolderEntry]) {
        var pagePositions: [String: (page: Int, slot: Int)] = [:]
        var folderPositions: [String: (folderID: String, index: Int)] = [:]
        var resultFolders: [FolderEntry] = []
        let existingFolders = Dictionary(uniqueKeysWithValues: folderEntries.map { ($0.id, $0) })

        for (pageIndex, page) in pages.enumerated() {
            for (slot, item) in page.enumerated() {
                switch item {
                case .app(let id):
                    pagePositions[id] = (pageIndex, slot)
                case .folder(let id):
                    guard let folder = folders[id] else { continue }
                    var entry = existingFolders[id] ?? FolderEntry(id: id, title: folder.title, pageIndex: 0, orderIndex: 0)
                    entry.title = folder.title
                    entry.pageIndex = pageIndex
                    entry.orderIndex = slot
                    resultFolders.append(entry)
                    for (index, appID) in folder.appIDs.enumerated() {
                        folderPositions[appID] = (id, index)
                    }
                }
            }
        }

        let resultApps = apps.map { app in
            var app = app
            if let position = pagePositions[app.bundleIdentifier] {
                app.pageIndex = position.page
                app.orderIndex = position.slot
                app.folderID = nil
                app.folderOrderIndex = nil
            } else if let position = folderPositions[app.bundleIdentifier] {
                app.pageIndex = nil
                app.orderIndex = nil
                app.folderID = position.folderID
                app.folderOrderIndex = position.index
            }
            return app
        }
        return (resultApps, resultFolders)
    }

    // MARK: - Private

    // Removes the item from wherever it is, keeping empty pages and folders so
    // indices the caller computed before the removal still point to the same
    // page. Returns where it was.
    @discardableResult
    private mutating func take(_ item: Item) -> Location? {
        let found = location(of: item)
        switch found {
        case .page(let page, let slot):
            pages[page].remove(at: slot)
        case .folder(let folderID, let index):
            folders[folderID]?.appIDs.remove(at: index)
        case nil:
            break
        }
        return found
    }

    private mutating func insert(_ item: Item, page: Int, slot: Int) {
        if page == pages.count {
            pages.append([])
        }
        pages[page].insert(item, at: min(slot, pages[page].count))
    }

    private mutating func normalize() {
        var pageIndex = 0
        while pageIndex < pages.count {
            if pages[pageIndex].count > pageCapacity {
                let overflow = Array(pages[pageIndex][pageCapacity...])
                pages[pageIndex].removeSubrange(pageCapacity...)
                if pageIndex + 1 == pages.count {
                    pages.append([])
                }
                pages[pageIndex + 1].insert(contentsOf: overflow, at: 0)
            }
            pageIndex += 1
        }
        pages.removeAll { $0.isEmpty }
    }
}
