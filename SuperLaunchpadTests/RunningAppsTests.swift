import Foundation
import Testing
@testable import SuperLaunchpad

// Stands in for NSWorkspace: the processes it lists, launches and
// terminations it reports, and the quit requests it gets. Nothing real is
// ever quit.
@MainActor
final class FakeWorkspace {
    private(set) var processes: [RunningApps.Process] = []
    // Quit requests, by process ID, and whether they were forced.
    private(set) var terminateRequests: [(id: pid_t, force: Bool)] = []
    // False: a quit request is ignored, like an app asking to save changes.
    // A forced one always ends the process.
    var quitsOnRequest = true
    private var handler: ((RunningApps.Event) -> Void)?
    private var nextID: pid_t = 100

    init(_ processes: [RunningApps.Process] = []) {
        self.processes = processes
    }

    // Holds the fake, so `FakeWorkspace().source` stays usable.
    var source: RunningApps.Source {
        RunningApps.Source(
            current: { self.processes },
            observe: { handler in
                self.handler = handler
                return NSObject()
            },
            terminate: { process, force in
                self.terminateRequests.append((process.id, force))
                if force || self.quitsOnRequest {
                    self.terminate(process)
                }
            }
        )
    }

    static func process(_ bundleID: String?, path: String? = nil, id: pid_t = 1) -> RunningApps.Process {
        RunningApps.Process(
            id: id,
            bundleIdentifier: bundleID,
            bundlePath: path ?? bundleID.map { "/Applications/\($0).app" }
        )
    }

    @discardableResult
    func launch(_ bundleID: String?, path: String? = nil) -> RunningApps.Process {
        nextID += 1
        let process = Self.process(bundleID, path: path, id: nextID)
        processes.append(process)
        handler?(.launched(process))
        return process
    }

    func terminate(_ process: RunningApps.Process) {
        processes.removeAll { $0 == process }
        handler?(.terminated(process))
    }
}

@MainActor
struct RunningAppsTests {

    private func app(_ bundleID: String, path: String? = nil) -> AppEntry {
        AppEntry(bundleIdentifier: bundleID, displayName: bundleID, appPath: path ?? "/Applications/\(bundleID).app")
    }

    // MARK: - State

    @Test func startsFromTheCurrentProcesses() {
        let workspace = FakeWorkspace([FakeWorkspace.process("a")])
        let running = RunningApps(source: workspace.source)

        #expect(running.isRunning(app("a")))
        #expect(!running.isRunning(app("b")))
    }

    @Test func followsLaunchesAndTerminations() {
        let workspace = FakeWorkspace()
        let running = RunningApps(source: workspace.source)
        #expect(!running.isRunning(app("a")))

        let process = workspace.launch("a")
        #expect(running.isRunning(app("a")))

        workspace.terminate(process)
        #expect(!running.isRunning(app("a")))
    }

    @Test func runsUntilItsLastInstanceQuits() {
        let workspace = FakeWorkspace()
        let running = RunningApps(source: workspace.source)
        let first = workspace.launch("a")
        let second = workspace.launch("a")

        workspace.terminate(first)
        #expect(running.isRunning(app("a")))
        workspace.terminate(second)
        #expect(!running.isRunning(app("a")))
    }

    // A process without a bundle ID, or with another one than the scan
    // recorded, still matches by where its bundle is.
    @Test(arguments: [
        (nil, "/Applications/Tool.app"),
        ("com.other.id", "/Applications/Tool.app"),
        (nil, "/Applications/./Tool.app/")
    ] as [(String?, String)])
    func matchesByBundlePathWithoutTheBundleID(bundleID: String?, path: String) {
        let workspace = FakeWorkspace([FakeWorkspace.process(bundleID, path: path)])
        let running = RunningApps(source: workspace.source)

        #expect(running.isRunning(app("com.tool", path: "/Applications/Tool.app")))
        #expect(!running.isRunning(app("com.tool", path: "/Applications/Other.app")))
    }

    @Test func matchesByBundleIDWherever() {
        let workspace = FakeWorkspace([FakeWorkspace.process("a", path: "/Users/me/Downloads/A.app")])
        let running = RunningApps(source: workspace.source)

        #expect(running.isRunning(app("a")))
    }

    // MARK: - Quitting

    @Test func quitAsksEveryInstanceAndForceQuitForces() {
        let workspace = FakeWorkspace()
        workspace.quitsOnRequest = false
        let running = RunningApps(source: workspace.source)
        let first = workspace.launch("a")
        let second = workspace.launch("a")
        workspace.launch("b")

        running.quit(app("a"))
        #expect(Set(workspace.terminateRequests.map(\.id)) == [first.id, second.id])
        #expect(workspace.terminateRequests.allSatisfy { !$0.force })
        #expect(running.isRunning(app("a")))

        running.quit(app("a"), force: true)
        #expect(workspace.terminateRequests.suffix(2).allSatisfy { $0.force })
        #expect(!running.isRunning(app("a")))
        #expect(running.isRunning(app("b")))
    }

    @Test func quitOfAnAppThatIsNotRunningDoesNothing() {
        let workspace = FakeWorkspace()
        let running = RunningApps(source: workspace.source)

        running.quit(app("a"))
        #expect(workspace.terminateRequests.isEmpty)
    }

    @Test func waitReturnsAtOnceForAnAppThatIsNotRunning() async {
        let running = RunningApps(source: FakeWorkspace().source)
        #expect(await running.waitUntilQuit(app("a"), timeout: .seconds(10)))
    }

    @Test func waitEndsWhenTheAppTerminates() async {
        let workspace = FakeWorkspace()
        let running = RunningApps(source: workspace.source)
        let process = workspace.launch("a")

        Task { workspace.terminate(process) }
        #expect(await running.waitUntilQuit(app("a"), timeout: .seconds(10)))
    }

    @Test func waitGivesUpAfterTheTimeout() async {
        let workspace = FakeWorkspace()
        let running = RunningApps(source: workspace.source)
        workspace.launch("a")

        #expect(await !running.waitUntilQuit(app("a"), timeout: .milliseconds(20)))
        #expect(running.isRunning(app("a")))
    }

    @Test func otherAppsQuittingDontEndTheWait() async {
        let workspace = FakeWorkspace()
        let running = RunningApps(source: workspace.source)
        workspace.launch("a")
        let other = workspace.launch("b")

        Task { workspace.terminate(other) }
        #expect(await !running.waitUntilQuit(app("a"), timeout: .milliseconds(50)))
    }
}
