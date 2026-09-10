import AppIntents
import Foundation

enum SpeedLaunchTarget: String, AppEnum {
    case open
    case start
    case startAndHide

    static var typeDisplayRepresentation = TypeDisplayRepresentation("Speed action")
    static var caseDisplayRepresentations: [SpeedLaunchTarget: DisplayRepresentation] = [
        .open: DisplayRepresentation("Open Speed"),
        .start: DisplayRepresentation("Start Speed"),
        .startAndHide: DisplayRepresentation("Start & Hide")
    ]
}

enum SpeedLaunchActionRouter {
    static let didSubmitNotification = Notification.Name("com.isil.speed.launch-action")
    private static let lock = NSLock()
    private static var pendingTarget: SpeedLaunchTarget?

    static func submit(_ target: SpeedLaunchTarget) {
        lock.lock()
        pendingTarget = target
        lock.unlock()
        NotificationCenter.default.post(name: didSubmitNotification, object: nil)
    }

    static func restorePending(_ target: SpeedLaunchTarget) {
        lock.lock()
        pendingTarget = target
        lock.unlock()
    }

    static func consumePendingTarget() -> SpeedLaunchTarget? {
        lock.lock()
        defer { lock.unlock() }
        let target = pendingTarget
        pendingTarget = nil
        return target
    }
}

struct SpeedLaunchIntent: OpenIntent {
    static var title: LocalizedStringResource = "Open Speed"
    static var description = IntentDescription("Open Speed and optionally start its floating-window performance engine.")

    @Parameter(title: "Action")
    var target: SpeedLaunchTarget

    init() { target = .open }
    init(target: SpeedLaunchTarget) { self.target = target }

    @MainActor
    func perform() async throws -> some IntentResult {
        SpeedLaunchActionRouter.submit(target)
        return .result()
    }
}
