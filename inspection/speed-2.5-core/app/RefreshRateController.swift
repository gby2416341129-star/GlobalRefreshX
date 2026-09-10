import UIKit

/// Experimental aggressive refresh policy for iOS 26/27.
///
/// Standard / VideoCall route:
/// - one empty hard-max CADisplayLink on `.common` remains the foreground/background/PiP anchor;
/// - deliberately avoids UIUpdateLink on iOS 27.0 because the system-level update hook is
///   too early/fragile for a sideloaded app launch path and can terminate the process before UI appears.
///
/// Compatibility / PlayerLayer route releases the app-level hard-max display link so the
/// media cadence can arbitrate without competing with the Standard route policy.
enum FrameRatePreference {
    static let didChangeNotification = Notification.Name("speed.refreshRatePolicyDidChange")
    static var isHighRefreshEnabled: Bool { true }
    static var targetFrameRate: Int { min(120, AppDisplayContext.maximumFramesPerSecond) }

    static func preferredFrameRateValue(target: Float) -> Float { target }
}

enum RefreshRuntimeMode: Equatable {
    case videoCall
    case playerLayer
}

enum RefreshDriverMode: String, CaseIterable, Equatable {
    case cadisplayLink
    case uiUpdateLink
    case hybrid

    var title: String {
        switch self {
        case .cadisplayLink: return "CADisplayLink"
        case .uiUpdateLink: return "UIUpdateLink"
        case .hybrid: return "Hybrid"
        }
    }
}

enum AppDisplayContext {
    // SceneDelegate registers the live scene once. This keeps display-clock hot paths from
    // walking UIApplication.connectedScenes on every geometry submission. The fallback is
    // retained for transient launch/reconnect windows before registration has happened.
    private static weak var registeredWindowScene: UIWindowScene?

    static func register(_ scene: UIWindowScene) {
        registeredWindowScene = scene
    }

    static func unregister(_ scene: UIWindowScene) {
        if registeredWindowScene === scene { registeredWindowScene = nil }
    }

    static var activeWindowScene: UIWindowScene? {
        if let registeredWindowScene { return registeredWindowScene }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
    }

    static var screen: UIScreen? { activeWindowScene?.screen }
    static var bounds: CGRect { screen?.bounds ?? .zero }
    static var scale: CGFloat { max(screen?.scale ?? 1, 1) }
    static var maximumFramesPerSecond: Int { max(screen?.maximumFramesPerSecond ?? 60, 60) }
}

@MainActor
final class RefreshRateController {
    static let shared = RefreshRateController()

    private let driverModeKey = "speed.refresh.driverMode"
    private var displayLink: CADisplayLink?
    private var updateLink: UIUpdateLink?
    private weak var anchorView: UIView?
    private var configuredFrameRate: Float = 0
    private(set) var runtimeMode: RefreshRuntimeMode = .videoCall
    private(set) var driverMode: RefreshDriverMode

    private init() {
        let raw = UserDefaults.standard.string(forKey: driverModeKey)
        driverMode = raw.flatMap(RefreshDriverMode.init(rawValue:)) ?? .cadisplayLink
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGovernorChange),
            name: SmartPerformanceGovernor.didChangeNotification,
            object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    var isRunning: Bool { displayLink != nil || updateLink?.isEnabled == true }

    func attach(to view: UIView) {
        anchorView = view
        reconcile()
    }

    func detach() {
        stop()
        anchorView = nil
    }

    func setDriverMode(_ mode: RefreshDriverMode) {
        guard driverMode != mode else { return }
        driverMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: driverModeKey)
        reconcile()
    }

    func setRuntimeMode(_ mode: RefreshRuntimeMode) {
        guard runtimeMode != mode else {
            reconcile()
            return
        }
        runtimeMode = mode
        reconcile()
    }

    func reconcile() {
        guard FrameRatePreference.isHighRefreshEnabled, runtimeMode == .videoCall else {
            stop()
            return
        }

        let governor = SmartPerformanceGovernor.shared.snapshot
        let effectiveMode: RefreshDriverMode
        if driverMode != .cadisplayLink && !governor.permitsContinuousRefreshExperiment {
            effectiveMode = .cadisplayLink
        } else {
            effectiveMode = driverMode
        }

        switch effectiveMode {
        case .cadisplayLink:
            stopUpdateLink()
            startOrUpdateHardMaxDisplayLink()
        case .uiUpdateLink:
            stopDisplayLink()
            startOrUpdateUIUpdateLink()
        case .hybrid:
            startOrUpdateHardMaxDisplayLink()
            startOrUpdateUIUpdateLink()
        }
    }

    func stop() {
        stopDisplayLink()
        stopUpdateLink()
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        configuredFrameRate = 0
    }

    private func stopUpdateLink() {
        updateLink?.isEnabled = false
        updateLink = nil
    }

    private func startOrUpdateHardMaxDisplayLink() {
        let requested = requestedFrameRate()
        if let displayLink {
            if configuredFrameRate != requested { configure(displayLink, requested: requested) }
            if displayLink.isPaused { displayLink.isPaused = false }
            return
        }
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        configure(link, requested: requested)
        link.add(to: .main, forMode: .common)
        link.isPaused = false
        displayLink = link
    }

    private func startOrUpdateUIUpdateLink() {
        guard let anchorView, anchorView.window != nil else { return }
        let requested = requestedFrameRate()
        if let updateLink {
            updateLink.preferredFrameRateRange = CAFrameRateRange(minimum: requested, maximum: requested, preferred: requested)
            updateLink.requiresContinuousUpdates = true
            updateLink.isEnabled = true
            return
        }
        let link = UIUpdateLink(view: anchorView, actionHandler: { _, _ in
            // Deliberately empty: the link expresses a refresh preference without adding per-frame work.
        })
        link.preferredFrameRateRange = CAFrameRateRange(minimum: requested, maximum: requested, preferred: requested)
        link.requiresContinuousUpdates = true
        link.isEnabled = true
        updateLink = link
    }

    private func requestedFrameRate() -> Float {
        Float(min(FrameRatePreference.targetFrameRate, AppDisplayContext.maximumFramesPerSecond))
    }

    private func configure(_ link: CADisplayLink, requested: Float) {
        link.preferredFrameRateRange = CAFrameRateRange(minimum: requested, maximum: requested, preferred: requested)
        configuredFrameRate = requested
    }

    @objc private func handleGovernorChange() { reconcile() }

    @objc private func step(_ link: CADisplayLink) {
        // Intentionally empty. Any main-thread work here steals from the 8.33 ms budget.
    }
}

// MARK: - Laboratory / latency experiments

/// User-controlled iOS 26/27 UIUpdateLink experiments.
///
/// Important design rule: this controller is completely separate from Speed's
/// production CADisplayLink policy above.  It creates no UIUpdateLink during
/// launch, so the stable 120 Hz path stays exactly as before until the user
/// explicitly enables an experiment from the Laboratory page.
struct LatencyExperimentState: Equatable {
    var lowLatencyEventDispatchEnabled = false
    var immediatePresentationEnabled = false
    var continuousUpdatesEnabled = false
    var directCompatibilityResizeEnabled = false
    var refreshDriverMode: RefreshDriverMode = .cadisplayLink
    var updateLinkActive = false

    var anyPreferenceEnabled: Bool {
        lowLatencyEventDispatchEnabled
            || immediatePresentationEnabled
            || continuousUpdatesEnabled
            || directCompatibilityResizeEnabled
            || refreshDriverMode != .cadisplayLink
    }

    var allPreferencesEnabled: Bool {
        lowLatencyEventDispatchEnabled
            && immediatePresentationEnabled
            && continuousUpdatesEnabled
            && directCompatibilityResizeEnabled
            && refreshDriverMode == .hybrid
    }
}

@MainActor
final class LatencyExperimentController {
    static let shared = LatencyExperimentController()

    private weak var anchorView: UIView?
    private var preferenceLink: UIUpdateLink?
    private var continuousLink: UIUpdateLink?
    private let directCompatibilityResizeKey = "speed.lab.directCompatibilityResize"
    private var rebuildGeneration: UInt = 0
    private(set) var state = LatencyExperimentState()

    private init() {
        state.refreshDriverMode = RefreshRateController.shared.driverMode
        state.directCompatibilityResizeEnabled = UserDefaults.standard.bool(forKey: directCompatibilityResizeKey)
    }

    func attach(to view: UIView) {
        anchorView = view
        if state.anyPreferenceEnabled {
            scheduleRebuild()
        }
    }

    func setLowLatencyEventDispatchEnabled(_ enabled: Bool) {
        guard state.lowLatencyEventDispatchEnabled != enabled else { return }
        state.lowLatencyEventDispatchEnabled = enabled
        scheduleRebuild()
    }

    func setImmediatePresentationEnabled(_ enabled: Bool) {
        guard state.immediatePresentationEnabled != enabled else { return }
        state.immediatePresentationEnabled = enabled
        scheduleRebuild()
    }

    func setContinuousUpdatesEnabled(_ enabled: Bool) {
        guard state.continuousUpdatesEnabled != enabled else { return }
        state.continuousUpdatesEnabled = enabled
        scheduleRebuild()
    }

    func setDirectCompatibilityResizeEnabled(_ enabled: Bool) {
        guard state.directCompatibilityResizeEnabled != enabled else { return }
        state.directCompatibilityResizeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: directCompatibilityResizeKey)
    }

    func setRefreshDriverMode(_ mode: RefreshDriverMode) {
        guard state.refreshDriverMode != mode else { return }
        state.refreshDriverMode = mode
        RefreshRateController.shared.setDriverMode(mode)
    }

    func setAllEnabled(_ enabled: Bool) {
        state.lowLatencyEventDispatchEnabled = enabled
        state.immediatePresentationEnabled = enabled
        state.continuousUpdatesEnabled = enabled
        state.directCompatibilityResizeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: directCompatibilityResizeKey)
        state.refreshDriverMode = enabled ? .hybrid : .cadisplayLink
        RefreshRateController.shared.setDriverMode(state.refreshDriverMode)
        scheduleRebuild()
    }

    func reconcile() {
        guard state.anyPreferenceEnabled else {
            stopLinks()
            return
        }
        let preferenceNeeded = state.lowLatencyEventDispatchEnabled || state.immediatePresentationEnabled
        let preferenceOK = !preferenceNeeded || preferenceLink?.isEnabled == true
        let continuousOK = !state.continuousUpdatesEnabled || continuousLink?.isEnabled == true
        if !preferenceOK || !continuousOK {
            scheduleRebuild()
        }
    }

    func detach() {
        rebuildGeneration &+= 1
        stopLinks(resetPreferences: false)
        anchorView = nil
    }

    func stopForTeardown() {
        detach()
        state = LatencyExperimentState()
    }

    private func scheduleRebuild() {
        rebuildGeneration &+= 1
        let generation = rebuildGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.rebuildGeneration else { return }
            self.rebuildLinks()
        }
    }

    private func rebuildLinks() {
        stopLinks(resetPreferences: false)

        guard state.anyPreferenceEnabled,
              let anchorView,
              let windowScene = anchorView.window?.windowScene
        else {
            state.updateLinkActive = false
            return
        }

        if state.lowLatencyEventDispatchEnabled || state.immediatePresentationEnabled {
            let link = UIUpdateLink(windowScene: windowScene)
            let target = Float(FrameRatePreference.targetFrameRate)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: target, maximum: target, preferred: target)
            if state.lowLatencyEventDispatchEnabled {
                link.wantsLowLatencyEventDispatch = true
            }
            if state.immediatePresentationEnabled {
                link.wantsImmediatePresentation = true
            }
            link.isEnabled = true
            preferenceLink = link
        }

        if state.continuousUpdatesEnabled && SmartPerformanceGovernor.shared.snapshot.permitsContinuousRefreshExperiment {
            let link = UIUpdateLink(view: anchorView, actionHandler: { _, _ in
                // Intentionally empty. The continuous link itself is the experiment.
                // Speed's existing stable CADisplayLink remains responsible for the 120 Hz preference.
            })
            let target = Float(FrameRatePreference.targetFrameRate)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: target, maximum: target, preferred: target)
            link.requiresContinuousUpdates = true
            link.isEnabled = true
            continuousLink = link
        }

        state.updateLinkActive = (preferenceLink?.isEnabled == true) || (continuousLink?.isEnabled == true)
        AppDebugLogger.log(
            "Laboratory links active: lowLatency=\(state.lowLatencyEventDispatchEnabled), "
            + "immediate=\(state.immediatePresentationEnabled), continuous=\(state.continuousUpdatesEnabled)"
        )
    }

    private func stopLinks(resetPreferences: Bool = false) {
        preferenceLink?.isEnabled = false
        preferenceLink = nil
        continuousLink?.isEnabled = false
        continuousLink = nil
        state.updateLinkActive = false
        if resetPreferences {
            state = LatencyExperimentState()
        }
    }
}
