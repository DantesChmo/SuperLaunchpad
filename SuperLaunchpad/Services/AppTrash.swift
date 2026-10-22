import AppKit

// Moves an app to the Trash, as dragging it there in Finder would. A bundle
// the user can't move (owned by root: App Store and .pkg installs) goes
// through Finder, which asks for an administrator password.
enum AppTrash {
    enum Failure: Error, Equatable {
        // The user cancelled Finder's password prompt.
        case cancelled
        // SuperLaunchpad may not control Finder (Privacy & Security → Automation).
        case finderNotPermitted
        case other(String)
    }

    // What the view model calls; tests swap in their own.
    struct Operations {
        var isRunning: (String) -> Bool
        var needsAuthorization: (String) -> Bool
        var moveToTrash: (String) throws -> Void
        var moveToTrashWithFinder: @MainActor (String) throws -> Void

        static var live: Operations {
            Operations(
                isRunning: AppTrash.isRunning(bundleIdentifier:),
                needsAuthorization: AppTrash.needsAuthorization(appPath:),
                moveToTrash: AppTrash.moveToTrash(appPath:),
                moveToTrashWithFinder: AppTrash.moveToTrashWithFinder(appPath:)
            )
        }
    }

    // False for apps that are part of macOS: everything under /System, and
    // /Applications/Safari.app, a link into the system cryptex.
    static func isRemovable(appPath: String) -> Bool {
        let resolved = URL(fileURLWithPath: appPath).resolvingSymlinksInPath().path
        return !resolved.hasPrefix("/System/")
    }

    static func isRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    // Moving a bundle to another folder takes write access to the bundle and
    // to the folder it is in.
    static func needsAuthorization(appPath: String) -> Bool {
        let fm = FileManager.default
        let folder = URL(fileURLWithPath: appPath).deletingLastPathComponent().path
        return !fm.isWritableFile(atPath: appPath) || !fm.isWritableFile(atPath: folder)
    }

    static func moveToTrash(appPath: String) throws {
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: appPath), resultingItemURL: nil)
        } catch {
            throw Failure.other(error.localizedDescription)
        }
    }

    // Blocks until Finder is done, including while it waits for the password.
    @MainActor
    static func moveToTrashWithFinder(appPath: String) throws {
        let quoted = appPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
            set target to POSIX file "\(quoted)" as alias
            with timeout of \(Uninstall.finderTimeout) seconds
                tell application "Finder" to delete target
            end timeout
            """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return }
        switch error[NSAppleScript.errorNumber] as? Int {
        case Int(userCanceledErr):
            throw Failure.cancelled
        case Int(errAEEventNotPermitted):
            throw Failure.finderNotPermitted
        default:
            throw Failure.other(error[NSAppleScript.errorMessage] as? String ?? "")
        }
    }
}
