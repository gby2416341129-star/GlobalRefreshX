import Foundation

/// Owns delayed PiP transition work so retry/timeout/watchdog jobs cannot overlap accidentally.
/// All operations are expected on the main thread because the scheduled work mutates UIKit/AVKit state.
final class PiPTaskScheduler {
    enum Slot: Hashable {
        case startRetry
        case startTimeout
        case transitionWatchdog
        case playerLayerAudioRelease
        case playerLayerGeometryPreview
        case launchPendingNotificationAlert
        case engineRouteSwitchSettle
        case foregroundWindowRestore
        case autoHideAfterStart
    }

    private let scheduler = DelayedTaskScheduler<Slot>()

    func schedule(
        _ slot: Slot,
        after delay: TimeInterval,
        on queue: DispatchQueue = .main,
        action: @escaping () -> Void
    ) {
        scheduler.schedule(slot, after: delay, on: queue, action: action)
    }

    func cancel(_ slot: Slot) {
        scheduler.cancel(slot)
    }

    func cancelAll() {
        scheduler.cancelAll()
    }

    func isScheduled(_ slot: Slot) -> Bool {
        scheduler.isScheduled(slot)
    }
}
