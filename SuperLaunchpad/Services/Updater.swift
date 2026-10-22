import Foundation
import Sparkle

// Sparkle 2 auto-updates. The feed URL and EdDSA public key come from Info.plist
// (`SUFeedURL`, `SUPublicEDKey`); the key is the `SPARKLE_PUBLIC_ED_KEY` build
// setting, which release CI fills in. Without a key (local builds, CI without the
// variable) the updater never starts: Sparkle would reject every update and show
// an error on each check.
@MainActor
@Observable
final class Updater {
    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    // Sparkle disables checking while a check or an update is in progress.
    private(set) var canCheckForUpdates = false

    var automaticallyChecksForUpdates = false {
        didSet {
            controller?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    var isAvailable: Bool { controller != nil }

    init() {
        guard Self.hasPublicKey, !UserDefaults.standard.bool(forKey: "UITestMode") else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            // Sparkle changes this on the main thread.
            MainActor.assumeIsolated {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    private static var hasPublicKey: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
