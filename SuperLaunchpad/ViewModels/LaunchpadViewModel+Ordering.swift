import Foundation

// The pure layout steps of a rescan, kept apart from the main-actor state:
// all `nonisolated static`, they run inside the detached rescan
// (`LaunchpadViewModel.startRescan`) and in the tests with a temp DB.
extension LaunchpadViewModel {
    // MARK: - Scan result

    // Writes one scan's result to the DB: the first-launch layout for an empty
    // DB, otherwise the existing layout plus new apps minus uninstalled ones.
    // Returns the rows as stored.
    //
    // `nonisolated static`: runs inside the detached rescan.
    nonisolated static func syncScan(
        _ enumerated: [AppEntry],
        systemOrdering: LaunchpadOrdering?,
        placement: NewAppPlacement,
        database: AppDatabase?
    ) -> (apps: [AppEntry], folders: [FolderEntry]) {
        // First launch heuristic: if no app has a pageIndex yet, we treat
        // this as a fresh install and import ordering from macOS Launchpad.
        let hasOrdering = (try? database?.hasOrderingData()) ?? false

        let appsToSave: [AppEntry]
        let foldersToSave: [FolderEntry]

        if !hasOrdering {
            // Fresh DB → apply system Launchpad layout (or alphabetical
            // fallback if the system DB is empty).
            (appsToSave, foldersToSave) = LaunchpadViewModel.applyOrdering(systemOrdering, to: enumerated)
        } else {
            // Existing DB → preserve user's existing positions, append
            // any newly installed apps at the end.
            let folderImportDone = (try? database?.setting(.folderImportDone)) != nil
            let tracksNewApps = (try? database?.setting(.newAppTracking)) != nil
            (appsToSave, foldersToSave) = LaunchpadViewModel.mergeNewApps(
                enumerated,
                existingApps: (try? database?.fetchAllApps()) ?? [],
                existingFolders: (try? database?.fetchAllFolders()) ?? [],
                systemOrdering: systemOrdering,
                folderImportDone: folderImportDone,
                markNew: tracksNewApps,
                placement: placement
            )
        }

        // Order matters: folders must exist before apps with FK references
        // to them are inserted. (FK constraint would otherwise fire.)
        try? database?.saveFolders(foldersToSave)
        try? database?.saveApps(appsToSave)

        // With a system layout available, both paths above have imported
        // its folders by now; never import them again.
        if systemOrdering != nil {
            try? database?.setSetting(.folderImportDone, "1")
        }

        // Every app on disk has a row now, unless the first import skipped
        // apps the system layout doesn't know: from the next rescan on, an
        // app without a row was just installed.
        if appsToSave.count == enumerated.count {
            try? database?.setSetting(.newAppTracking, "1")
        }

        // Drop rows for apps that were uninstalled since the last scan.
        let validIDs = Set(enumerated.map(\.bundleIdentifier))
        try? database?.deleteStale(validIdentifiers: validIDs)

        // After deleting stale apps, some folders may now be empty —
        // remove those too so they don't appear as ghost tiles.
        let folderIDsWithApps = Set(appsToSave.compactMap(\.folderID))
        let staleFolderIDs = Set(foldersToSave.map(\.id)).subtracting(folderIDsWithApps)
        if !staleFolderIDs.isEmpty {
            let validFolderIDs = Set(foldersToSave.map(\.id)).subtracting(staleFolderIDs)
            try? database?.deleteStaleFolders(validIDs: validFolderIDs)
        }

        // Re-read from DB so we get rows sorted by the canonical SQL
        // ordering (with locale-aware collation). Falls back to the
        // in-memory list if the read fails.
        let sortedApps = (try? database?.fetchAllApps()) ?? appsToSave
        let sortedFolders = (try? database?.fetchAllFolders()) ?? foldersToSave
        return (sortedApps, sortedFolders)
    }

    // MARK: - Ordering

    // First-launch ordering. Take the freshly enumerated apps and assign
    // positions based on the system Launchpad layout. Falls back to a
    // categorized layout when the system DB is empty.
    //
    // `nonisolated static`: runs inside the detached rescan, so it must not
    // touch main-actor state.
    nonisolated static func applyOrdering(_ ordering: LaunchpadOrdering?, to apps: [AppEntry]) -> ([AppEntry], [FolderEntry]) {
        guard let ordering else {
            // No system DB (always the case on macOS 26 Tahoe) — group apps
            // by category, see `InitialLayout`.
            return InitialLayout.build(apps, categoryOf: AppCategory.of)
        }

        // The system DB identifies folders by an internal rowid we can't
        // reuse — generate fresh UUID strings and build a lookup from
        // bundleID → which folder + position inside it.
        var folderAppPositions: [String: (folderID: String, folderOrderIndex: Int)] = [:]
        var newFolders: [FolderEntry] = []

        for folderInfo in ordering.folders {
            let folderID = UUID().uuidString
            newFolders.append(FolderEntry(
                id: folderID,
                title: folderInfo.title,
                pageIndex: folderInfo.pageIndex,
                orderIndex: folderInfo.orderIndex
            ))
            for appRef in folderInfo.appBundleIDs {
                folderAppPositions[appRef.bundleID] = (folderID: folderID, folderOrderIndex: appRef.orderIndex)
            }
        }

        var ordered: [AppEntry] = []
        var unordered: [AppEntry] = []

        for app in apps {
            if let folderPos = folderAppPositions[app.bundleIdentifier] {
                // App belongs to a folder — set folder fields, clear page fields.
                // The "either page OR folder, never both" invariant lives here.
                var app = app
                app.folderID = folderPos.folderID
                app.folderOrderIndex = folderPos.folderOrderIndex
                app.pageIndex = nil
                app.orderIndex = nil
                ordered.append(app)
            } else if let pos = ordering.appPositions[app.bundleIdentifier] {
                // Top-level app with known position from the system DB.
                var app = app
                app.pageIndex = pos.pageIndex
                app.orderIndex = pos.orderIndex
                ordered.append(app)
            } else {
                unordered.append(app)
            }
        }

        // Drop apps that aren't tracked by the system Launchpad at all.
        // These are typically background-only apps the user shouldn't see
        // in a launcher (CLI installers, login helpers, etc.).
        _ = unordered

        return (ordered, newFolders)
    }

    // Subsequent-launch merge. Preserve every existing position; append
    // newly-installed apps at the end. Re-import folders from the system DB
    // only if we don't yet have any and never imported them (recovery path).
    //
    // `nonisolated static` like `applyOrdering`; the caller passes in the rows
    // currently in the DB and the `folderImportDone` setting.
    //
    // With `markNew` the new apps are marked `isNew` and go where `placement`
    // says; `categoryTitles` names the folders that match an app's category.
    nonisolated static func mergeNewApps(
        _ enumerated: [AppEntry],
        existingApps existing: [AppEntry],
        existingFolders: [FolderEntry],
        systemOrdering: LaunchpadOrdering?,
        folderImportDone: Bool,
        markNew: Bool = false,
        placement: NewAppPlacement = .end,
        categoryTitles: (AppEntry) -> [String] = NewAppPlacement.categoryFolderTitles
    ) -> ([AppEntry], [FolderEntry]) {
        // O(1) bundleID lookup for the merge loop below.
        // `uniqueKeysWithValues` traps on duplicate keys — safe here because
        // bundleIdentifier is the primary key.
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.bundleIdentifier, $0) })
        var existingFolders = existingFolders

        // Recovery path: a DB where folders were dropped (e.g. older app version
        // never imported them) should re-import on the next run. We detect this
        // by checking: do we have folder rows AND apps actually linked to them?
        // Once the import happened (or the user edited the layout) an empty
        // folder list is the user's choice: dissolving the last folder must not
        // bring the system folders back.
        var folderAppPositions: [String: (folderID: String, folderOrderIndex: Int)] = [:]
        let hasFolderApps = existing.contains { $0.folderID != nil }
        if !folderImportDone, existingFolders.isEmpty || !hasFolderApps, let ordering = systemOrdering {
            existingFolders = []
            for folderInfo in ordering.folders {
                let folderID = UUID().uuidString
                existingFolders.append(FolderEntry(
                    id: folderID,
                    title: folderInfo.title,
                    pageIndex: folderInfo.pageIndex,
                    orderIndex: folderInfo.orderIndex
                ))
                for appRef in folderInfo.appBundleIDs {
                    folderAppPositions[appRef.bundleID] = (folderID: folderID, folderOrderIndex: appRef.orderIndex)
                }
            }
        }

        var result: [AppEntry] = []
        var newApps: [AppEntry] = []

        // Walk the freshly-enumerated apps. For each one decide: update an
        // existing row (keep position) or queue it as a brand-new app.
        for app in enumerated {
            if var existingApp = existingByID[app.bundleIdentifier] {
                // Refresh mutable metadata (name and icon can change between
                // updates) but preserve user-positioning fields.
                existingApp.displayName = app.displayName
                existingApp.appPath = app.appPath
                existingApp.iconData = app.iconData
                // If folders were just re-imported, retroactively attach
                // this existing app to its folder, unless the user hid it.
                if !existingApp.isHidden, let folderPos = folderAppPositions[app.bundleIdentifier] {
                    existingApp.folderID = folderPos.folderID
                    existingApp.folderOrderIndex = folderPos.folderOrderIndex
                    existingApp.pageIndex = nil
                    existingApp.orderIndex = nil
                }
                result.append(existingApp)
            } else {
                newApps.append(app)
            }
        }

        // Find the highest page/slot currently occupied — new apps will be
        // appended starting at lastPage + 1 slot. We consider both top-level
        // apps and folders since both occupy slots on the main grid.
        let topLevel = result.filter { $0.folderID == nil }
        let lastPage = max(
            topLevel.compactMap(\.pageIndex).max() ?? 0,
            existingFolders.map(\.pageIndex).max() ?? 0
        )
        // `-1` so `lastOrder + 1 = 0` when the last page is empty.
        let lastOrder = max(
            topLevel.filter { $0.pageIndex == lastPage }.compactMap(\.orderIndex).max() ?? -1,
            existingFolders.filter { $0.pageIndex == lastPage }.map(\.orderIndex).max() ?? -1
        )

        var nextOrder = lastOrder + 1
        var currentPage = lastPage

        // The next free slot, paging over when the current page fills up.
        func takeNextSlot() -> (page: Int, order: Int) {
            if nextOrder >= Grid.appsPerPage {
                currentPage += 1
                nextOrder = 0
            }
            defer { nextOrder += 1 }
            return (currentPage, nextOrder)
        }

        // The folder `placement` puts a new app into, if any. The "New"
        // folder is made in the next free slot the first time it is needed.
        func placementFolderID(for app: AppEntry) -> String? {
            switch placement {
            case .end:
                return nil
            case .categoryFolder:
                let titles = categoryTitles(app)
                return existingFolders.first { folder in
                    titles.contains { $0.localizedCaseInsensitiveCompare(folder.title) == .orderedSame }
                }?.id
            case .newFolder:
                let title = NewAppPlacement.newFolderTitle
                if let folder = existingFolders.first(where: { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame }) {
                    return folder.id
                }
                let slot = takeNextSlot()
                let folder = FolderEntry(id: UUID().uuidString, title: title, pageIndex: slot.page, orderIndex: slot.order)
                existingFolders.append(folder)
                return folder.id
            }
        }

        for var app in newApps {
            app.isNew = markNew
            // Priority 1: this new app belongs to a folder according to the
            // (possibly just-imported) system DB layout.
            if let folderPos = folderAppPositions[app.bundleIdentifier] {
                app.folderID = folderPos.folderID
                app.folderOrderIndex = folderPos.folderOrderIndex
                app.pageIndex = nil
                app.orderIndex = nil
            } else if markNew, let folderID = placementFolderID(for: app) {
                // Priority 2: the user's choice in Settings, after the
                // folder's last app.
                let lastIndex = result.filter { $0.folderID == folderID }.compactMap(\.folderOrderIndex).max() ?? -1
                app.folderID = folderID
                app.folderOrderIndex = lastIndex + 1
                app.pageIndex = nil
                app.orderIndex = nil
            } else if let pos = systemOrdering?.appPositions[app.bundleIdentifier] {
                // Priority 3: the system DB knows where this app should go.
                app.pageIndex = pos.pageIndex
                app.orderIndex = pos.orderIndex
            } else {
                // Priority 4: append at the next free slot.
                let slot = takeNextSlot()
                app.pageIndex = slot.page
                app.orderIndex = slot.order
            }
            result.append(app)
        }

        return (result, existingFolders)
    }
}
