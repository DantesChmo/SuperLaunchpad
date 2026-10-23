import AppKit
import SwiftUI

// Which apps are running, for the dot under their icons and the Quit items.
// Seeded from `NSWorkspace.runningApplications`, then kept current by the
// workspace's launch and termination notifications; nothing polls. An app on
// the grid matches a process by bundle ID, or else by bundle path.
@MainActor
@Observable
final class RunningApps {
    struct Process: Hashable {
        let id: pid_t
        let bundleIdentifier: String?
        let bundlePath: String?
    }

    enum Event {
        case launched(Process)
        case terminated(Process)
    }

    // Where processes come from; tests swap in their own.
    struct Source {
        var current: @MainActor () -> [Process]
        // Calls back on every launch and termination until the returned token
        // is released.
        var observe: @MainActor (@escaping @MainActor (Event) -> Void) -> AnyObject
        // Asks the process to quit, or kills it when forced.
        var terminate: @MainActor (Process, _ force: Bool) -> Void

        static var live: Source {
            Source(
                current: { NSWorkspace.shared.runningApplications.map(Process.init) },
                observe: { handler in LiveObservation(handler) },
                terminate: { process, force in
                    guard let app = NSRunningApplication(processIdentifier: process.id) else { return }
                    if force { app.forceTerminate() } else { app.terminate() }
                }
            )
        }
    }

    private let source: Source
    @ObservationIgnored private var observation: AnyObject?
    @ObservationIgnored private var processes: [pid_t: Process] = [:]
    // Derived from `processes`; what the icons read.
    private var bundleIdentifiers: Set<String> = []
    private var bundlePaths: Set<String> = []
    @ObservationIgnored private var quitWaiters: [QuitWaiter] = []

    init(source: Source) {
        self.source = source
        for process in source.current() {
            processes[process.id] = process
        }
        rebuild()
        observation = source.observe { [weak self] event in
            self?.handle(event)
        }
    }

    func isRunning(_ app: AppEntry) -> Bool {
        bundleIdentifiers.contains(app.bundleIdentifier) || bundlePaths.contains(Self.normalized(app.appPath))
    }

    // Every process of the app gets the request; one that asks to save
    // changes may still refuse.
    func quit(_ app: AppEntry, force: Bool = false) {
        for process in processes(of: app) {
            source.terminate(process, force)
        }
    }

    // True once no process of the app is left, false if one still runs after
    // `timeout`.
    func waitUntilQuit(_ app: AppEntry, timeout: Duration) async -> Bool {
        guard isRunning(app) else { return true }
        let waiter = QuitWaiter(app: app)
        quitWaiters.append(waiter)
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.finish(waiter, quit: false)
        }
        defer { timer.cancel() }
        // The body runs before the first suspension, so neither a
        // termination nor the timer can finish the waiter ahead of it.
        return await withCheckedContinuation { continuation in
            waiter.continuation = continuation
        }
    }

    private func processes(of app: AppEntry) -> [Process] {
        let path = Self.normalized(app.appPath)
        return processes.values.filter { process in
            process.bundleIdentifier == app.bundleIdentifier || process.bundlePath.map(Self.normalized) == path
        }
    }

    private func handle(_ event: Event) {
        switch event {
        case .launched(let process):
            processes[process.id] = process
        case .terminated(let process):
            processes[process.id] = nil
        }
        rebuild()
        for waiter in quitWaiters where !isRunning(waiter.app) {
            finish(waiter, quit: true)
        }
    }

    private func finish(_ waiter: QuitWaiter, quit: Bool) {
        guard let index = quitWaiters.firstIndex(where: { $0 === waiter }) else { return }
        quitWaiters.remove(at: index)
        waiter.resume(quit)
    }

    private func rebuild() {
        let identifiers = Set(processes.values.compactMap(\.bundleIdentifier))
        let paths = Set(processes.values.compactMap { $0.bundlePath.map(Self.normalized) })
        // Assigned only on change: every icon on screen reads these.
        if identifiers != bundleIdentifiers { bundleIdentifiers = identifiers }
        if paths != bundlePaths { bundlePaths = paths }
    }

    private static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

private extension RunningApps.Process {
    init(_ app: NSRunningApplication) {
        self.init(id: app.processIdentifier, bundleIdentifier: app.bundleIdentifier, bundlePath: app.bundleURL?.path)
    }
}

// One `waitUntilQuit` call, finished by a termination or by its timeout,
// whichever comes first.
@MainActor
private final class QuitWaiter {
    let app: AppEntry
    var continuation: CheckedContinuation<Bool, Never>?

    init(app: AppEntry) {
        self.app = app
    }

    func resume(_ quit: Bool) {
        continuation?.resume(returning: quit)
        continuation = nil
    }
}

// The workspace's own notification center, not `NotificationCenter.default`.
private final class LiveObservation {
    private var tokens: [NSObjectProtocol] = []

    init(_ handler: @escaping @MainActor (RunningApps.Event) -> Void) {
        let center = NSWorkspace.shared.notificationCenter
        let observe = { (name: Notification.Name, event: @escaping (RunningApps.Process) -> RunningApps.Event) in
            center.addObserver(forName: name, object: nil, queue: .main) { notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                let process = RunningApps.Process(app)
                // Delivered on `.main`, but the closure type is not main-actor isolated.
                MainActor.assumeIsolated {
                    handler(event(process))
                }
            }
        }
        tokens = [
            observe(NSWorkspace.didLaunchApplicationNotification, RunningApps.Event.launched),
            observe(NSWorkspace.didTerminateApplicationNotification, RunningApps.Event.terminated)
        ]
    }

    deinit {
        for token in tokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }
}

extension EnvironmentValues {
    // Read by app icons for the running dot.
    @Entry var runningApps: RunningApps?
}
