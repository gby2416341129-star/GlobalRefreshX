import Foundation

/// Single runtime truth source for Speed's PiP intent, AVKit confirmation and transition state.
///
/// The previous implementation split current intent, confirmed activity and transition timing
/// across several booleans in ViewController. Keeping those values here prevents stale UI or
/// persisted preferences from silently becoming runtime truth.
final class PiPLifecycleController {
    enum State: Equatable, CustomStringConvertible {
        case idle
        case starting(reason: String)
        case active(startedAt: Date)
        case stopping(reason: String)
        case failed(message: String)

        var description: String {
            switch self {
            case .idle: return "idle"
            case .starting(let reason): return "starting(\(reason))"
            case .active: return "active"
            case .stopping(let reason): return "stopping(\(reason))"
            case .failed(let message): return "failed(\(message))"
            }
        }
    }

    struct Transition: Equatable {
        let sequence: UInt64
        let startedAt: Date
        let reason: String
        let expectedActive: Bool
    }

    private(set) var state: State = .idle
    private(set) var transitionSequence: UInt64 = 0
    private(set) var lastTransitionAt = Date()
    private(set) var transition: Transition?

    // Runtime intent and AVKit-confirmed state live here, not in UserDefaults or UI state.
    private(set) var wantsActive = false
    private(set) var confirmedActive = false
    private(set) var suspendedAtSide = false

    var isActive: Bool { confirmedActive }
    var isTransitioning: Bool { transition != nil }
    var transitionStartedAt: Date? { transition?.startedAt }
    var transitionReason: String { transition?.reason ?? "未知" }
    var transitionExpectedActive: Bool? { transition?.expectedActive }

    func setIntent(active: Bool) {
        wantsActive = active
    }

    func setConfirmedActive(_ active: Bool) {
        confirmedActive = active
        if !active {
            suspendedAtSide = false
        }
    }

    func setSuspendedAtSide(_ suspended: Bool) {
        suspendedAtSide = confirmedActive && suspended
    }

    @discardableResult
    func beginTransition(expectedActive: Bool, reason: String) -> UInt64 {
        transitionSequence &+= 1
        let now = Date()
        transition = Transition(
            sequence: transitionSequence,
            startedAt: now,
            reason: reason,
            expectedActive: expectedActive
        )
        lastTransitionAt = now
        state = expectedActive ? .starting(reason: reason) : .stopping(reason: reason)
        AppDebugLogger.log("PiP lifecycle #\(transitionSequence): \(state.description)")
        return transitionSequence
    }

    func finishTransition() {
        transition = nil
        lastTransitionAt = Date()
    }

    @discardableResult
    func willStart(reason: String) -> UInt64 {
        if transition?.expectedActive != true {
            return beginTransition(expectedActive: true, reason: reason)
        }
        state = .starting(reason: reason)
        return transitionSequence
    }

    @discardableResult
    func didStart() -> UInt64 {
        wantsActive = true
        confirmedActive = true
        suspendedAtSide = false
        transition = nil
        transitionSequence &+= 1
        lastTransitionAt = Date()
        state = .active(startedAt: Date())
        AppDebugLogger.log("PiP lifecycle #\(transitionSequence): active")
        return transitionSequence
    }

    @discardableResult
    func willStop(reason: String) -> UInt64 {
        if transition?.expectedActive != false {
            return beginTransition(expectedActive: false, reason: reason)
        }
        state = .stopping(reason: reason)
        return transitionSequence
    }

    @discardableResult
    func didStop() -> UInt64 {
        wantsActive = false
        confirmedActive = false
        suspendedAtSide = false
        transition = nil
        transitionSequence &+= 1
        lastTransitionAt = Date()
        state = .idle
        AppDebugLogger.log("PiP lifecycle #\(transitionSequence): idle")
        return transitionSequence
    }

    @discardableResult
    func didFail(_ error: Error) -> UInt64 {
        wantsActive = false
        confirmedActive = false
        suspendedAtSide = false
        transition = nil
        transitionSequence &+= 1
        lastTransitionAt = Date()
        state = .failed(message: error.localizedDescription)
        AppDebugLogger.log("PiP lifecycle #\(transitionSequence): \(state.description)")
        return transitionSequence
    }

    @discardableResult
    func reset() -> UInt64 {
        wantsActive = false
        confirmedActive = false
        suspendedAtSide = false
        transition = nil
        transitionSequence &+= 1
        lastTransitionAt = Date()
        state = .idle
        return transitionSequence
    }
}
