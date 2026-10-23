import Foundation

// The × on an app in edit mode, or Move to Trash in its context menu, asks
// for confirmation, then moves the app to the Trash and drops it from the
// layout. A running app is quit first. The selection bar does the same for
// several apps behind one dialog. Owned by `LaunchpadViewModel`.
@MainActor
@Observable
final class RemovalModel {
    private unowned let launchpad: LaunchpadViewModel

    init(launchpad: LaunchpadViewModel) {
        self.launchpad = launchpad
    }

    struct PendingRemoval: Equatable {
        enum Stage: Equatable {
            case confirm
            // Confirming quits the app, then moves it.
            case appIsOpen
            // Waiting for the app to quit; only Cancel works.
            case quitting
            // Still running after `quitTimeout`, likely asking to save changes.
            case didNotQuit
            case failed(AppTrash.Failure)
        }

        // One app, or the selected ones (multi-select).
        let apps: [AppEntry]
        var stage: Stage
        // Selected apps left out because they are part of macOS.
        var skippedCount = 0

        init(app: AppEntry, stage: Stage) {
            self.init(apps: [app], stage: stage)
        }

        init(apps: [AppEntry], stage: Stage, skippedCount: Int = 0) {
            self.apps = apps
            self.stage = stage
            self.skippedCount = skippedCount
        }

        var app: AppEntry { apps[0] }
        var isGroup: Bool { apps.count > 1 }
    }

    // The dialog on screen, if any.
    private(set) var pendingRemoval: PendingRemoval?
    @ObservationIgnored var trash = AppTrash.Operations.live
    @ObservationIgnored var quitTimeout = Duration.seconds(Uninstall.quitTimeout)

    // Asked for every icon's VoiceOver actions on render; the answer for a
    // path doesn't change, so the disk is asked once.
    @ObservationIgnored private var removableByPath: [String: Bool] = [:]

    func isRemovable(_ app: AppEntry) -> Bool {
        if let known = removableByPath[app.appPath] { return known }
        let removable = AppTrash.isRemovable(appPath: app.appPath)
        removableByPath[app.appPath] = removable
        return removable
    }

    // Apps that are part of macOS can't be removed: no ×, a disabled menu item.
    func requestRemoval(of app: AppEntry) {
        requestRemoval(of: [app])
    }

    // One dialog for all of them; apps that are part of macOS are skipped,
    // and nothing happens when none is left.
    func requestRemoval(of apps: [AppEntry]) {
        let removable = apps.filter { isRemovable($0) }
        guard !removable.isEmpty else { return }
        let stage: PendingRemoval.Stage = removable.contains { launchpad.runningApps.isRunning($0) } ? .appIsOpen : .confirm
        pendingRemoval = PendingRemoval(apps: removable, stage: stage, skippedCount: apps.count - removable.count)
    }

    func cancelRemoval() {
        pendingRemoval = nil
    }

    // The dialog's default button: moves the apps to the Trash when asked
    // to (quitting the open ones first), otherwise just closes the dialog.
    // Finder's password prompt would open behind the launcher, so the
    // launcher hides (once) before Finder is asked; a failure there shows its
    // dialog when the launcher opens next. A group stops at the first
    // failure; the apps already in the Trash leave the layout.
    func confirmRemoval(hideLauncher: () -> Void) async {
        guard let removal = pendingRemoval else { return }
        switch removal.stage {
        case .confirm:
            break
        case .appIsOpen:
            guard await quitBeforeRemoval(removal) else { return }
        case .quitting:
            return
        case .didNotQuit, .failed:
            pendingRemoval = nil
            return
        }
        pendingRemoval = nil
        let protected = Set(removal.apps.map(\.appPath).filter { trash.needsAuthorization($0) })
        if !protected.isEmpty {
            hideLauncher()
            try? await Task.sleep(for: .seconds(AnimationDuration.hide + AnimationDuration.orderOutSlack))
        }
        var trashed: [String] = []
        apps: for app in removal.apps {
            do {
                if protected.contains(app.appPath) {
                    try trash.moveToTrashWithFinder(app.appPath)
                } else {
                    try trash.moveToTrash(app.appPath)
                }
                trashed.append(app.bundleIdentifier)
            } catch AppTrash.Failure.cancelled {
                break apps
            } catch {
                let failure = error as? AppTrash.Failure ?? .other(error.localizedDescription)
                pendingRemoval = PendingRemoval(app: app, stage: .failed(failure))
                break apps
            }
        }
        dropUninstalledApps(trashed)
    }

    // Quits every open app of the removal and waits for all of them against
    // one `quitTimeout`. False if the dialog was closed meanwhile (the apps
    // still get the quit request), or one didn't quit in time; the dialog
    // then says so and nothing goes to the Trash.
    private func quitBeforeRemoval(_ removal: PendingRemoval) async -> Bool {
        let quitting = PendingRemoval(apps: removal.apps, stage: .quitting, skippedCount: removal.skippedCount)
        pendingRemoval = quitting
        let running = removal.apps.filter { launchpad.runningApps.isRunning($0) }
        for app in running {
            launchpad.runningApps.quit(app)
        }
        let deadline = ContinuousClock.now + quitTimeout
        var quit = true
        for app in running {
            let remaining = max(deadline - ContinuousClock.now, .zero)
            guard await launchpad.runningApps.waitUntilQuit(app, timeout: remaining) else {
                quit = false
                break
            }
        }
        guard pendingRemoval == quitting else { return false }
        guard quit else {
            pendingRemoval = PendingRemoval(apps: removal.apps, stage: .didNotQuit, skippedCount: removal.skippedCount)
            return false
        }
        return true
    }

    // Takes an app that is gone from disk out of the layout right away,
    // without waiting for the directory watcher's rescan (which doesn't see
    // subfolders like /Applications/Utilities).
    @discardableResult
    func dropUninstalledApp(_ appID: String) -> Bool {
        dropUninstalledApps([appID])
    }

    // All in one edit; apps not in the layout are left alone. False when
    // none of them was.
    @discardableResult
    func dropUninstalledApps(_ appIDs: [String]) -> Bool {
        let ids = Set(appIDs)
        guard launchpad.applyEdit({ layout in
            ids.filter { layout.location(of: .app($0)) != nil }.reduce(false) { layout.delete($1) || $0 }
        }) else { return false }
        launchpad.apps.removeAll { ids.contains($0.bundleIdentifier) }
        for id in ids {
            try? launchpad.database?.deleteApp(bundleIdentifier: id)
        }
        return true
    }
}
