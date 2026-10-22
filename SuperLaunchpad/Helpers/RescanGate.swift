import Foundation

// Keeps at most one app rescan in flight. Requests that arrive while one is
// running are remembered and collapse into a single follow-up rescan, started
// as soon as the current one finishes.
//
// Without it, a burst of directory events started parallel scans, and on first
// launch each one imported the system folders under fresh UUIDs, duplicating
// them.
struct RescanGate {
    private(set) var isRunning = false
    private(set) var isPending = false

    // Returns true when the caller should start a rescan now.
    mutating func request() -> Bool {
        if isRunning {
            isPending = true
            return false
        }
        isRunning = true
        return true
    }

    // Call when a rescan finishes. Returns true when the caller should start
    // the follow-up rescan right away; the gate then stays running.
    mutating func finish() -> Bool {
        if isPending {
            isPending = false
            return true
        }
        isRunning = false
        return false
    }
}
