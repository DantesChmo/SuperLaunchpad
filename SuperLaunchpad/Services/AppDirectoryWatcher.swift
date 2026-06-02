import Foundation

// Watches the application directories (`/Applications`, `/System/Applications`)
// and fires `onChange` whenever something is added/removed, so the launcher
// can rescan after the user installs or deletes an app.
//
// Uses POSIX-level file descriptors + GCD's `DispatchSource` — this is the
// supported macOS API for "give me a callback when this directory mutates".
// `FSEventStream` is an alternative, but `DispatchSource` is simpler when we
// only watch two known paths.
final class AppDirectoryWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private let onChange: () -> Void

    // `@escaping` because the closure is stored on the instance and called
    // long after `init` returns.
    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func start() {
        for path in AppEnumerator.directories {
            // `O_EVTONLY` opens the file descriptor purely as an event source —
            // it does NOT count towards the "this file is open" limit that
            // would, e.g., prevent the volume from being unmounted.
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                // `.write` here means "directory contents changed" (files
                // added/removed). It does NOT mean "a file was written into".
                eventMask: .write,
                queue: .main
            )
            source.setEventHandler { [weak self] in
                self?.onChange()
            }
            // Cancel handler runs when the source is cancelled — that is the
            // only place we close the fd, to keep ownership balanced.
            source.setCancelHandler {
                close(fd)
            }
            // DispatchSources are created in a suspended state — `resume()` is
            // mandatory or events never fire.
            source.resume()
            sources.append(source)
        }
    }

    func stop() {
        // `cancel()` triggers the cancel handler → fd is closed exactly once.
        sources.forEach { $0.cancel() }
        sources.removeAll()
    }
}
