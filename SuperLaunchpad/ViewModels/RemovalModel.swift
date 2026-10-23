import Foundation

// The × on an app in edit mode, or Move to Trash in its context menu, asks
// for confirmation, then moves the app to the Trash and drops it from the
// layout. A running app is quit first. Owned by `LaunchpadViewModel`.
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

        let app: AppEntry
        var stage: Stage
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
        guard isRemovable(app) else { return }
        let stage: PendingRemoval.Stage = launchpad.runningApps.isRunning(app) ? .appIsOpen : .confirm
        pendingRemoval = PendingRemoval(app: app, stage: stage)
    }

    func cancelRemoval() {
        pendingRemoval = nil
    }

    // The dialog's default button: moves the app to the Trash when asked to
    // (quitting it first if it is open), otherwise just closes the dialog.
    // Finder's password prompt would open behind the launcher, so the
    // launcher hides before Finder is asked; a failure there shows its
    // dialog when the launcher opens next.
    func confirmRemoval(hideLauncher: () -> Void) async {
        guard let removal = pendingRemoval else { return }
        switch removal.stage {
        case .confirm:
            break
        case .appIsOpen:
            guard await quitBeforeRemoval(removal.app) else { return }
        case .quitting:
            return
        case .didNotQuit, .failed:
            pendingRemoval = nil
            return
        }
        pendingRemoval = nil
        let app = removal.app
        do {
            if trash.needsAuthorization(app.appPath) {
                hideLauncher()
                try? await Task.sleep(for: .seconds(AnimationDuration.hide + AnimationDuration.orderOutSlack))
                try trash.moveToTrashWithFinder(app.appPath)
            } else {
                try trash.moveToTrash(app.appPath)
            }
        } catch AppTrash.Failure.cancelled {
            return
        } catch {
            let failure = error as? AppTrash.Failure ?? .other(error.localizedDescription)
            pendingRemoval = PendingRemoval(app: app, stage: .failed(failure))
            return
        }
        dropUninstalledApp(app.bundleIdentifier)
    }

    // False if the dialog was closed meanwhile (the app still gets the quit
    // request), or the app didn't quit in time; the dialog then says so.
    private func quitBeforeRemoval(_ app: AppEntry) async -> Bool {
        let quitting = PendingRemoval(app: app, stage: .quitting)
        pendingRemoval = quitting
        launchpad.runningApps.quit(app)
        let quit = await launchpad.runningApps.waitUntilQuit(app, timeout: quitTimeout)
        guard pendingRemoval == quitting else { return false }
        guard quit else {
            pendingRemoval = PendingRemoval(app: app, stage: .didNotQuit)
            return false
        }
        return true
    }

    // Takes an app that is gone from disk out of the layout right away,
    // without waiting for the directory watcher's rescan (which doesn't see
    // subfolders like /Applications/Utilities).
    @discardableResult
    func dropUninstalledApp(_ appID: String) -> Bool {
        guard launchpad.applyEdit({ $0.delete(appID) }) else { return false }
        launchpad.apps.removeAll { $0.bundleIdentifier == appID }
        try? launchpad.database?.deleteApp(bundleIdentifier: appID)
        return true
    }
}
