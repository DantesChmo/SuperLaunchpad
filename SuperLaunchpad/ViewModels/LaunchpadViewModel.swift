import AppKit
import SwiftUI

@Observable
final class LaunchpadViewModel {
    var apps: [AppEntry] = []
    var folders: [FolderEntry] = []
    var currentPage: Int = 0
    var isVisible: Bool = false
    var searchText: String = ""
    var openFolderID: String?

    var pages: [[LaunchpadItem]] {
        // Top-level apps (not in any folder)
        let topLevelApps = apps.filter { $0.folderID == nil }

        // Build folder apps lookup
        let folderAppsGrouped = Dictionary(grouping: apps.filter { $0.folderID != nil }) { $0.folderID! }

        // Create grid items
        var items: [LaunchpadItem] = topLevelApps.map { .app($0) }

        for folder in folders {
            let folderApps = (folderAppsGrouped[folder.id] ?? []).sorted { a, b in
                (a.folderOrderIndex ?? Int.max) < (b.folderOrderIndex ?? Int.max)
            }
            items.append(.folder(folder, apps: folderApps))
        }

        // Group by page
        let grouped = Dictionary(grouping: items) { $0.pageIndex }
        return grouped.keys.sorted().map { key in
            grouped[key]!.sorted { $0.orderIndex < $1.orderIndex }
        }
    }

    var openFolder: FolderEntry? {
        guard let id = openFolderID else { return nil }
        return folders.first { $0.id == id }
    }

    var openFolderApps: [AppEntry] {
        guard let id = openFolderID else { return [] }
        return apps.filter { $0.folderID == id }
            .sorted { ($0.folderOrderIndex ?? 0) < ($1.folderOrderIndex ?? 0) }
    }

    private var database: AppDatabase?

    init() {
        do {
            database = try AppDatabase()
        } catch {
            print("Failed to initialize database: \(error)")
        }
    }

    func loadApps() {
        if let cached = try? database?.fetchAllApps(), !cached.isEmpty {
            apps = cached
        }
        if let cachedFolders = try? database?.fetchAllFolders(), !cachedFolders.isEmpty {
            folders = cachedFolders
        }

        Task.detached { [weak self] in
            let enumerated = AppEnumerator.enumerate()
            guard let self else { return }

            let hasOrdering = (try? self.database?.hasOrderingData()) ?? false
            let systemOrdering = SystemLaunchpadDB.readOrdering()

            let appsToSave: [AppEntry]
            let foldersToSave: [FolderEntry]

            if !hasOrdering {
                (appsToSave, foldersToSave) = self.applyOrdering(systemOrdering, to: enumerated)
            } else {
                (appsToSave, foldersToSave) = self.mergeNewApps(enumerated, systemOrdering: systemOrdering)
            }

            // Save folders first — apps reference folders via foreign key
            try? self.database?.saveFolders(foldersToSave)
            try? self.database?.saveApps(appsToSave)

            let validIDs = Set(enumerated.map(\.bundleIdentifier))
            try? self.database?.deleteStale(validIdentifiers: validIDs)

            // Clean up folders with no remaining apps
            let folderIDsWithApps = Set(appsToSave.compactMap(\.folderID))
            let staleFolderIDs = Set(foldersToSave.map(\.id)).subtracting(folderIDsWithApps)
            if !staleFolderIDs.isEmpty {
                let validFolderIDs = Set(foldersToSave.map(\.id)).subtracting(staleFolderIDs)
                try? self.database?.deleteStaleFolders(validIDs: validFolderIDs)
            }

            let sortedApps = (try? self.database?.fetchAllApps()) ?? appsToSave
            let sortedFolders = (try? self.database?.fetchAllFolders()) ?? foldersToSave

            await MainActor.run {
                self.apps = sortedApps
                self.folders = sortedFolders
            }
        }
    }

    private func applyOrdering(_ ordering: LaunchpadOrdering?, to apps: [AppEntry]) -> ([AppEntry], [FolderEntry]) {
        guard let ordering else {
            // No system DB — alphabetical fallback, no folders
            let sorted = apps.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            let result = sorted.enumerated().map { index, app in
                var app = app
                app.pageIndex = index / Grid.appsPerPage
                app.orderIndex = index % Grid.appsPerPage
                return app
            }
            return (result, [])
        }

        // Build set of apps that belong to folders
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
                // App belongs to a folder
                var app = app
                app.folderID = folderPos.folderID
                app.folderOrderIndex = folderPos.folderOrderIndex
                app.pageIndex = nil
                app.orderIndex = nil
                ordered.append(app)
            } else if let pos = ordering.appPositions[app.bundleIdentifier] {
                // Top-level app with known position
                var app = app
                app.pageIndex = pos.pageIndex
                app.orderIndex = pos.orderIndex
                ordered.append(app)
            } else {
                unordered.append(app)
            }
        }

        // Skip unordered apps — they are not in the system Launchpad DB
        // and should not be shown (e.g. background agents, uninstallers, helpers)

        return (ordered, newFolders)
    }

    private func mergeNewApps(_ enumerated: [AppEntry], systemOrdering: LaunchpadOrdering?) -> ([AppEntry], [FolderEntry]) {
        let existing = (try? database?.fetchAllApps()) ?? []
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.bundleIdentifier, $0) })
        var existingFolders = (try? database?.fetchAllFolders()) ?? []

        // If no folders or no apps linked to folders, (re)import from system DB
        var folderAppPositions: [String: (folderID: String, folderOrderIndex: Int)] = [:]
        let hasFolderApps = existing.contains { $0.folderID != nil }
        if (existingFolders.isEmpty || !hasFolderApps), let ordering = systemOrdering {
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

        for app in enumerated {
            if var existingApp = existingByID[app.bundleIdentifier] {
                existingApp.displayName = app.displayName
                existingApp.appPath = app.appPath
                existingApp.iconData = app.iconData
                // If we just imported folders, assign folder membership to existing apps
                if let folderPos = folderAppPositions[app.bundleIdentifier] {
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

        // Assign positions to new apps (top-level only)
        let topLevel = result.filter { $0.folderID == nil }
        let lastPage = max(
            topLevel.compactMap(\.pageIndex).max() ?? 0,
            existingFolders.map(\.pageIndex).max() ?? 0
        )
        let lastOrder = max(
            topLevel.filter { $0.pageIndex == lastPage }.compactMap(\.orderIndex).max() ?? -1,
            existingFolders.filter { $0.pageIndex == lastPage }.map(\.orderIndex).max() ?? -1
        )

        var nextOrder = lastOrder + 1
        var currentPage = lastPage

        for var app in newApps {
            // Check if this new app belongs to a folder
            if let folderPos = folderAppPositions[app.bundleIdentifier] {
                app.folderID = folderPos.folderID
                app.folderOrderIndex = folderPos.folderOrderIndex
                app.pageIndex = nil
                app.orderIndex = nil
            } else if let pos = systemOrdering?.appPositions[app.bundleIdentifier] {
                app.pageIndex = pos.pageIndex
                app.orderIndex = pos.orderIndex
            } else {
                if nextOrder >= Grid.appsPerPage {
                    currentPage += 1
                    nextOrder = 0
                }
                app.pageIndex = currentPage
                app.orderIndex = nextOrder
                nextOrder += 1
            }
            result.append(app)
        }

        return (result, existingFolders)
    }

    func launchApp(_ app: AppEntry) {
        let url = URL(fileURLWithPath: app.appPath)
        NSWorkspace.shared.open(url)
        hide()
    }

    func show() {
        currentPage = 0
        isVisible = true
    }

    func hide() {
        openFolderID = nil
        isVisible = false
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func openFolder(_ folder: FolderEntry) {
        openFolderID = folder.id
    }

    func closeFolder() {
        openFolderID = nil
    }
}
