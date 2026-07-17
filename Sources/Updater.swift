import AppKit
import Sparkle

/// Owns Sparkle's scheduled and user-initiated update checks.
final class Updater {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Forces the shared updater to initialize during app launch.
    func start() {}

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
