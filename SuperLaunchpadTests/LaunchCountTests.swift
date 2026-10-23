import AppKit
import Foundation
import GRDB
import Testing
@testable import SuperLaunchpad

@MainActor
struct LaunchCountTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("slp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeTempDB() throws -> (AppDatabase, URL) {
        let dir = try makeTempDir()
        return (try AppDatabase(path: dir.appendingPathComponent("test.db").path), dir)
    }

    private func app(_ bundleID: String, order: Int, isNew: Bool = false, launches: Int = 0) -> AppEntry {
        AppEntry(
            bundleIdentifier: bundleID,
            displayName: bundleID,
            appPath: "/Applications/\(bundleID).app",
            pageIndex: 0,
            orderIndex: order,
            isNew: isNew,
            launchCount: launches
        )
    }

    private func makeViewModel(_ db: AppDatabase, apps: [AppEntry]) throws -> LaunchpadViewModel {
        try db.saveApps(apps)
        let vm = LaunchpadViewModel(database: db)
        vm.apps = try db.fetchAllApps()
        vm.itemActions.opener = AppOpener.Operations(open: { _, _ in }, showInFinder: { _ in })
        vm.show()
        return vm
    }

    private func storedCounts(_ db: AppDatabase) throws -> [String: Int] {
        Dictionary(uniqueKeysWithValues: try db.fetchAllApps().map { ($0.bundleIdentifier, $0.launchCount) })
    }

    // MARK: - Database

    // A v6 database is filled, then opened by `AppDatabase`, which runs v8.
    @Test func v8StartsExistingAppsAtZeroLaunches() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("test.db").path

        let queue = try DatabaseQueue(path: path)
        try AppDatabase.migrator.migrate(queue, upTo: "v6")
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO appEntry (bundleIdentifier, displayName, appPath, pageIndex, orderIndex, isNew) VALUES (?, ?, ?, ?, ?, ?)",
                arguments: ["com.a", "a", "/Applications/com.a.app", 0, 0, true]
            )
        }
        try queue.close()

        let db = try AppDatabase(path: path)
        let stored = try #require(try db.fetchAllApps().first)
        #expect(stored.launchCount == 0)
        #expect(stored.isNew)
    }

    @Test func launchCountRoundTripsThroughDatabase() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        try db.saveApps([app("com.a", order: 0, launches: 12), app("com.b", order: 1)])
        #expect(try storedCounts(db) == ["com.a": 12, "com.b": 0])
    }

    @Test func recordLaunchIncrementsOneAppAndClearsItsMark() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        try db.saveApps([app("com.a", order: 0, isNew: true, launches: 2), app("com.b", order: 1, isNew: true)])

        try db.recordLaunch(bundleIdentifier: "com.a")

        let byID = Dictionary(uniqueKeysWithValues: try db.fetchAllApps().map { ($0.bundleIdentifier, $0) })
        #expect(byID["com.a"]?.launchCount == 3)
        #expect(byID["com.a"]?.isNew == false)
        #expect(byID["com.b"]?.launchCount == 0)
        #expect(byID["com.b"]?.isNew == true)
    }

    @Test func rescanKeepsLaunchCount() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        try db.saveApps([app("com.a", order: 0, launches: 4)])
        let enumerated = [
            AppEntry(bundleIdentifier: "com.a", displayName: "A 2", appPath: "/Applications/com.a.app"),
            AppEntry(bundleIdentifier: "com.b", displayName: "b", appPath: "/Applications/com.b.app"),
        ]

        let (apps, _) = LaunchpadViewModel.syncScan(enumerated, systemOrdering: nil, placement: .end, database: db)

        #expect(apps.first { $0.bundleIdentifier == "com.a" }?.launchCount == 4)
        #expect(try storedCounts(db) == ["com.a": 4, "com.b": 0])
    }

    // MARK: - Launching from the launcher

    enum LaunchPath: CaseIterable {
        case returnInSearch, click, commandClick, menuOpen
    }

    @Test(arguments: LaunchPath.allCases)
    func everyLaunchCountsOnceAndClearsTheMark(path: LaunchPath) throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db, apps: [app("com.a", order: 0, isNew: true, launches: 1), app("com.b", order: 1)])
        let entry = try #require(vm.apps.first { $0.bundleIdentifier == "com.a" })

        switch path {
        case .returnInSearch: vm.itemActions.launchApp(entry)
        case .click: _ = vm.itemActions.click(entry, modifiers: [])
        case .commandClick: _ = vm.itemActions.click(entry, modifiers: .command)
        case .menuOpen: _ = vm.itemActions.perform(.open, on: entry)
        }

        let launched = try #require(vm.apps.first { $0.bundleIdentifier == "com.a" })
        #expect(launched.launchCount == 2)
        #expect(launched.isNew == false)
        #expect(try storedCounts(db) == ["com.a": 2, "com.b": 0])
    }

    @Test func showInFinderAndEditModeClicksDoNotCount() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db, apps: [app("com.a", order: 0)])
        let entry = try #require(vm.apps.first)

        _ = vm.itemActions.click(entry, modifiers: [.option, .command])
        _ = vm.itemActions.perform(.showInFinder, on: entry)
        vm.editing.enterEditMode()
        _ = vm.itemActions.click(entry, modifiers: [])
        vm.itemActions.launchApp(entry)

        #expect(vm.apps.first?.launchCount == 0)
        #expect(try storedCounts(db) == ["com.a": 0])
    }

    @Test func launchesReorderSearchResults() throws {
        let (db, dir) = try makeTempDB()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = try makeViewModel(db, apps: [app("Safari", order: 0), app("Slack", order: 1)])
        vm.search.searchText = "s"
        #expect(vm.search.searchResults.map(\.name) == ["Safari", "Slack"])

        vm.recordLaunch("Slack")

        #expect(vm.search.searchResults.map(\.name) == ["Slack", "Safari"])
    }

    // MARK: - Frequently Used row

    private func withPreferences(showsFrequentApps: Bool, _ body: (Preferences) throws -> Void) throws {
        let suiteName = "LaunchCountTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = Preferences(defaults: defaults)
        preferences.showsFrequentApps = showsFrequentApps
        try body(preferences)
    }

    private func makeFrequentViewModel(_ preferences: Preferences, apps: [AppEntry]) -> LaunchpadViewModel {
        let vm = LaunchpadViewModel(database: nil)
        vm.apps = apps
        vm.search.preferences = preferences
        vm.itemActions.opener = AppOpener.Operations(open: { _, _ in }, showInFinder: { _ in })
        return vm
    }

    @Test func frequentRowIsEmptyWhileTheSettingIsOff() throws {
        try withPreferences(showsFrequentApps: false) { preferences in
            let vm = makeFrequentViewModel(preferences, apps: [app("com.a", order: 0, launches: 5)])
            vm.show()
            #expect(vm.search.frequentApps.isEmpty)
        }
    }

    @Test func frequentRowHoldsTheMostLaunchedVisibleApps() throws {
        try withPreferences(showsFrequentApps: true) { preferences in
            var apps = (0..<(FrequentApps.maxCount + 2)).map { app("com.app\($0)", order: $0, launches: $0) }
            apps.append(AppEntry(bundleIdentifier: "com.hidden", displayName: "hidden", appPath: "/Applications/hidden.app", isHidden: true, launchCount: 100))
            let vm = makeFrequentViewModel(preferences, apps: apps)

            vm.show()

            let expected = (2..<(FrequentApps.maxCount + 2)).reversed().map { "com.app\($0)" }
            #expect(vm.search.frequentApps.map(\.bundleIdentifier) == expected)
        }
    }

    @Test func frequentRowKeepsItsOrderUntilTheNextShow() throws {
        try withPreferences(showsFrequentApps: true) { preferences in
            let vm = makeFrequentViewModel(preferences, apps: [app("com.a", order: 0, launches: 2), app("com.b", order: 1, launches: 1)])
            vm.show()
            #expect(vm.search.frequentApps.map(\.bundleIdentifier) == ["com.a", "com.b"])

            _ = vm.itemActions.click(try #require(vm.search.frequentApps.last), modifiers: .command)
            _ = vm.itemActions.click(try #require(vm.search.frequentApps.last), modifiers: .command)

            #expect(vm.search.frequentApps.map(\.bundleIdentifier) == ["com.a", "com.b"])
            #expect(vm.search.frequentApps.last?.launchCount == 3)
            vm.hide()
            vm.show()
            #expect(vm.search.frequentApps.map(\.bundleIdentifier) == ["com.b", "com.a"])
        }
    }

    @Test func frequentRowDropsAppsHiddenOrRemovedWhileOpen() throws {
        try withPreferences(showsFrequentApps: true) { preferences in
            let vm = makeFrequentViewModel(
                preferences,
                apps: [app("com.a", order: 0, launches: 3), app("com.b", order: 1, launches: 2), app("com.c", order: 2, launches: 1)]
            )
            vm.show()

            #expect(vm.editing.hideApp("com.a"))
            vm.apps.removeAll { $0.bundleIdentifier == "com.c" }

            #expect(vm.search.frequentApps.map(\.bundleIdentifier) == ["com.b"])
        }
    }

    @Test func turningTheSettingOffEmptiesTheRowOnTheNextShow() throws {
        try withPreferences(showsFrequentApps: true) { preferences in
            let vm = makeFrequentViewModel(preferences, apps: [app("com.a", order: 0, launches: 1)])
            vm.show()
            #expect(vm.search.frequentApps.count == 1)

            vm.hide()
            preferences.showsFrequentApps = false
            vm.show()

            #expect(vm.search.frequentApps.isEmpty)
        }
    }
}
