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
    // order fall back to the order of the input arrays. Hidden apps and apps
    // whose folder is missing are left out (they are not shown either).
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

        for (sequence, app) in apps.enumerated() where !app.isHidden {
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

    // The apps of `appIDs` that are in the layout, in reading order: pages in
    // turn, a folder's apps (in folder order) where its tile is.
    func ordered(_ appIDs: Set<String>) -> [String] {
        pages.joined().flatMap { item -> [String] in
            switch item {
            case .app(let id): appIDs.contains(id) ? [id] : []
            case .folder(let id): (folders[id]?.appIDs ?? []).filter(appIDs.contains)
            }
        }
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

    // Puts an app that is not in the layout (it was hidden) after the last
    // item of the last page, opening a new page when that one is full.
    @discardableResult
    mutating func append(_ appID: String) -> Bool {
        guard location(of: .app(appID)) == nil else { return false }
        if pages.isEmpty {
            pages.append([])
        }
        pages[pages.count - 1].append(.app(appID))
        normalize()
        return true
    }

    // MARK: - Group operations
    //
    // A selection of apps (1.8.0) moves as one: every app comes out of its
    // page or folder, then all are put back one after another in the given
    // order. All apps must be in the layout. Folders they leave empty stay —
    // see `dissolveEmptyFolders()`.

    // Puts the apps consecutively at `slot` on page `page`, the slot counted
    // on the page without them. `page == pages.count` opens a new last page;
    // a page that overflows spills onto the next one.
    @discardableResult
    mutating func moveGroup(_ appIDs: [String], toPage page: Int, slot: Int) -> Bool {
        guard isMovableGroup(appIDs), page >= 0, page <= pages.count, slot >= 0 else { return false }
        for appID in appIDs {
            take(.app(appID))
        }
        if page == pages.count {
            pages.append([])
        }
        pages[page].insert(contentsOf: appIDs.map { Item.app($0) }, at: min(slot, pages[page].count))
        normalize()
        return true
    }

    // Puts the apps into an existing folder at `index` (clamped, counted
    // without them; nil = at the end).
    @discardableResult
    mutating func addGroup(_ appIDs: [String], toFolder folderID: String, at index: Int? = nil) -> Bool {
        guard isMovableGroup(appIDs), folders[folderID] != nil else { return false }
        for appID in appIDs {
            take(.app(appID))
        }
        guard var folder = folders[folderID] else { return false }
        let position = min(max(index ?? folder.appIDs.count, 0), folder.appIDs.count)
        folder.appIDs.insert(contentsOf: appIDs, at: position)
        folders[folderID] = folder
        normalize()
        return true
    }

    // Drops the apps onto the top-level app `targetAppID`: a new folder takes
    // the target's place and holds the target followed by the apps.
    @discardableResult
    mutating func mergeGroup(_ appIDs: [String], onto targetAppID: String, folderID: String, title: String) -> Bool {
        guard isMovableGroup(appIDs), !appIDs.contains(targetAppID), folders[folderID] == nil,
              case .page(let page, let slot) = location(of: .app(targetAppID)) else { return false }
        pages[page][slot] = .folder(folderID)
        for appID in appIDs {
            take(.app(appID))
        }
        folders[folderID] = Folder(title: title, appIDs: [targetAppID] + appIDs)
        normalize()
        return true
    }

    // New Folder from Selection: the folder takes the place of the first app
    // that is on a page; when all are in folders, it goes right after the
    // folder holding the first one.
    @discardableResult
    mutating func makeFolder(_ appIDs: [String], folderID: String, title: String) -> Bool {
        guard isMovableGroup(appIDs), folders[folderID] == nil else { return false }
        var anchor: (page: Int, slot: Int)?
        for appID in appIDs {
            if case .page(let page, let slot) = location(of: .app(appID)) {
                anchor = (page, slot)
                break
            }
        }
        if let anchor {
            pages[anchor.page][anchor.slot] = .folder(folderID)
        } else {
            guard case .folder(let sourceID, _) = location(of: .app(appIDs[0])),
                  case .page(let page, let slot) = location(of: .folder(sourceID)) else { return false }
            pages[page].insert(.folder(folderID), at: slot + 1)
        }
        for appID in appIDs {
            take(.app(appID))
        }
        folders[folderID] = Folder(title: title, appIDs: appIDs)
        normalize()
        return true
    }

    // Non-empty, no duplicates, every app in the layout.
    private func isMovableGroup(_ appIDs: [String]) -> Bool {
        !appIDs.isEmpty && Set(appIDs).count == appIDs.count && appIDs.allSatisfy { location(of: .app($0)) != nil }
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

    // Removes the folder; its apps take its place on the page, in folder
    // order, pushing the items after it along (overflow spills onto the next
    // page).
    @discardableResult
    mutating func disband(_ folderID: String) -> Bool {
        guard let folder = folders[folderID],
              case .page(let page, let slot) = location(of: .folder(folderID)) else { return false }
        folders[folderID] = nil
        pages[page].replaceSubrange(slot...slot, with: folder.appIDs.map { Item.app($0) })
        normalize()
        return true
    }

    // Reorders the folder's apps; the folder keeps its place.
    @discardableResult
    mutating func sortFolder(_ folderID: String, by areInIncreasingOrder: (String, String) -> Bool) -> Bool {
        guard var folder = folders[folderID] else { return false }
        folder.appIDs.sort(by: areInIncreasingOrder)
        folders[folderID] = folder
        return true
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
