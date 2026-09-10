//
//  ViewController.swift
//  pip_swift
//

import UIKit
import AVKit
import AVFoundation
import CoreMedia
import CoreVideo
import Compression
import SwiftUI

enum PiPEngineRoute: String, CaseIterable, Hashable {
    case auto
    case videoCall
    case playerLayerGenerated

    var usesPlayerLayer: Bool { self == .playerLayerGenerated }
    var isAuto: Bool { self == .auto }

    var diagnosticsName: String {
        switch self {
        case .auto: return "Auto"
        case .videoCall: return "VideoCallContentSource"
        case .playerLayerGenerated: return "PlayerLayerCanonicalH264"
        }
    }
}

enum AppAppearancePreference {
    private static let darkModeForcedKey = "pip.home.darkModeForced"
    private static let lightModeForcedKey = "pip.home.lightModeForced"

    static var isDarkModeForced: Bool {
        get { UserDefaults.standard.bool(forKey: darkModeForcedKey) }
        set {
            setForced(newValue, animated: false)
        }
    }

    static var isLightModeForced: Bool {
        UserDefaults.standard.bool(forKey: lightModeForcedKey)
    }

    static var isStyleForced: Bool {
        isDarkModeForced || isLightModeForced
    }

    static var preferredStyle: UIUserInterfaceStyle {
        if isDarkModeForced {
            return .dark
        }
        if isLightModeForced {
            return .light
        }
        return .unspecified
    }

    static func apply(to window: UIWindow?) {
        window?.overrideUserInterfaceStyle = preferredStyle
        window?.rootViewController?.overrideUserInterfaceStyle = preferredStyle
    }

    static func setForced(_ isForced: Bool, animated: Bool) {
        UserDefaults.standard.set(isForced, forKey: darkModeForcedKey)
        UserDefaults.standard.set(false, forKey: lightModeForcedKey)
        applyCurrentPreference(animated: animated)
    }

    static func setPreferredStyle(_ style: UIUserInterfaceStyle, animated: Bool) {
        switch style {
        case .dark:
            UserDefaults.standard.set(true, forKey: darkModeForcedKey)
            UserDefaults.standard.set(false, forKey: lightModeForcedKey)
        case .light:
            UserDefaults.standard.set(false, forKey: darkModeForcedKey)
            UserDefaults.standard.set(true, forKey: lightModeForcedKey)
        default:
            UserDefaults.standard.set(false, forKey: darkModeForcedKey)
            UserDefaults.standard.set(false, forKey: lightModeForcedKey)
        }
        applyCurrentPreference(animated: animated)
    }

    static func clearForcedStyle(animated: Bool) {
        UserDefaults.standard.set(false, forKey: darkModeForcedKey)
        UserDefaults.standard.set(false, forKey: lightModeForcedKey)
        applyCurrentPreference(animated: animated)
    }

    static func applyCurrentPreference(animated: Bool = false) {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)

        guard animated, !AppMotion.reduceMotionEnabled else {
            UIView.performWithoutAnimation {
                windows.forEach {
                    apply(to: $0)
                    requestAppearanceRedraw($0)
                }
            }
            return
        }

        // Snapshot only the currently visible content. Avoid recursively forcing layout
        // through the complete UIKit/SwiftUI hierarchy; that creates a large main-thread
        // spike exactly when the user expects a system-like appearance transition.
        let snapshots: [UIView] = windows.compactMap { window in
            guard let container = activeContentView(in: window),
                  let snapshot = container.snapshotView(afterScreenUpdates: false) else {
                return nil
            }
            snapshot.frame = container.bounds
            snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(snapshot)
            return snapshot
        }

        UIView.performWithoutAnimation {
            windows.forEach {
                apply(to: $0)
                requestAppearanceRedraw($0)
            }
        }

        let animator = AppMotion.makeAnimator(duration: AppMotion.Duration.quick, curve: .easeInOut) {
            snapshots.forEach { $0.alpha = 0 }
        }
        animator.addCompletion { _ in
            snapshots.forEach { $0.removeFromSuperview() }
            windows.forEach { requestAppearanceRedraw($0) }
        }
        animator.startAnimation()
    }

    private static func activeContentView(in window: UIWindow) -> UIView? {
        if let tabBarController = window.rootViewController as? UITabBarController,
           let selectedView = tabBarController.selectedViewController?.view {
            return selectedView
        }
        return window.rootViewController?.view
    }

    private static func requestAppearanceRedraw(_ window: UIWindow) {
        window.setNeedsLayout()
        window.setNeedsDisplay()
        guard let rootView = window.rootViewController?.view else { return }
        rootView.setNeedsLayout()
        rootView.setNeedsDisplay()
    }
}

private enum PlayerLayerPiPStartAudioMode {
    case ambientCategoryOnly
    case playbackCategoryOnly
    case playbackActive

    static var defaultStartupMode: PlayerLayerPiPStartAudioMode {
        // 9:39 / beta5 anchor: start with active playback so PiP is possible immediately,
        // then release the audio session after PiP starts.
        .playbackActive
    }

    var category: AVAudioSession.Category {
        switch self {
        case .ambientCategoryOnly:
            return .ambient
        case .playbackCategoryOnly, .playbackActive:
            return .playback
        }
    }

    var options: AVAudioSession.CategoryOptions {
        switch self {
        case .ambientCategoryOnly, .playbackCategoryOnly, .playbackActive:
            return .mixWithOthers
        }
    }

    var shouldActivateSession: Bool {
        switch self {
        case .ambientCategoryOnly, .playbackCategoryOnly:
            return false
        case .playbackActive:
            return true
        }
    }

    var logName: String {
        switch self {
        case .ambientCategoryOnly:
            return "ambient category only"
        case .playbackCategoryOnly:
            return "playback category only"
        case .playbackActive:
            return "playback active"
        }
    }
}

private final class PiPDelegateProxy: NSObject, AVPictureInPictureControllerDelegate {
    weak var owner: ViewController?

    init(owner: ViewController) {
        self.owner = owner
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        owner?.pictureInPictureControllerWillStartPictureInPicture(pictureInPictureController)
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        owner?.pictureInPictureControllerDidStartPictureInPicture(pictureInPictureController)
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        owner?.pictureInPictureControllerWillStopPictureInPicture(pictureInPictureController)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        owner?.pictureInPictureControllerDidStopPictureInPicture(pictureInPictureController)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        owner?.pictureInPictureController(pictureInPictureController, failedToStartPictureInPictureWithError: error)
    }
}

class ViewController: UIViewController, AVPictureInPictureControllerDelegate {

    private var playerLayer: AVPlayerLayer!
    private var pipController: AVPictureInPictureController!
    private lazy var pipDelegateProxy = PiPDelegateProxy(owner: self)
    private let pipLifecycle = PiPLifecycleController()
    private let pipEngine = PiPEngineController()
    private var pipSourceView: UIView!
    private var pipSourceWidthConstraint: NSLayoutConstraint?
    private var pipSourceHeightConstraint: NSLayoutConstraint?
    private var pipSourcePlacementConstraints: [NSLayoutConstraint] = []
    private var customView: UIView!
    private var textView: UITextView!
    private var clockLabel: UILabel!
    private var clockOverlayView: ClockOverlayView!
    private var pipContentTapGesture: UITapGestureRecognizer?
    private var videoCallContentController: UIViewController?
    private var hostingController: UIHostingController<PiPHomeView>?
    private var homeViewModel: SpeedHomeViewModel?
    private var scrollDisplayLink: CADisplayLink?
    private var clockDisplayLink: CADisplayLink?
    private var clockRenderTimer: Timer?
    private var lastScrollTimestamp: CFTimeInterval?
    private var lastClockTimestamp: CFTimeInterval?
    private var clockFrameCount = 0
    private var pendingMeasuredPiPFPS: Int?
    private var pendingMeasuredPiPFPSCount = 0
    private var pendingMeasuredPiPFPSStartedAt: CFTimeInterval?
    private var measuredPiPFPS: Int = 0
    private var lastClockOverlayTimeText = ""
    private var lastClockOverlayFPSText = ""
    private var lastClockRenderTick = -1
    private var lastBackgroundClockDiagnosticsTimestamp: CFTimeInterval?
    private var lastLoggedPiPSuspendedAtSide: Bool?
    private var windowsBeforePiPStart: Set<ObjectIdentifier> = []
    private var playerEndObserver: NSObjectProtocol?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var isLockScreenAudioBoostActive = false
    private var isPiPTransitioning: Bool { pipLifecycle.isTransitioning }
    private var isStoppingPiP = false
    private let pipTasks = PiPTaskScheduler()
    private var directCloseGestureRetryGeneration: UInt = 0
    private var legacyCustomViewAttachRetryGeneration: UInt = 0
    private var foregroundResignRetryGeneration: UInt = 0
    private var hasPrimedPlayerLayerPiPStart = false
    private var playerLayerPiPStartAudioMode: PlayerLayerPiPStartAudioMode = .defaultStartupMode
    private var isPlayerLayerAudioSessionSettled = true
    private var pipTransitionStartedAt: Date? { pipLifecycle.transitionStartedAt }
    private var pipTransitionReason: String { pipLifecycle.transitionReason }
    private var pipTransitionExpectedActive: Bool? { pipLifecycle.transitionExpectedActive }
    private var pipExpectedActiveBeforeStop: Bool?
    private var didRecoverStalePiPStop = false
    private var pendingPiPEngineRouteAfterStop: PiPEngineRoute?
    private var shouldResignForegroundAfterPiPClose = false
    private var isClosingPiPFromCustomContentTap = false
    private var windowsHiddenForPiPClose: [(window: UIWindow, alpha: CGFloat)] = []
    private weak var pipDirectCloseGestureHost: UIView?
    private var pipDirectCloseTapGesture: UITapGestureRecognizer?
    private var playerStallObserver: NSObjectProtocol?
    private var playerPauseObserver: NSKeyValueObservation?
    private var playerLayerTimeControlObserver: NSKeyValueObservation?
    private var playerLayerMediaRequestGeneration: UInt = 0
    private var pendingPlayerLayerPreviewHeight: CGFloat?
    private var lastPlayerLayerPreviewSubmissionAt: CFTimeInterval = 0
    private var playerLayerPreviewSubmissionInterval: CFTimeInterval {
        1.0 / max(30.0, SmartPerformanceGovernor.shared.snapshot.previewHz)
    }
    private var lastPlayerLayerPrefetchHeight: Int?
    private var lastPlayerLayerPipelineRecoveryAt: CFTimeInterval = 0
    private var recentPlayerLayerRecoveryCount = 0
    private var lastPlayerLayerRecoveryBurstStartedAt: CFTimeInterval = 0
    private var autoFallbackRestartAttempts = 0
    private var isAutoHiddenOverheadPaused = false
    private var isPreviewingPiPHeight = false
    private var isLegacyPlayerLayerFallbackActive = false
    private var isCompactPiPStyle = true
    private let clockFPSMeasureInterval: CFTimeInterval = 0.8
    private var isLoadingHomePreferences = false
    private var hasPreparedPiPInfrastructure = false
    private var wantsPiPActive: Bool {
        get { pipLifecycle.wantsActive }
        set { pipLifecycle.setIntent(active: newValue) }
    }
    private var isOwnPiPConfirmedActive: Bool {
        get { pipLifecycle.confirmedActive }
        set { pipLifecycle.setConfirmedActive(newValue) }
    }
    private var pipRuntimeStartedAt: Date?
    private var pipRuntimeDuration: TimeInterval = 0
    private var pipRuntimeStoppedAtText = "暂无"
    private var isPiPStatusInfoVisible = false {
        didSet {
            guard oldValue != isPiPStatusInfoVisible else { return }
            updateHomeView()
        }
    }
    private var overlayResetToken = 0
    private var isSettingsExpanded = true {
        didSet {
            guard oldValue != isSettingsExpanded else { return }
            updateHomeView()
        }
    }
    private var prefersTextScrolling = true
    private var isScrollingEnabled = false {
        didSet {
            guard oldValue != isScrollingEnabled else { return }
            if !isLoadingHomePreferences && !isClockModeEnabled {
                prefersTextScrolling = isScrollingEnabled
                UserDefaults.standard.set(isScrollingEnabled, forKey: userDefaultsScrollingEnabledKey)
            }
            updateHomeView()
        }
    }
    private var remembersPiPHeight = true {
        didSet {
            guard oldValue != remembersPiPHeight else { return }
            if !isLoadingHomePreferences {
                UserDefaults.standard.set(remembersPiPHeight, forKey: userDefaultsRememberPiPHeightKey)
            }
            if remembersPiPHeight && !isLoadingHomePreferences {
                saveCurrentPiPHeightPreference()
            }
            updateHomeView()
        }
    }
    private var requiresPiPCloseConfirmation = false {
        didSet {
            guard oldValue != requiresPiPCloseConfirmation else { return }
            if !isLoadingHomePreferences {
                UserDefaults.standard.set(requiresPiPCloseConfirmation, forKey: userDefaultsPiPCloseConfirmationKey)
            }
            updateHomeView()
        }
    }
    private var hidesPiPWhenDocked = false {
        didSet {
            guard oldValue != hidesPiPWhenDocked else { return }
            if !isLoadingHomePreferences {
                UserDefaults.standard.set(hidesPiPWhenDocked, forKey: userDefaultsHidePiPWhenDockedKey)
            }
            updateHomeView()
        }
    }
    private var shouldAutoHideAfterNextStart = false
    private var pipHeightAnimationDisplayLink: CADisplayLink?
    private var pipHeightAnimationStartTimestamp: CFTimeInterval = 0
    private var pipHeightAnimationStartHeight: CGFloat = 0
    private var pipHeightAnimationTargetHeight: CGFloat = 0
    private var lastSubmittedPiPSizeInPixels: CGSize?
    private var lastAppliedPiPSourceSizeInPixels: CGSize?
    private let pipHeightAnimationDuration: CFTimeInterval = 0.34
    private var isClockModeEnabled = false {
        didSet {
            guard oldValue != isClockModeEnabled else { return }
            if !isLoadingHomePreferences {
                UserDefaults.standard.set(isClockModeEnabled, forKey: userDefaultsClockModeEnabledKey)
            }
            configureRunningText()
            updateHomeView()
        }
    }
    private var isDarkModeForced = AppAppearancePreference.isDarkModeForced {
        didSet {
            guard oldValue != isDarkModeForced else { return }
            if !isLoadingHomePreferences && !isSyncingAppearancePreferenceState {
                AppAppearancePreference.setForced(
                    isDarkModeForced,
                    animated: shouldAnimateNextAppearancePreferenceChange
                )
            }
            updateHomeView()
        }
    }
    private var shouldAnimateNextAppearancePreferenceChange = false
    private var isSyncingAppearancePreferenceState = false
    private var isPiPStoppedNotificationEnabled = KeepAliveNotificationTester.isPiPStoppedNotificationEnabled {
        didSet {
            guard oldValue != isPiPStoppedNotificationEnabled else { return }
            if !isLoadingHomePreferences {
                KeepAliveNotificationTester.isPiPStoppedNotificationEnabled = isPiPStoppedNotificationEnabled
            }
            updateHomeView()
        }
    }
    private var isBackgroundInterruptionNotificationEnabled = KeepAliveNotificationTester.isBackgroundProbeEnabled {
        didSet {
            guard oldValue != isBackgroundInterruptionNotificationEnabled else { return }
            if !isLoadingHomePreferences {
                KeepAliveNotificationTester.isBackgroundProbeEnabled = isBackgroundInterruptionNotificationEnabled
            }
            updateHomeView()
        }
    }
    private var keepAliveNotificationFrequency = KeepAliveNotificationTester.probeFrequency {
        didSet {
            guard oldValue != keepAliveNotificationFrequency else { return }
            if !isLoadingHomePreferences {
                KeepAliveNotificationTester.probeFrequency = keepAliveNotificationFrequency
            }
            updateHomeView()
        }
    }
    private var keepsPiPStatusInfoPersistent = false {
        didSet {
            guard oldValue != keepsPiPStatusInfoPersistent else { return }
            if !isLoadingHomePreferences {
                UserDefaults.standard.set(keepsPiPStatusInfoPersistent, forKey: userDefaultsPiPStatusInfoPersistentKey)
            }
            // Persistence now controls whether an already-open status card stays open.
            // It must never force the card open by itself; the previous behavior caused
            // the status popover to sit over the home controls after launch.
            if !keepsPiPStatusInfoPersistent {
                isPiPStatusInfoVisible = false
            }
            updateHomeView()
        }
    }
    private var pipEngineRoute: PiPEngineRoute = .videoCall {
        didSet {
            guard oldValue != pipEngineRoute else { return }
            if !isLoadingHomePreferences {
                UserDefaults.standard.set(pipEngineRoute.rawValue, forKey: userDefaultsPiPEngineRouteKey)
                UserDefaults.standard.set(pipEngineRoute.usesPlayerLayer, forKey: userDefaultsPlayerLayerRouteEnabledKey)
            }
            RefreshRateController.shared.setRuntimeMode(
                shouldUseCompatibilityRefreshPolicy ? .playerLayer : .videoCall
            )
            if shouldUsePlayerLayerPiPCompatibility {
                // Prime only the current neighborhood. Full-bank materialization created
                // needless CPU and file I/O spikes when switching into Compatibility mode.
                PlaceholderVideoFactory.prefetchPlayerLayerBackingVideos(
                    around: clampedPiPHeight,
                    direction: 0,
                    policy: SmartPerformanceGovernor.shared.snapshot
                )
            } else if oldValue.usesPlayerLayer || oldValue == .auto {
                // Leaving Compatibility must also stop obsolete encodes. A completed file is
                // harmless, but continuing 1,800-frame work after the user left the route can
                // steal CPU/GPU scheduling headroom from the Standard 120 Hz path.
                PlaceholderVideoFactory.cancelPendingPlayerLayerMediaWork()
            }
            if !shouldUsePlayerLayerPiPCompatibility, isExtremeSilentModeEnabled {
                isExtremeSilentModeEnabled = false
            }
            applyExtremeSilentModeIfNeeded(reason: "底层切换")
            updateHomeView()
        }
    }
    private var isExtremeSilentModeEnabled = false {
        didSet {
            guard oldValue != isExtremeSilentModeEnabled else { return }
            if !isLoadingHomePreferences {
                UserDefaults.standard.set(isExtremeSilentModeEnabled, forKey: userDefaultsExtremeSilentModeEnabledKey)
            }
            if isExtremeSilentModeEnabled, isContentExtremeModeEnabled {
                isContentExtremeModeEnabled = false
            }
            applyExtremeSilentModeIfNeeded(reason: "纯净模式切换")
            updateHomeView()
        }
    }
    private var isContentExtremeModeEnabled = false {
        didSet {
            guard oldValue != isContentExtremeModeEnabled else { return }
            if !isLoadingHomePreferences {
                UserDefaults.standard.set(isContentExtremeModeEnabled, forKey: userDefaultsContentExtremeModeEnabledKey)
            }
            if isContentExtremeModeEnabled, isExtremeSilentModeEnabled {
                isExtremeSilentModeEnabled = false
            }
            applyContentExtremeModeIfNeeded(reason: "内容极限模式切换")
            updateHomeView()
        }
    }
    private lazy var pipHeight: CGFloat = compactPiPHeight
    private var isPiPActiveForUI = false {
        didSet {
            guard oldValue != isPiPActiveForUI else { return }
            updateHomeView(animated: true)
        }
    }
    private lazy var clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.S"
        return formatter
    }()

    private let textPiPWidth: CGFloat = 300
    private let clockPiPWidth: CGFloat = 200
    // Speed production UI no longer exposes the legacy clock surface. Keeping it
    // compile-time disabled prevents stale user defaults from resurrecting a second
    // persistent CADisplayLink beside the single hard-max refresh request.
    private let isClockModeFeatureEnabled = false
    private let defaultPiPHeight: CGFloat = 120
    private let compactPiPHeight: CGFloat = PiPGeometryController.shared.videoCallMetrics.defaultHeight
    private let playerLayerDefaultPiPHeight: CGFloat = PiPGeometryController.shared.playerLayerMetrics.defaultHeight
    private var currentDefaultPiPHeight: CGFloat {
        let compatibility = shouldUseCompatibilityRefreshPolicy
        let fallback = compatibility ? playerLayerDefaultPiPHeight : defaultPiPHeight
        return clampedHeight(HeightProfileStore.defaultHeight(isCompatibility: compatibility, fallback: fallback))
    }
    private var currentCompactPiPHeight: CGFloat { currentGeometryMetrics.defaultHeight }
    private let playerLayerAudioReleaseDelay: TimeInterval = 0.25
    private let playerLayerActivePlaybackFallbackAttempt = 8
    private let userDefaultsScrollingEnabledKey = "pip.home.scrollingEnabled"
    private let userDefaultsRememberPiPHeightKey = "pip.home.rememberPiPHeight"
    private let userDefaultsClockModeEnabledKey = "pip.home.clockModeEnabled"
    private let userDefaultsClockModeDefaultMigrationKey = "pip.home.clockModeDefaultMigration.v1"
    private let userDefaultsClockModeDefaultTextMigrationKey = "pip.home.clockModeDefaultMigration.v2.textDefault"
    private let userDefaultsPiPHeightKey = "pip.home.rememberedPiPHeight"
    private let userDefaultsPiPRuntimeStartedAtKey = "pip.home.runtimeStartedAt"
    private let userDefaultsPiPRuntimeDurationKey = "pip.home.runtimeDuration"
    private let userDefaultsPiPRuntimeWasActiveKey = "pip.home.runtimeWasActive"
    private let userDefaultsPiPRuntimeStoppedAtTextKey = "pip.home.runtimeStoppedAtText"
    private let userDefaultsPiPRuntimeLastConfirmedAtKey = "pip.home.runtimeLastConfirmedAt"
    private let userDefaultsPiPStatusInfoPersistentKey = "pip.home.pipStatusInfoPersistent"
    private let userDefaultsPiPEngineRouteKey = "pip.home.engineRoute"
    private let userDefaultsPlayerLayerRouteEnabledKey = "pip.home.playerLayerRouteEnabled"
    private let userDefaultsExtremeSilentModeEnabledKey = "pip.home.extremeSilentModeEnabled"
    private let userDefaultsContentExtremeModeEnabledKey = "pip.home.contentExtremeModeEnabled"
    private let userDefaultsHidePiPWhenDockedKey = "pip.home.hideWhenDocked"
    private let userDefaultsPiPCloseConfirmationKey = "pip.home.confirmBeforeClosing"
    static let userDefaultsIOS26AudioKeepAliveKey = "pip.keepAlive.iOS26AudioEnabled"
    static let userDefaultsIOS26PiPOnlyKeepAliveKey = "pip.keepAlive.iOS26PiPOnlyEnabled"
    static let iOS26KeepAliveModeDidChangeNotification = Notification.Name("pip.iOS26KeepAliveModeDidChange")
    private var currentGeometryRoute: PiPGeometryController.Route {
        shouldUsePlayerLayerPiPCompatibility ? .playerLayer : .videoCall
    }
    private var currentGeometryMetrics: PiPGeometryController.Metrics {
        PiPGeometryController.shared.metrics(for: currentGeometryRoute)
    }
    private var currentPiPSize: CGSize {
        CGSize(width: currentPiPWidth, height: effectivePiPSurfaceHeight)
    }
    private var currentPiPWidth: CGFloat {
        shouldRenderClockMode ? clockPiPWidth : textPiPWidth
    }
    private var clampedPiPHeight: CGFloat {
        clampedHeight(pipHeight)
    }
    private var currentMinimumPiPHeight: CGFloat { currentGeometryMetrics.minimumHeight }
    private var currentPiPHeightStep: CGFloat { currentGeometryMetrics.heightStep }
    private var effectivePiPSurfaceHeight: CGFloat {
        PiPGeometryController.shared.effectiveSurfaceHeight(
            height: pipHeight,
            route: currentGeometryRoute,
            visuallyHidden: isPiPVisuallyHidden
        )
    }
    private var pipHeightForDisplay: String {
        formattedHeight(clampedPiPHeight)
    }
    private var pipStatusTitle: String {
        guard isPiPRuntimeActive else {
            return L10n.text("待启用", "Ready")
        }
        return clampedPiPHeight <= 0.15
            ? L10n.text("运行中-已隐藏", "Hidden")
            : L10n.text("运行中", "Running")
    }

    private var isPiPVisuallyHidden: Bool {
        PiPGeometryController.shared.isVisuallyHidden(height: pipHeight, route: currentGeometryRoute)
    }
    private var isPiPSuspendedAtSide: Bool {
        pipLifecycle.confirmedActive && pipLifecycle.suspendedAtSide
    }
    private var shouldRenderClockMode: Bool {
        isClockModeFeatureEnabled && isClockModeEnabled && !shouldUsePlayerLayerPiPCompatibility && !isPiPVisuallyHidden
    }
    private var isClockModeAvailableForUI: Bool {
        isClockModeFeatureEnabled
    }
    private var pipStatusColor: UIColor {
        isPiPRuntimeActive ? .systemBlue : .secondaryLabel
    }
    private var isPiPRuntimeActive: Bool {
        pipRuntimeStartedAt != nil && isOwnPiPConfirmedActive && (pipController?.isPictureInPictureActive ?? false)
    }
    private var pipRuntimeDurationForDisplay: String {
        if let pipRuntimeStartedAt {
            return formattedRuntime(Date().timeIntervalSince(pipRuntimeStartedAt))
        }
        return formattedRuntime(pipRuntimeDuration)
    }
    private var directCompatibilityResizeEnabled: Bool {
        LatencyExperimentController.shared.state.directCompatibilityResizeEnabled
    }
    private var shouldUseDirectCompatibilityVideoCall: Bool {
        pipEngineRoute == .playerLayerGenerated && directCompatibilityResizeEnabled
    }
    private var effectivePiPEngineRoute: PiPEngineRoute {
        if pipEngineRoute == .auto {
            return isLegacyPlayerLayerFallbackActive ? .playerLayerGenerated : .videoCall
        }
        if shouldUseDirectCompatibilityVideoCall {
            return .videoCall
        }
        return pipEngineRoute
    }
    private var shouldUsePlayerLayerPiPCompatibility: Bool {
        effectivePiPEngineRoute.usesPlayerLayer
    }
    private var shouldUseCompatibilityRefreshPolicy: Bool {
        pipEngineRoute == .playerLayerGenerated || (pipEngineRoute == .auto && isLegacyPlayerLayerFallbackActive)
    }
    private var isPlayerLayerRouteEnabled: Bool {
        shouldUseCompatibilityRefreshPolicy
    }
    private var shouldAttachCustomViewInPlayerLayerPiP: Bool {
        false
    }
    /// Single read-only snapshot for the redesigned home UI.
    /// Core PiP state remains owned by the engine/lifecycle controllers.
    private var homePresentationState: HomePresentationState {
        let activity: HomePresentationState.Activity
        if isPiPTransitioning {
            activity = pipTransitionExpectedActive == false ? .stopping : .starting
        } else if case .failed = pipLifecycle.state {
            activity = .failed
        } else if pipLifecycle.isTransitioning {
            switch pipLifecycle.state {
            case .starting: activity = .starting
            case .stopping: activity = .stopping
            default: activity = .ready
            }
        } else if isPiPRuntimeActive {
            activity = isPiPVisuallyHidden ? .hidden : .running
        } else {
            activity = .ready
        }

        return HomePresentationState(
            activity: activity,
            engine: isPlayerLayerRouteEnabled ? .playerLayer : .videoCall,
            requestedFrameRate: FrameRatePreference.targetFrameRate,
            refreshRequestActive: RefreshRateController.shared.isRunning,
            pipHeightText: pipHeightForDisplay
        )
    }

    private var isCurrentAppearanceDark: Bool {
        traitCollection.userInterfaceStyle == .dark
    }

    override func viewDidLoad() {
        super.viewDidLoad()

#if DEBUG
        AppDebugLogger.log("画中画初始化前，应用窗口数：\(allApplicationWindows().count)")
        DiagnosticsRuntimeState.updateCurrentPage("悬浮窗")
        AppDebugLogger.trimOnLaunch()
        AppDebugLogger.registerBackgroundFlush()
        AppDebugLogger.log("Home viewDidLoad")
        PowerUsageLogger.markLaunch()
        KeepAliveNotificationTester.sanitizeOnLaunch()
        let keepAliveInterruptionNotice = KeepAliveLogger.markAppLaunch()
#endif

        loadHomePreferences()
        loadPiPRuntimeState()
        setupSwiftUI()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in
            self.updateHomeView()
        }
#if DEBUG
        if let keepAliveInterruptionNotice {
            KeepAliveNotificationTester.presentLaunchInterruptionAlert(keepAliveInterruptionNotice, from: self)
            pipTasks.schedule(.launchPendingNotificationAlert, after: 1.0) { [weak self] in
                guard let self else { return }
                KeepAliveNotificationTester.presentPendingLocalNotificationAlertIfNeeded(from: self)
            }
        } else {
            KeepAliveNotificationTester.presentPendingLocalNotificationAlertIfNeeded(from: self)
        }
#endif

        NotificationCenter.default.addObserver(self, selector: #selector(handleEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleLanguageDidChange), name: L10n.languageDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePerformanceGovernorDidChange), name: SmartPerformanceGovernor.didChangeNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !shouldResignForegroundAfterPiPClose {
            restoreForegroundWindowsHiddenForPiPCloseIfNeeded()
        }
        DiagnosticsRuntimeState.updateCurrentPage("悬浮窗")
        updateDiagnosticsPiPState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard playerLayer != nil else { return }
        centerPlayerLayer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Settings stay visible by design; Speed is intentionally a single-page UI.
    }

    deinit {
        if let playerEndObserver = playerEndObserver {
            NotificationCenter.default.removeObserver(playerEndObserver)
        }
        if let playerStallObserver = playerStallObserver {
            NotificationCenter.default.removeObserver(playerStallObserver)
        }
        playerPauseObserver?.invalidate()
        playerLayerTimeControlObserver?.invalidate()
        cancelPiPHeightAnimation()
        PlaceholderVideoFactory.cancelPendingPlayerLayerMediaWork()
        NotificationCenter.default.removeObserver(self)
        pipTasks.cancelAll()
        hasPrimedPlayerLayerPiPStart = false
        stopDisplayLinks()
        stopClockTimer()
        endBackgroundTask()
    }

    private func setupSwiftUI() {
        let model = SpeedHomeViewModel(
            isPiPActive: isPiPActiveForUI,
            presentationState: homePresentationState,
            pipHeight: pipHeightForDisplay,
            isCurrentAppearanceDark: isCurrentAppearanceDark,
            pipEngineRoute: pipEngineRoute,
            latencyExperimentState: LatencyExperimentController.shared.state,
            performanceGovernorSnapshot: SmartPerformanceGovernor.shared.snapshot,
            performanceLabSnapshot: SpeedPerformanceLab.snapshot(),
            onTogglePiP: { [weak self] in self?.togglePiP() },
            onHidePiP: { [weak self] in self?.hidePiPFromHome() },
            onStartAndHidePiP: { [weak self] in self?.startPiPAndHideFromHome() },
            onToggleStyle: { [weak self] in self?.togglePiPStyle() },
            onCustomizeHeight: { [weak self] in self?.presentPiPHeightEditor() },
            onToggleAppearanceMode: { [weak self] in self?.toggleAppearanceMode() },
            onClearCache: { [weak self] in self?.clearCacheFromHome() },
            onSetPiPEngineRoute: { [weak self] route in self?.setPiPEngineRoute(route) },
            onSetLatencyExperimentAll: { [weak self] enabled in self?.setLatencyExperimentAll(enabled) },
            onSetLowLatencyEventDispatch: { [weak self] enabled in self?.setLowLatencyEventDispatch(enabled) },
            onSetImmediatePresentation: { [weak self] enabled in self?.setImmediatePresentation(enabled) },
            onSetContinuousUpdates: { [weak self] enabled in self?.setContinuousUpdates(enabled) },
            onSetDirectCompatibilityResize: { [weak self] enabled in self?.setDirectCompatibilityResize(enabled) },
            onSetRefreshDriverMode: { [weak self] mode in self?.setRefreshDriverMode(mode) }
        )
        homeViewModel = model

        let hostingController = UIHostingController(rootView: PiPHomeView(model: model))
        self.hostingController = hostingController
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.backgroundColor = .systemBackground
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
        RefreshRateController.shared.attach(to: hostingController.view)
        LatencyExperimentController.shared.attach(to: hostingController.view)
    }

    private func updateHomeView(animated: Bool = false) {
        guard let homeViewModel else { return }
        let update = {
            homeViewModel.update(
                isPiPActive: self.isPiPActiveForUI,
                presentationState: self.homePresentationState,
                pipHeight: self.pipHeightForDisplay,
                isCurrentAppearanceDark: self.isCurrentAppearanceDark,
                pipEngineRoute: self.pipEngineRoute,
                latencyExperimentState: LatencyExperimentController.shared.state,
                performanceGovernorSnapshot: SmartPerformanceGovernor.shared.snapshot,
                performanceLabSnapshot: SpeedPerformanceLab.snapshot()
            )
        }
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            update()
            return
        }
        withAnimation(.smooth(duration: 0.28)) { update() }
    }

    private func refreshLatencyExperimentUIAfterMutation() {
        // UIUpdateLink rebuilds are intentionally deferred to the next main-queue turn.
        // Refresh now, then again after the queued rebuild so the badge cannot lag by one tap.
        updateHomeView(animated: true)
        DispatchQueue.main.async { [weak self] in
            self?.updateHomeView(animated: false)
        }
    }
    private func setLatencyExperimentAll(_ enabled: Bool) {
        LatencyExperimentController.shared.setAllEnabled(enabled)
        refreshLatencyExperimentUIAfterMutation()
    }

    private func setLowLatencyEventDispatch(_ enabled: Bool) {
        LatencyExperimentController.shared.setLowLatencyEventDispatchEnabled(enabled)
        refreshLatencyExperimentUIAfterMutation()
    }

    private func setImmediatePresentation(_ enabled: Bool) {
        LatencyExperimentController.shared.setImmediatePresentationEnabled(enabled)
        refreshLatencyExperimentUIAfterMutation()
    }

    private func setContinuousUpdates(_ enabled: Bool) {
        LatencyExperimentController.shared.setContinuousUpdatesEnabled(enabled)
        refreshLatencyExperimentUIAfterMutation()
    }

    private func setRefreshDriverMode(_ mode: RefreshDriverMode) {
        LatencyExperimentController.shared.setRefreshDriverMode(mode)
        refreshLatencyExperimentUIAfterMutation()
    }

    private func setDirectCompatibilityResize(_ enabled: Bool) {
        let wasEnabled = directCompatibilityResizeEnabled
        LatencyExperimentController.shared.setDirectCompatibilityResizeEnabled(enabled)
        guard wasEnabled != enabled else {
            refreshLatencyExperimentUIAfterMutation()
            return
        }

        // Direct compatibility is an alternate experimental engine. Never swap AVKit
        // content sources under an active PiP; apply safely to the next session instead.
        if pipController?.isPictureInPictureActive == true || isPiPTransitioning {
            refreshLatencyExperimentUIAfterMutation()
            showMessage(L10n.text("Direct Resize 会在下次重新打开悬浮窗时生效", "Direct Resize will take effect the next time you reopen PiP."))
            return
        }

        if pipEngineRoute == .playerLayerGenerated, hasPreparedPiPInfrastructure {
            teardownPiPInfrastructure()
        }
        RefreshRateController.shared.setRuntimeMode(shouldUseCompatibilityRefreshPolicy ? .playerLayer : .videoCall)
        updateHomeView(animated: true)
    }

    @objc private func handlePerformanceGovernorDidChange() {
        RefreshRateController.shared.reconcile()
        LatencyExperimentController.shared.reconcile()
        updateHomeView()
    }

    private func loadHomePreferences() {
        isLoadingHomePreferences = true
        defer { isLoadingHomePreferences = false }

        // Production Speed uses a static PiP surface. Do not let preferences from
        // older builds resurrect scrolling text, a clock display link, or any other
        // persistent content animation beside the single app-level refresh request.
        prefersTextScrolling = false
        isScrollingEnabled = false
        isClockModeEnabled = false
        // Aggressive production policy: standard Speed is PiP-only. Old installs must
        // not silently resurrect continuous/lock-screen audio keep-alive preferences.
        KeepAlivePolicy.current = .pipOnly
        UserDefaults.standard.set(false, forKey: userDefaultsScrollingEnabledKey)
        UserDefaults.standard.set(false, forKey: userDefaultsClockModeEnabledKey)
        UserDefaults.standard.set(true, forKey: userDefaultsClockModeDefaultMigrationKey)
        UserDefaults.standard.set(true, forKey: userDefaultsClockModeDefaultTextMigrationKey)
        isDarkModeForced = AppAppearancePreference.isDarkModeForced
        KeepAliveNotificationTester.isPiPStoppedNotificationEnabled = false
        KeepAliveNotificationTester.cancelPiPStoppedNotifications(reason: "Speed 精简模式")
        isPiPStoppedNotificationEnabled = false
        KeepAliveNotificationTester.isBackgroundProbeEnabled = false
        KeepAliveNotificationTester.cancelBackgroundProbeNotifications(reason: "后台中断通知已停用")
        isBackgroundInterruptionNotificationEnabled = false
        keepAliveNotificationFrequency = KeepAliveNotificationTester.probeFrequency
        keepsPiPStatusInfoPersistent = UserDefaults.standard.object(forKey: userDefaultsPiPStatusInfoPersistentKey) == nil
            ? false
            : UserDefaults.standard.bool(forKey: userDefaultsPiPStatusInfoPersistentKey)
        // Never auto-open the status info card on launch. This fixes the persistent
        // center overlay that obscured the home controls on Alpha46/47.
        isPiPStatusInfoVisible = false
        if let storedRoute = UserDefaults.standard.string(forKey: userDefaultsPiPEngineRouteKey) {
            switch storedRoute {
            case PiPEngineRoute.auto.rawValue:
                pipEngineRoute = .auto
            case PiPEngineRoute.videoCall.rawValue:
                pipEngineRoute = .videoCall
            case PiPEngineRoute.playerLayerGenerated.rawValue, "playerLayer":
                pipEngineRoute = .playerLayerGenerated
            case "referenceIPA", "referenceIPAPure":
                pipEngineRoute = .playerLayerGenerated
            default:
                pipEngineRoute = .auto
            }
        } else {
            let legacyPlayerLayerEnabled = UserDefaults.standard.object(forKey: userDefaultsPlayerLayerRouteEnabledKey) == nil
                ? false
                : UserDefaults.standard.bool(forKey: userDefaultsPlayerLayerRouteEnabledKey)
            pipEngineRoute = legacyPlayerLayerEnabled ? .playerLayerGenerated : .auto
        }
        UserDefaults.standard.set(false, forKey: userDefaultsExtremeSilentModeEnabledKey)
        UserDefaults.standard.set(false, forKey: userDefaultsContentExtremeModeEnabledKey)
        isExtremeSilentModeEnabled = false
        isContentExtremeModeEnabled = false

        remembersPiPHeight = UserDefaults.standard.object(forKey: userDefaultsRememberPiPHeightKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: userDefaultsRememberPiPHeightKey)
        requiresPiPCloseConfirmation = UserDefaults.standard.bool(forKey: userDefaultsPiPCloseConfirmationKey)
        UserDefaults.standard.set(false, forKey: userDefaultsHidePiPWhenDockedKey)
        hidesPiPWhenDocked = false
        let hasRememberedPiPHeight = UserDefaults.standard.object(forKey: userDefaultsPiPHeightKey) != nil
        if remembersPiPHeight, hasRememberedPiPHeight {
            pipHeight = clampedHeight(CGFloat(UserDefaults.standard.double(forKey: userDefaultsPiPHeightKey)))
            isCompactPiPStyle = abs(clampedPiPHeight - currentDefaultPiPHeight) < 0.5
        } else if pipEngineRoute.usesPlayerLayer {
            pipHeight = playerLayerDefaultPiPHeight
            isCompactPiPStyle = true
        }
        if pipEngineRoute.usesPlayerLayer, abs(clampedPiPHeight - compactPiPHeight) < 0.5 {
            // Migrate the old 44pt compatibility value to the actual PlayerLayer default.
            pipHeight = playerLayerDefaultPiPHeight
            isCompactPiPStyle = true
            if remembersPiPHeight {
                saveCurrentPiPHeightPreference()
            }
        }
        if pipEngineRoute.usesPlayerLayer, isClockModeEnabled {
            isClockModeEnabled = false
            UserDefaults.standard.set(false, forKey: userDefaultsClockModeEnabledKey)
            isScrollingEnabled = prefersTextScrolling
        }
    }

    private func loadPiPRuntimeState() {
        let defaults = UserDefaults.standard
        pipRuntimeStoppedAtText = normalizedStoredPiPRuntimeStoppedAtText()
        let lastDuration = defaults.double(forKey: userDefaultsPiPRuntimeDurationKey)
        if defaults.bool(forKey: userDefaultsPiPRuntimeWasActiveKey) {
            let timestamp = defaults.double(forKey: userDefaultsPiPRuntimeStartedAtKey)
            if timestamp > 0 {
                let detectedStopDate = Date()
                let lastConfirmedDate = runtimeLastConfirmedDate(
                    defaults: defaults,
                    fallback: KeepAliveLogger.lastHeartbeatDate ?? Date(timeIntervalSince1970: timestamp)
                )
                pipRuntimeDuration = max(detectedStopDate.timeIntervalSince1970 - timestamp, lastDuration)
                pipRuntimeStoppedAtText = formattedStopTime(detectedStopDate)
                defaults.set(pipRuntimeStoppedAtText, forKey: userDefaultsPiPRuntimeStoppedAtTextKey)
                defaults.set(lastConfirmedDate.timeIntervalSince1970, forKey: userDefaultsPiPRuntimeLastConfirmedAtKey)
                defaults.set(pipRuntimeDuration, forKey: userDefaultsPiPRuntimeDurationKey)
                defaults.set(false, forKey: userDefaultsPiPRuntimeWasActiveKey)
                AppDebugLogger.log(
                    "PiP runtime recovered after abnormal interruption, lastConfirmed=\(pipRuntimeStoppedAtText), detectedAt=\(formattedStopTime(detectedStopDate)), duration=\(formattedRuntime(pipRuntimeDuration))"
                )
                return
            }
        }
        pipRuntimeDuration = lastDuration
    }

    private func runtimeLastConfirmedDate(defaults: UserDefaults, fallback: Date) -> Date {
        let timestamp = defaults.double(forKey: userDefaultsPiPRuntimeLastConfirmedAtKey)
        guard timestamp > 0 else { return fallback }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func syncPiPRuntimeDisplayState() {
        if let pipRuntimeStartedAt {
            pipRuntimeDuration = max(0, Date().timeIntervalSince(pipRuntimeStartedAt))
        } else {
            pipRuntimeStoppedAtText = normalizedStoredPiPRuntimeStoppedAtText()
        }
    }

    private func normalizedStoredPiPRuntimeStoppedAtText() -> String {
        let storedText = UserDefaults.standard.string(forKey: userDefaultsPiPRuntimeStoppedAtTextKey) ?? "暂无"
        guard !storedText.isEmpty, storedText != "暂无" else {
            return L10n.text("暂无", "None")
        }
        return storedText
    }

    private func setRememberPiPHeight(_ isEnabled: Bool) {
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启记忆悬浮窗高度" : "关闭记忆悬浮窗高度")
        remembersPiPHeight = isEnabled
    }

    private func setPiPCloseConfirmationRequired(_ isEnabled: Bool) {
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启防误触关闭确认" : "关闭防误触关闭确认")
        AppDebugLogger.log("防误触关闭确认已\(isEnabled ? "开启" : "关闭")")
        requiresPiPCloseConfirmation = isEnabled
    }

    private func setHidePiPWhenDocked(_ isEnabled: Bool) {
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启检测吸附后隐藏" : "关闭检测吸附后隐藏")
        // Disabled for now: dock detection is not stable enough for automatic height changes.
        hidesPiPWhenDocked = false
        UserDefaults.standard.set(false, forKey: userDefaultsHidePiPWhenDockedKey)
    }

    private func setDarkModeForced(_ isEnabled: Bool) {
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启深色模式" : "关闭深色模式")
        shouldAnimateNextAppearancePreferenceChange = true
        isDarkModeForced = isEnabled
        shouldAnimateNextAppearancePreferenceChange = false
    }

    private func toggleAppearanceMode() {
        let targetStyle: UIUserInterfaceStyle
        if AppAppearancePreference.isDarkModeForced {
            targetStyle = .light
        } else if AppAppearancePreference.isLightModeForced {
            targetStyle = .dark
        } else {
            targetStyle = isCurrentAppearanceDark ? .light : .dark
        }
        DiagnosticsRuntimeState.recordUserAction(targetStyle == .dark ? "切换深色模式" : "切换浅色模式")
        AppAppearancePreference.setPreferredStyle(targetStyle, animated: true)
        isSyncingAppearancePreferenceState = true
        isDarkModeForced = AppAppearancePreference.isDarkModeForced
        isSyncingAppearancePreferenceState = false
        updateHomeView()
    }

    private func setPiPStoppedNotificationEnabled(_ isEnabled: Bool) {
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启悬浮窗被挤通知" : "关闭悬浮窗被挤通知")
        if isEnabled {
            KeepAliveNotificationTester.prepareForPiPStoppedToggle(from: self) { [weak self] granted in
                guard let self else { return }
                self.isPiPStoppedNotificationEnabled = granted
            }
        } else {
            isPiPStoppedNotificationEnabled = false
            KeepAliveNotificationTester.cancelPiPStoppedNotifications(reason: "首页关闭悬浮窗被挤通知")
        }
    }

    private func setBackgroundInterruptionNotificationEnabled(_ isEnabled: Bool) {
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启后台中断提醒beta" : "关闭后台中断提醒beta")
        isBackgroundInterruptionNotificationEnabled = false
        KeepAliveNotificationTester.isBackgroundProbeEnabled = false
        KeepAliveNotificationTester.cancelBackgroundProbeNotifications(reason: "后台中断通知已停用")
    }

    private func setKeepAliveNotificationFrequency(_ frequency: KeepAliveNotificationProbeFrequency) {
        DiagnosticsRuntimeState.recordUserAction("切换后台中断提醒频率：\(frequency.title)")
        keepAliveNotificationFrequency = frequency
    }

    private func setPiPStatusInfoPersistent(_ isEnabled: Bool) {
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启悬浮窗状态常驻" : "关闭悬浮窗状态常驻")
        keepsPiPStatusInfoPersistent = isEnabled
    }

    private func setPlayerLayerRouteEnabled(_ isEnabled: Bool) {
        setPiPEngineRoute(isEnabled ? .playerLayerGenerated : .videoCall)
    }

    private func setPiPEngineRoute(_ requestedRoute: PiPEngineRoute) {
        let route = requestedRoute
        if route == .auto, route == pipEngineRoute, isLegacyPlayerLayerFallbackActive,
           pipController?.isPictureInPictureActive != true, !isPiPTransitioning {
            isLegacyPlayerLayerFallbackActive = false
            autoFallbackRestartAttempts = 0
            if hasPreparedPiPInfrastructure { teardownPiPInfrastructure() }
            RefreshRateController.shared.setRuntimeMode(.videoCall)
            updateHomeView(animated: true)
            return
        }
        guard route != pipEngineRoute else { return }
        if route.usesPlayerLayer, !pipEngineRoute.usesPlayerLayer {
            presentPlayerLayerRouteConfirmation {
                self.applyPiPEngineRoute(route)
            }
            return
        }
        applyPiPEngineRoute(route)
    }

    private func applyPiPEngineRoute(_ route: PiPEngineRoute) {
        if stopActivePiPForEngineRouteSwitchIfNeeded(route) {
            return
        }

        isLegacyPlayerLayerFallbackActive = false
        autoFallbackRestartAttempts = 0
        cancelDelayedPiPHideCountdown(reason: "切换悬浮窗底层")
        if !route.usesPlayerLayer {
            isExtremeSilentModeEnabled = false
        } else {
            isClockModeEnabled = false
            UserDefaults.standard.set(false, forKey: userDefaultsClockModeEnabledKey)
            isScrollingEnabled = prefersTextScrolling
        }
        pipHeight = route.usesPlayerLayer ? playerLayerDefaultPiPHeight : compactPiPHeight
        isCompactPiPStyle = true
        if remembersPiPHeight {
            saveCurrentPiPHeightPreference()
        }
        DiagnosticsRuntimeState.recordUserAction("切换悬浮窗底层：\(route.diagnosticsName)")
        if hasPreparedPiPInfrastructure {
            teardownPiPInfrastructure()
        }
        hasPrimedPlayerLayerPiPStart = false
        isLegacyPlayerLayerFallbackActive = false
        playerLayerPiPStartAudioMode = .defaultStartupMode
        pipEngineRoute = route
        RefreshRateController.shared.setRuntimeMode(shouldUseCompatibilityRefreshPolicy ? .playerLayer : .videoCall)
        AppDebugLogger.log("PiP route changed: \(route.diagnosticsName)")
        updateDiagnosticsPiPState()
        // pipEngineRoute.didSet already publishes the complete post-switch home state.
        // Avoid an identical second SwiftUI model transaction on the same run-loop turn.
        showMessage(L10n.text("悬浮窗底层启用方式已切换成功，请重新打开悬浮窗", "Floating window engine changed successfully. Please reopen the floating window."))
    }

    @discardableResult
    private func stopActivePiPForEngineRouteSwitchIfNeeded(_ route: PiPEngineRoute) -> Bool {
        guard pipController?.isPictureInPictureActive == true || isPiPTransitioning else { return false }
        pendingPiPEngineRouteAfterStop = route
        AppDebugLogger.log("PiP route change deferred until current PiP stops: \(route.diagnosticsName)")
        wantsPiPActive = false
        updatePiPAutomaticStartPolicy()
        cancelDelayedPiPHideCountdown(reason: "切换悬浮窗底层")
        pipTasks.cancel(.startRetry)
        pipTasks.cancel(.startTimeout)

        if isPiPTransitioning {
            pipTasks.schedule(.engineRouteSwitchSettle, after: 0.35) { [weak self] in
                guard let self, self.pendingPiPEngineRouteAfterStop == route else { return }
                if self.pipController?.isPictureInPictureActive == true {
                    self.stopPiPSmoothly()
                } else if !self.isPiPTransitioning {
                    self.pendingPiPEngineRouteAfterStop = nil
                    self.applyPiPEngineRoute(route)
                }
            }
        } else {
            stopPiPSmoothly()
        }
        return true
    }

    private var shouldUseVideoCallOffscreenCloseAnimation: Bool {
        !shouldUsePlayerLayerPiPCompatibility
    }

    private func presentPlayerLayerRouteConfirmation(onConfirm: @escaping () -> Void) {
        let message = L10n.text(
            "请确认默认方案解锁120后会导致你日常的b站弹幕以及锁60hz的游戏一顿一顿，可以通过切换新方案解决，但是无法完全隐藏悬浮窗，没有这两个需求就使用默认方案即可",
            "Please confirm that the default route causes your usual Bilibili danmaku or games locked to 60 Hz to stutter after unlocking 120 Hz. Switching to the new route may solve this, but it cannot fully hide the floating window. If you do not need these fixes, keep using the default route."
        )
        let alert = UIAlertController(
            title: L10n.text("确认切换新方案", "Confirm New Route"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.text("确认切换", "Switch"), style: .default) { _ in
            onConfirm()
        })
        present(alert, animated: true)
    }

    private func setExtremeSilentModeEnabled(_ isEnabled: Bool) {
        guard isEnabled != isExtremeSilentModeEnabled else { return }
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启极限静默模式" : "关闭极限静默模式")
        if isEnabled && !isPlayerLayerRouteEnabled {
            setPlayerLayerRouteEnabled(true)
        }
        if isEnabled {
            isContentExtremeModeEnabled = false
        }
        isExtremeSilentModeEnabled = isEnabled
        let message = isEnabled
            ? L10n.text("已开启极限静默模式，并切换为新方案。请重新打开悬浮窗测试。", "Extreme silent mode is on and the new route is active. Reopen PiP to test.")
            : L10n.text("已关闭极限静默模式", "Extreme silent mode is off.")
        showMessage(message)
    }

    private func setContentExtremeModeEnabled(_ isEnabled: Bool) {
        guard isEnabled != isContentExtremeModeEnabled else { return }
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "开启内容极限模式" : "关闭内容极限模式")
        if isEnabled {
            if isPlayerLayerRouteEnabled {
                setPlayerLayerRouteEnabled(false)
            }
            isExtremeSilentModeEnabled = false
        }
        isContentExtremeModeEnabled = isEnabled
        let message = isEnabled
            ? L10n.text("已开启内容极限模式，请重新打开悬浮窗测试", "Content extreme mode is on. Reopen PiP to test.")
            : L10n.text("已关闭内容极限模式", "Content extreme mode is off.")
        showMessage(message)
    }

    private func applyExtremeSilentModeIfNeeded(reason: String) {
        guard isExtremeSilentModeEnabled else { return }
        stopDisplayLinks()
        stopClockTimer()
        BackgroundTaskManager.shared.forceStopAndDeactivate()
        PowerUsageLogger.markKeepAliveStop()
        DebugDiagnosticsMonitor.setEnabled(false)
        if isClockModeEnabled {
            isClockModeEnabled = false
        }
        if isScrollingEnabled {
            isScrollingEnabled = false
        }
        AppDebugLogger.log("Extreme silent mode applied: \(reason)")
    }

    private func applyContentExtremeModeIfNeeded(reason: String) {
        guard isContentExtremeModeEnabled else { return }
        stopDisplayLinks()
        stopClockTimer()
        BackgroundTaskManager.shared.forceStopAndDeactivate()
        PowerUsageLogger.markKeepAliveStop()
        DebugDiagnosticsMonitor.setEnabled(false)
        measuredPiPFPS = 0
        AppDebugLogger.log("Content extreme mode applied: \(reason)")
        guard pipController?.isPictureInPictureActive == true || isPiPTransitioning else { return }
        configureRunningText()
    }

    private func toggleSettingsPanel() {
        // Settings are permanently visible in the streamlined home screen.
        isSettingsExpanded = true
    }

    private func dismissSettingsPanel() {
        isSettingsExpanded = true
    }

    func handleSystemLaunchTarget(_ target: SpeedLaunchTarget) {
        SmartPerformanceGovernor.shared.beginInteractiveBurst()
        switch target {
        case .open:
            updateHomeView(animated: true)
            SmartPerformanceGovernor.shared.endInteractiveBurst(after: 0.20)
        case .start:
            if pipController?.isPictureInPictureActive != true && !isPiPTransitioning {
                togglePiP()
            }
            SmartPerformanceGovernor.shared.endInteractiveBurst(after: 0.45)
        case .startAndHide:
            if pipController?.isPictureInPictureActive == true {
                hidePiPFromHome()
            } else if !isPiPTransitioning {
                startPiPAndHideFromHome()
            }
            SmartPerformanceGovernor.shared.endInteractiveBurst(after: 0.70)
        }
    }

    func dismissTransientOverlays() {
        overlayResetToken += 1
        isSettingsExpanded = true
        updateHomeView()
    }

    func stopForFullDataReset() {
        wantsPiPActive = false
        isPiPActiveForUI = false
        guard pipController?.isPictureInPictureActive == true || isPiPTransitioning else {
            if shouldUsePlayerLayerPiPCompatibility, hasPreparedPiPInfrastructure {
                teardownPiPInfrastructure()
            }
            return
        }
        AppDebugLogger.log("清空全部数据前停止悬浮窗")
        stopPiPSmoothly()
    }

    private func saveCurrentPiPHeightPreference() {
        UserDefaults.standard.set(Double(clampedPiPHeight), forKey: userDefaultsPiPHeightKey)
    }

    private func clampedHeight(_ height: CGFloat) -> CGFloat {
        PiPGeometryController.shared.clampedHeight(height, route: currentGeometryRoute)
    }

    private func promotePlayerLayerMinimumHeightForNormalStartIfNeeded(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        guard clampedPiPHeight <= currentMinimumPiPHeight + 0.01 else { return }

        pipHeight = playerLayerDefaultPiPHeight
        isCompactPiPStyle = true
        if remembersPiPHeight {
            saveCurrentPiPHeightPreference()
        }
        // PlayerLayer PiP size is driven by the media presentation size. Merely resizing
        // the hidden source view leaves AVKit using the old 1pt backing item on the next launch.
        requestPlayerLayerMedia(for: playerLayerDefaultPiPHeight, reason: "普通开启恢复默认尺寸")
        configureRunningText()
        updateHomeView()
        AppDebugLogger.log("PlayerLayer normal start restored default height to \(formattedHeight(playerLayerDefaultPiPHeight)): \(reason)")
    }

    private func beginPiPRuntimeSession() {
        let start = Date()
        pipRuntimeStartedAt = start
        pipRuntimeDuration = 0
        pipRuntimeStoppedAtText = normalizedStoredPiPRuntimeStoppedAtText()
        let defaults = UserDefaults.standard
        defaults.set(start.timeIntervalSince1970, forKey: userDefaultsPiPRuntimeStartedAtKey)
        defaults.set(start.timeIntervalSince1970, forKey: userDefaultsPiPRuntimeLastConfirmedAtKey)
        defaults.set(0, forKey: userDefaultsPiPRuntimeDurationKey)
        defaults.set(true, forKey: userDefaultsPiPRuntimeWasActiveKey)
        updateDiagnosticsPiPState()
        updateHomeView()
    }

    private func finishPiPRuntimeSession(stoppedAt: Date = Date()) {
        if let pipRuntimeStartedAt {
            pipRuntimeDuration = max(0, stoppedAt.timeIntervalSince(pipRuntimeStartedAt))
        }
        pipRuntimeStartedAt = nil
        pipRuntimeStoppedAtText = formattedStopTime(stoppedAt)
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: userDefaultsPiPRuntimeWasActiveKey)
        defaults.set(pipRuntimeDuration, forKey: userDefaultsPiPRuntimeDurationKey)
        defaults.set(pipRuntimeStoppedAtText, forKey: userDefaultsPiPRuntimeStoppedAtTextKey)
        defaults.set(stoppedAt.timeIntervalSince1970, forKey: userDefaultsPiPRuntimeLastConfirmedAtKey)
        updateDiagnosticsPiPState()
        AppDebugLogger.log("PiP runtime stopped at \(pipRuntimeStoppedAtText)")
        updateHomeView()
    }

    private func formattedRuntime(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func formattedStopTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "M/d HH:mm:ss"
        return formatter.string(from: date)
    }

    private func preparePiPInfrastructureIfNeeded() -> Bool {
        guard !hasPreparedPiPInfrastructure else {
            return pipController != nil
        }

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            print("不支持画中画")
            AppDebugLogger.log("PiP unsupported")
            return false
        }

        if shouldUsePlayerLayerPiPCompatibility,
           !PlaceholderVideoFactory.isPlayerLayerBackingVideoReady(forPointHeight: clampedPiPHeight) {
            // Long H.264 compatibility assets are generated on a utility queue only.
            // Never fall back to synchronous encoding from the main-thread PiP setup path.
            PlaceholderVideoFactory.prewarmPlayerLayerBackingVideo(forPointHeight: clampedPiPHeight)
            AppDebugLogger.log("Prepare PiP deferred: PlayerLayer startup media is still warming")
            return false
        }

        AppDebugLogger.log("Prepare PiP infrastructure begin")
        setupPiPSourceView()
        setupCustomView()
        if shouldUsePlayerLayerPiPCompatibility {
            preparePlayerLayerVideoOnlyAudioState(reason: "准备PlayerLayer视频PiP")
        }
        if shouldPrepareBackingPlayerForPlayback {
            setupPlayer()
            guard playerLayer != nil else {
                AppDebugLogger.log("Prepare PiP failed: playerLayer nil")
                teardownPiPInfrastructure()
                return false
            }
        }
        setupPip()
        guard pipController != nil else {
            AppDebugLogger.log("Prepare PiP failed: pipController nil")
            teardownPiPInfrastructure()
            return false
        }
        if shouldUsePlayerLayerPiPCompatibility {
            NotificationCenter.default.addObserver(self, selector: #selector(handleAudioInterruption), name: AVAudioSession.interruptionNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleAudioRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
        }
        hasPreparedPiPInfrastructure = true
        AppDebugLogger.log("Prepare PiP infrastructure success")
        return true
    }

    private func teardownPiPInfrastructure() {
        stopClockTimer()
        resetLockScreenAudioBoost(reason: "拆除悬浮窗底层")
        cancelDelayedPiPHideCountdown(reason: "拆除悬浮窗底层")
        pipTasks.cancel(.playerLayerAudioRelease)
        if let playerEndObserver {
            NotificationCenter.default.removeObserver(playerEndObserver)
            self.playerEndObserver = nil
        }
        if let playerStallObserver {
            NotificationCenter.default.removeObserver(playerStallObserver)
            self.playerStallObserver = nil
        }
        playerPauseObserver?.invalidate()
        playerPauseObserver = nil
        playerLayerTimeControlObserver?.invalidate()
        playerLayerTimeControlObserver = nil
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        pipController?.removeObserver(self, forKeyPath: "isPictureInPictureSuspended")
        pipEngine.reset()
        pipController = nil
        videoCallContentController = nil
        customView?.removeFromSuperview()
        customView = nil
        textView = nil
        clockLabel = nil
        pipSourceView?.removeFromSuperview()
        pipSourceView = nil
        pipSourceWidthConstraint = nil
        pipSourceHeightConstraint = nil
        pipSourcePlacementConstraints.removeAll(keepingCapacity: true)
        lastAppliedPiPSourceSizeInPixels = nil
        lastSubmittedPiPSizeInPixels = nil
        pendingPlayerLayerPreviewHeight = nil
        lastPlayerLayerPreviewSubmissionAt = 0
        hasPreparedPiPInfrastructure = false
    }

    private func pinToSuperview(_ subview: UIView) {
        guard let superview = subview.superview else { return }
        subview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: superview.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: superview.trailingAnchor),
            subview.topAnchor.constraint(equalTo: superview.topAnchor),
            subview.bottomAnchor.constraint(equalTo: superview.bottomAnchor)
        ])
    }

    private func installCenteredPiPSourceConstraints(size: CGSize) {
        guard let pipSourceView else { return }
        NSLayoutConstraint.deactivate(pipSourcePlacementConstraints)
        let width = pipSourceView.widthAnchor.constraint(equalToConstant: size.width)
        let height = pipSourceView.heightAnchor.constraint(equalToConstant: size.height)
        pipSourceWidthConstraint = width
        pipSourceHeightConstraint = height
        pipSourcePlacementConstraints = [
            pipSourceView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pipSourceView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            width,
            height
        ]
        NSLayoutConstraint.activate(pipSourcePlacementConstraints)
    }

    private func setupPiPSourceView() {
        lastAppliedPiPSourceSizeInPixels = nil
        lastSubmittedPiPSizeInPixels = nil
        pipSourceView = UIView()
        pipSourceView.backgroundColor = .clear
        pipSourceView.isOpaque = false
        pipSourceView.isUserInteractionEnabled = false
        pipSourceView.layer.cornerRadius = 18
        pipSourceView.layer.cornerCurve = .continuous
        pipSourceView.clipsToBounds = true
        view.addSubview(pipSourceView)
        pipSourceView.translatesAutoresizingMaskIntoConstraints = false
        installCenteredPiPSourceConstraints(size: currentPiPSize)
    }

    private func setupPlayer() {
        guard let playerItem = makePlayerItem() else {
            print("未能生成画中画占位视频")
            AppDebugLogger.log("makePlayerItem failed")
            return
        }

        playerLayer = AVPlayerLayer()
        playerLayer.frame = centeredPreviewFrame()
        playerLayer.backgroundColor = UIColor.clear.cgColor
        playerLayer.isOpaque = false
        playerLayer.opacity = shouldUsePlayerLayerPiPCompatibility ? 1 : 0
        playerLayer.videoGravity = shouldUsePlayerLayerPiPCompatibility ? .resize : .resizeAspect
        playerLayer.needsDisplayOnBoundsChange = false

        let player = AVPlayer(playerItem: playerItem)
        configureBackingPlayerForPiP(player)
        player.actionAtItemEnd = .none
        player.isMuted = true
        player.volume = 0
        player.allowsExternalPlayback = shouldUsePlayerLayerPiPCompatibility
        playerLayer.player = player
        observeLooping(for: playerItem)
        if shouldUsePlayerLayerPiPCompatibility {
            observePlayerLayerPipelineHealth(for: player, item: playerItem)
        } else {
            observePlaybackHealth(for: player, item: playerItem)
        }
        if shouldUsePlayerLayerPiPCompatibility {
            if FrameRatePreference.isHighRefreshEnabled {
                player.play()
                scheduleTransientPlayerLayerPiPAudioRelease(reason: "PlayerLayer按原作者方式创建后播放")
            } else {
                player.pause()
            }
        }

        view.layer.insertSublayer(playerLayer, at: 0)
    }

    private func configureBackingPlayerForPiP(_ player: AVPlayer) {
        player.preventsDisplaySleepDuringVideoPlayback = false
        // Compatibility media is always a tiny local file. Avoid AVPlayer's network-oriented
        // startup waiting heuristic so item swaps can become visible with minimum latency.
        player.automaticallyWaitsToMinimizeStalling = false
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
    }

    private func setupPip() {
        do {
            let session = try pipEngine.prepare(
                route: effectivePiPEngineRoute,
                sourceView: pipSourceView,
                playerLayer: playerLayer,
                preferredContentSize: currentPiPSize,
                delegate: pipDelegateProxy
            )
            pipController = session.controller
            videoCallContentController = session.videoCallContentController

            if session.videoCallContentController != nil {
                attachCustomViewToPiPContent()
            }

            applyPiPControlsStyle()
            pipController.requiresLinearPlayback = true
            updatePiPAutomaticStartPolicy()
            pipController.addObserver(
                self,
                forKeyPath: "isPictureInPictureSuspended",
                options: [.new],
                context: nil
            )
        } catch {
            pipController = nil
            videoCallContentController = nil
            AppDebugLogger.log("PiP engine prepare failed: \(error.localizedDescription)")
        }
    }

    private func applyPiPControlsStyle() {
        _ = PiPCompatibilityAdapter.applyHiddenSystemControls(to: pipController)
    }

    private func setupCustomView() {
        customView = UIView()
        customView.backgroundColor = .white
        customView.isOpaque = true
        // Let the system own PiP interactions. App-installed tap handlers used to
        // intercept the expand gesture and close the PiP session unexpectedly.
        customView.isUserInteractionEnabled = false
        customView.clipsToBounds = true

        textView = UITextView()
        textView.text = originalPiPText
        textView.backgroundColor = .black
        textView.textColor = .white
        textView.isUserInteractionEnabled = false
        customView.addSubview(textView)
        pinToSuperview(textView)

        clockLabel = UILabel()
        clockLabel.textAlignment = .center
        clockLabel.textColor = .black
        clockLabel.backgroundColor = .white
        clockLabel.isOpaque = false
        clockLabel.layer.backgroundColor = UIColor.white.cgColor
        clockLabel.layer.isOpaque = false
        clockLabel.adjustsFontSizeToFitWidth = true
        clockLabel.minimumScaleFactor = 0.45
        clockLabel.baselineAdjustment = .alignCenters
        clockLabel.isHidden = true
        customView.addSubview(clockLabel)
        pinToSuperview(clockLabel)

        clockOverlayView = ClockOverlayView()
        clockOverlayView.isHidden = true
        clockOverlayView.alpha = 0
        customView.addSubview(clockOverlayView)
        pinToSuperview(clockOverlayView)

        configureRunningText()
    }

    private func attachCustomViewToPiPContent() {
        guard !shouldUsePlayerLayerPiPCompatibility else { return }
        guard let hostView = videoCallContentController?.view, let customView else { return }
        if customView.superview !== hostView {
            customView.removeFromSuperview()
            hostView.addSubview(customView)
            pinToSuperview(customView)
        }
        hostView.layoutIfNeeded()
    }

    private var originalPiPText: String {
        L10n.text("120Hz 已启动", "120 Hz started")
    }

    private func showPiPPreparationFailureMessage() {
        if shouldUsePlayerLayerPiPCompatibility,
           !PlaceholderVideoFactory.isPlayerLayerBackingVideoReady(forPointHeight: clampedPiPHeight) {
            showMessage(L10n.text(
                "兼容模式资源正在准备，请稍后再试",
                "Compatibility media is preparing. Please try again shortly."
            ))
            return
        }
        showMessage(L10n.text(
            "当前环境不支持悬浮窗",
            "Floating window is not supported here."
        ))
    }

    private func togglePiP() {
        SmartPerformanceGovernor.shared.beginInteractiveBurst()
        SmartPerformanceGovernor.shared.endInteractiveBurst(after: 0.75)
        DiagnosticsRuntimeState.recordUserAction((pipController?.isPictureInPictureActive ?? false) ? "点击关闭悬浮窗" : "点击开启悬浮窗")
        updateDiagnosticsPiPState()
        AppDebugLogger.log("Toggle PiP tapped, active=\(pipController?.isPictureInPictureActive ?? false), prepared=\(hasPreparedPiPInfrastructure), wants=\(wantsPiPActive)")
        if pipController?.isPictureInPictureActive != true {
            promotePlayerLayerMinimumHeightForNormalStartIfNeeded(reason: "首页普通开启")
        }
        if pipController == nil, !preparePiPInfrastructureIfNeeded() {
            isPiPActiveForUI = false
            showPiPPreparationFailureMessage()
            return
        }

        guard let pipController else {
            isPiPActiveForUI = false
            showPiPPreparationFailureMessage()
            return
        }

        recoverStalePiPTransitionIfNeeded(reason: "用户点击悬浮窗按钮")

        if isPiPTransitioning {
            AppDebugLogger.log("Toggle PiP ignored while transitioning")
            return
        }

        if pipController.isPictureInPictureActive {
            if requiresPiPCloseConfirmation {
                presentPiPCloseConfirmation()
            } else {
                performHomePiPClose(reason: "首页直接关闭")
            }
        } else {
            startPiPFromHome(autoHide: false)
        }
    }

    private func startPiPFromHome(autoHide: Bool) {
        guard pipController?.isPictureInPictureActive != true, !isPiPTransitioning else { return }
        AppDebugLogger.log("Start PiP requested, autoHide=\(autoHide)")
        cancelPiPHeightAnimation()
        cancelDelayedPiPHideCountdown(reason: autoHide ? "首页一键启动并隐藏" : "首页单独启动")
        shouldAutoHideAfterNextStart = autoHide
        wantsPiPActive = true
        hasPrimedPlayerLayerPiPStart = false
        updatePiPAutomaticStartPolicy()
        configureRunningText()
        startPiPSmoothly()
        updateHomeView(animated: true)
    }

    private func presentPiPCloseConfirmation() {
        let alert = UIAlertController(
            title: L10n.text("关闭悬浮窗？", "Close floating window?"),
            message: L10n.text("当前已开启防误触保护，请确认是否关闭悬浮窗。", "Confirm that you want to close the floating window."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel) { _ in
            DiagnosticsRuntimeState.recordUserAction("取消关闭悬浮窗")
            AppDebugLogger.log("用户取消关闭悬浮窗")
        })
        alert.addAction(UIAlertAction(title: L10n.text("确认关闭", "Close"), style: .destructive) { [weak self] _ in
            DiagnosticsRuntimeState.recordUserAction("确认关闭悬浮窗")
            self?.performHomePiPClose(reason: "防误触确认后关闭")
        })
        present(alert, animated: true)
    }

    private func performHomePiPClose(reason: String) {
        guard pipController?.isPictureInPictureActive == true else { return }
        AppDebugLogger.log("Stop PiP requested: \(reason)")
        shouldAutoHideAfterNextStart = false
        wantsPiPActive = false
        cancelDelayedPiPHideCountdown(reason: reason)
        updatePiPAutomaticStartPolicy()
        pipTasks.cancel(.startRetry)
        pipTasks.cancel(.startTimeout)
        stopPiPSmoothly()
        cancelPiPHeightAnimation()
        isPiPActiveForUI = false
    }

    private func hidePiPFromHome() {
        SmartPerformanceGovernor.shared.beginInteractiveBurst()
        SmartPerformanceGovernor.shared.endInteractiveBurst(after: 0.45)
        applyOneTapMinimumHeight(source: "首页单独隐藏")
    }

    private func startPiPAndHideFromHome() {
        SmartPerformanceGovernor.shared.beginInteractiveBurst()
        SmartPerformanceGovernor.shared.endInteractiveBurst(after: 0.75)
        if pipController?.isPictureInPictureActive == true {
            applyOneTapMinimumHeight(source: "首页启动并隐藏")
            return
        }

        promotePlayerLayerMinimumHeightForNormalStartIfNeeded(reason: "首页启动并隐藏")
        if pipController == nil, !preparePiPInfrastructureIfNeeded() {
            isPiPActiveForUI = false
            showPiPPreparationFailureMessage()
            return
        }
        guard pipController != nil else {
            isPiPActiveForUI = false
            showPiPPreparationFailureMessage()
            return
        }
        recoverStalePiPTransitionIfNeeded(reason: "用户点击启动并隐藏")
        startPiPFromHome(autoHide: true)
    }

    private func clearCacheFromHome() {
        guard pipController?.isPictureInPictureActive != true, !isPiPTransitioning else {
            showMessage(L10n.text(
                "请先关闭悬浮窗再清理缓存",
                "Stop the floating window before clearing cache."
            ))
            return
        }

        CacheCleanupManager.clearManually { [weak self] report in
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let freed = formatter.string(fromByteCount: report.freedBytes)
            let message = L10n.text(
                "缓存清理完成：删除 \(report.removedItems) 项，释放 \(freed)",
                "Cache cleared: \(report.removedItems) items, \(freed) freed."
            )
            self?.showMessage(message)
        }
    }

    private func applyOneTapMinimumHeight(source: String) {
        let actionTitle = shouldUsePlayerLayerPiPCompatibility ? "一键1pt" : "一键0.1pt"
        DiagnosticsRuntimeState.recordUserAction("\(source)：\(actionTitle)")
        AppDebugLogger.log("\(source) \(actionTitle) requested")

        guard let pipController, pipController.isPictureInPictureActive else {
            cancelDelayedPiPHideCountdown(reason: "\(source)\(actionTitle)但悬浮窗未开启")
            showMessage(L10n.text(
                "请先开启悬浮窗并拖到侧边吸附",
                "Enable PiP and dock it to the edge first."
            ))
            return
        }

        cancelDelayedPiPHideCountdown(reason: "\(source)\(actionTitle)")
        if shouldUsePlayerLayerPiPCompatibility {
            // PlayerLayer system PiP geometry follows media aspect ratio. Treat 1pt as a
            // transient hide state so closing/reopening returns to the normal default size.
            commitPiPHeight(currentMinimumPiPHeight, persistPreference: false)
        } else {
            animatePiPHeight(to: currentMinimumPiPHeight)
        }
        showMessage(shouldUsePlayerLayerPiPCompatibility
            ? L10n.text("已调整到1pt", "Set to 1 pt.")
            : L10n.text("已调整到0.1pt", "Set to 0.1 pt."))
    }

    private func cancelDelayedPiPHideCountdown(reason: String) {
        pipTasks.cancel(.autoHideAfterStart)
        if shouldAutoHideAfterNextStart {
            AppDebugLogger.log("Cancel stable-post-start auto-hide: \(reason)")
        }
        shouldAutoHideAfterNextStart = false
    }

    /// Drive the brief AVKit resize from the display clock. The animation uses the
    /// upcoming presentation time (`targetTimestamp`) rather than callback time, and
    /// geometry is submitted only when the resulting physical-pixel size changes.
    /// This keeps the transition display-synchronised without turning it into a second
    /// persistent refresh driver.
    private func animatePiPHeight(to requestedHeight: CGFloat) {
        let targetHeight = clampedHeight(requestedHeight)
        let startHeight = clampedPiPHeight
        cancelPiPHeightAnimation(settleCurrentGeometry: true)
        guard abs(startHeight - targetHeight) > 0.01,
              !UIAccessibility.isReduceMotionEnabled
        else {
            commitPiPHeight(targetHeight)
            return
        }

        pipHeightAnimationStartTimestamp = 0
        pipHeightAnimationStartHeight = startHeight
        pipHeightAnimationTargetHeight = targetHeight
        lastSubmittedPiPSizeInPixels = nil
        let link = CADisplayLink(target: self, selector: #selector(stepPiPHeightAnimation(_:)))
        let maximum = Float(min(120, AppDisplayContext.maximumFramesPerSecond))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: min(60, maximum),
            maximum: maximum,
            preferred: maximum
        )
        link.add(to: .main, forMode: .common)
        pipHeightAnimationDisplayLink = link
    }

    @objc private func stepPiPHeightAnimation(_ link: CADisplayLink) {
        guard UIApplication.shared.applicationState == .active,
              pipController?.isPictureInPictureActive == true
        else {
            cancelPiPHeightAnimation(settleCurrentGeometry: true)
            return
        }

        let presentationTimestamp = link.targetTimestamp > 0 ? link.targetTimestamp : link.timestamp
        if pipHeightAnimationStartTimestamp == 0 {
            pipHeightAnimationStartTimestamp = presentationTimestamp
        }
        let elapsed = max(0, presentationTimestamp - pipHeightAnimationStartTimestamp)
        let progress = min(1, CGFloat(elapsed / pipHeightAnimationDuration))
        let easedProgress = 1 - pow(1 - progress, 3)
        pipHeight = clampedHeight(
            pipHeightAnimationStartHeight
                + (pipHeightAnimationTargetHeight - pipHeightAnimationStartHeight) * easedProgress
        )
        submitPiPGeometryIfNeeded(synchronousLayout: false)

        guard progress >= 1 else { return }
        let targetHeight = pipHeightAnimationTargetHeight
        cancelPiPHeightAnimation()
        commitPiPHeight(targetHeight)
    }

    private func submitPiPGeometryIfNeeded(force: Bool = false, synchronousLayout: Bool = true) {
        let size = currentPiPSize
        let scale = AppDisplayContext.scale
        let pixelSize = CGSize(
            width: (size.width * scale).rounded(),
            height: (size.height * scale).rounded()
        )
        guard force || lastSubmittedPiPSizeInPixels != pixelSize else { return }
        lastSubmittedPiPSizeInPixels = pixelSize
        videoCallContentController?.preferredContentSize = size
        updatePiPSourceGeometry(force: force, synchronousLayout: synchronousLayout)
    }

    private func cancelPiPHeightAnimation(settleCurrentGeometry: Bool = false) {
        let hadActiveAnimation = pipHeightAnimationDisplayLink != nil
        pipHeightAnimationDisplayLink?.invalidate()
        pipHeightAnimationDisplayLink = nil
        pipHeightAnimationStartTimestamp = 0
        lastSubmittedPiPSizeInPixels = nil

        // During the fast path each tick changes only the source-view bounds while the
        // Auto Layout constraints intentionally remain at the last committed size. If the
        // animation is interrupted, converge those two truths once so a later layout pass
        // cannot snap the source view back to stale geometry.
        if settleCurrentGeometry,
           hadActiveAnimation,
           pipController?.isPictureInPictureActive == true,
           pipSourceView != nil {
            submitPiPGeometryIfNeeded(force: true, synchronousLayout: true)
        }
    }

    private func observeLooping(for playerItem: AVPlayerItem) {
        if let playerEndObserver = playerEndObserver {
            NotificationCenter.default.removeObserver(playerEndObserver)
        }
        playerEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.restartPlaybackFromBeginning()
        }
    }

    private func observePlaybackHealth(for player: AVPlayer, item: AVPlayerItem) {
        guard shouldPrepareBackingPlayerForPlayback, !shouldUsePlayerLayerPiPCompatibility else { return }
        if let playerStallObserver {
            NotificationCenter.default.removeObserver(playerStallObserver)
        }
        playerPauseObserver?.invalidate()

        playerStallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.keepPlaybackAlive()
        }

        playerPauseObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard
                let self,
                self.shouldKeepPiPPlaybackAlive,
                player.timeControlStatus == .paused
            else { return }
            DispatchQueue.main.async { self.keepPlaybackAlive() }
        }
    }

    private func observePlayerLayerPipelineHealth(for player: AVPlayer, item: AVPlayerItem) {
        if let playerStallObserver = playerStallObserver {
            NotificationCenter.default.removeObserver(playerStallObserver)
        }
        playerPauseObserver?.invalidate()
        playerPauseObserver = nil

        playerStallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.recoverPlayerLayerPipelineIfNeeded(reason: "PlayerLayer播放停滞")
        }

        if playerLayerTimeControlObserver == nil {
            playerLayerTimeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                guard let self, self.shouldUsePlayerLayerPiPCompatibility else { return }
                guard self.shouldKeepPiPPlaybackAlive else { return }
                guard player.timeControlStatus != .playing else { return }
                DispatchQueue.main.async {
                    self.recoverPlayerLayerPipelineIfNeeded(reason: "PlayerLayer状态=\(player.timeControlStatus.rawValue)")
                }
            }
        }
    }

    private func recoverPlayerLayerPipelineIfNeeded(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility, shouldKeepPiPPlaybackAlive else { return }
        guard let player = playerLayer?.player else { return }
        guard FrameRatePreference.isHighRefreshEnabled else {
            player.pause()
            resetPlayerLayerTransientStateForHighRefreshOff(reason: "强制120关闭，跳过PlayerLayer自愈")
            return
        }
        let now = CACurrentMediaTime()
        guard now - lastPlayerLayerPipelineRecoveryAt > 0.75 else { return }
        lastPlayerLayerPipelineRecoveryAt = now
        SpeedPerformanceLab.recordSelfHealingAttempt()
        if now - lastPlayerLayerRecoveryBurstStartedAt > 8.0 {
            lastPlayerLayerRecoveryBurstStartedAt = now
            recentPlayerLayerRecoveryCount = 0
        }
        recentPlayerLayerRecoveryCount += 1

        if recentPlayerLayerRecoveryCount >= 3 {
            recentPlayerLayerRecoveryCount = 0
            rebuildCurrentPlayerLayerItemForSelfHealing(reason: reason)
            return
        }

        configureBackingPlayerForPiP(player)
        if player.currentItem?.status == .readyToPlay {
            player.seek(to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player] _ in
                guard let self, self.shouldUsePlayerLayerPiPCompatibility, self.shouldKeepPiPPlaybackAlive else { return }
                player?.play()
                self.scheduleTransientPlayerLayerPiPAudioRelease(reason: "PlayerLayer管线自愈：\(reason)")
                AppDebugLogger.log("PlayerLayer pipeline recovered: \(reason)")
            }
        } else {
            player.play()
            scheduleTransientPlayerLayerPiPAudioRelease(reason: "PlayerLayer管线自愈：\(reason)")
            AppDebugLogger.log("PlayerLayer pipeline recovered without ready item: \(reason)")
        }
    }

    private func rebuildCurrentPlayerLayerItemForSelfHealing(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility, shouldKeepPiPPlaybackAlive, let player = playerLayer?.player else { return }
        guard let url = PlaceholderVideoFactory.resolvedPlayerLayerBackingVideoURL(forPointHeight: clampedPiPHeight) else {
            PlaceholderVideoFactory.prefetchPlayerLayerBackingVideos(
                around: clampedPiPHeight,
                direction: 0,
                policy: SmartPerformanceGovernor.shared.snapshot
            )
            player.play()
            return
        }
        let item = AVPlayerItem(asset: PlaceholderVideoFactory.cachedAsset(for: url))
        observeLooping(for: item)
        observePlayerLayerPipelineHealth(for: player, item: item)
        configureBackingPlayerForPiP(player)
        player.replaceCurrentItem(with: item)
        player.play()
        scheduleTransientPlayerLayerPiPAudioRelease(reason: "PlayerLayer深度自愈：\(reason)")
        AppDebugLogger.log("PlayerLayer item rebuilt by self-healing: \(reason)")
    }

    private func restartPlaybackFromBeginning() {
        guard let player = playerLayer?.player else { return }
        if shouldUsePlayerLayerPiPCompatibility {
            guard FrameRatePreference.isHighRefreshEnabled else {
                player.pause()
                resetPlayerLayerTransientStateForHighRefreshOff(reason: "强制120关闭，跳过PlayerLayer循环续播")
                return
            }
            player.seek(to: .zero) { [weak self, weak player] _ in
                guard let self, self.shouldKeepPiPPlaybackAlive else {
                    player?.pause()
                    return
                }
                player?.play()
                self.scheduleTransientPlayerLayerPiPAudioRelease(reason: "PlayerLayer视频循环续播")
            }
            return
        }
        // 单帧视频（duration ≈ 0.1s）播完后保持暂停，不循环
        // PiP 保活不需要 player 实际播放，只需 player 对象存在
        guard let item = player.currentItem, item.duration.seconds > 0.15 else {
            player.pause()  // 明确暂停，避免「播完-暂停-play()-播完」的每秒 10 次循环
            return
        }
        player.seek(to: .zero) { [weak self, weak player] _ in
            guard let self else { return }
            guard self.shouldKeepPiPPlaybackAlive else {
                player?.pause()
                return
            }
            self.updateBackingPlayerPlaybackForCurrentMode()
        }
    }

    private func keepPlaybackAlive() {
        guard shouldKeepPiPPlaybackAlive else {
            updateDisplaySleepDiagnostics(reason: "保活刷新未保活", shouldLog: true)
            return
        }
        recordPiPRuntimeHealthCheckpoint()
        UIApplication.shared.isIdleTimerDisabled = false
        if shouldUsePlayerLayerPiPCompatibility {
            BackgroundTaskManager.shared.forceStopAndDeactivate()
            PowerUsageLogger.markKeepAliveStop()
            KeepAliveLogger.heartbeat()
            if isPiPTransitioning && wantsPiPActive && !isOwnPiPConfirmedActive {
                primePlayerLayerPiPStartIfNeeded(reason: "PlayerLayer视频型PiP启动保活")
            } else {
                updateBackingPlayerPlaybackForCurrentMode()
                scheduleTransientPlayerLayerPiPAudioRelease(reason: "PlayerLayer视频型PiP保活")
            }
            updateDisplaySleepDiagnostics(reason: "PlayerLayer视频型PiP保活", shouldLog: true)
            AppDebugLogger.log(isPiPTransitioning && !isOwnPiPConfirmedActive ? "PlayerLayer PiP startup is primed with video pipeline" : "PlayerLayer PiP keeps video pipeline alive")
            return
        }
        if shouldUsePiPOnlyKeepAlive {
            PowerUsageLogger.markKeepAliveStop()
            KeepAliveLogger.heartbeat()
            // Pure VideoCall PiP has no backing player and must not churn AVAudioSession.
            // This keeps the normal route at: PiP session + one empty hard-max display link.
            updateBackingPlayerPlaybackForCurrentMode()
            updateDisplaySleepDiagnostics(reason: "纯PiP低功耗保活", shouldLog: true)
            AppDebugLogger.log("PiP-only keepAlive without media/audio work")
            return
        } else {
            configurePiPAudioSession()
            PowerUsageLogger.markKeepAliveStart()
            BackgroundTaskManager.shared.startPlay()
            KeepAliveLogger.heartbeat()
        }
        updateBackingPlayerPlaybackForCurrentMode()
        updateDisplaySleepDiagnostics(reason: "音频强保活", shouldLog: true)
    }

    private func recordPiPRuntimeHealthCheckpoint() {
        guard pipRuntimeStartedAt != nil || isOwnPiPConfirmedActive else { return }
        let now = Date()
        let defaults = UserDefaults.standard
        let previous = defaults.double(forKey: userDefaultsPiPRuntimeLastConfirmedAtKey)
        guard previous <= 0 || now.timeIntervalSince1970 - previous >= 30 else { return }
        defaults.set(now.timeIntervalSince1970, forKey: userDefaultsPiPRuntimeLastConfirmedAtKey)
    }

    private func pauseBackingPlayerIfIdle() {
        guard !shouldKeepPiPPlaybackAlive else { return }
        playerLayer?.player?.pause()
    }

    private var shouldPlayBackingPlayerForKeepAlive: Bool {
        if shouldUsePlayerLayerPiPCompatibility {
            return (isOwnPiPConfirmedActive || isPiPTransitioning) && wantsPiPActive
        }
        return !shouldUsePiPOnlyKeepAlive || shouldPrepareBackingPlayerForPlayback
    }

    private func updateBackingPlayerPlaybackForCurrentMode() {
        guard let player = playerLayer?.player else { return }
        configureBackingPlayerForPiP(player)
        if shouldUsePlayerLayerPiPCompatibility {
            guard FrameRatePreference.isHighRefreshEnabled else {
                player.pause()
                resetPlayerLayerTransientStateForHighRefreshOff(reason: "强制120关闭")
                updateDisplaySleepDiagnostics()
                return
            }
            // PlayerLayer keeps the known-compatible media cadence, but health recovery is
            // event-driven through timeControlStatus and playback-stalled notifications.
            player.play()
            scheduleTransientPlayerLayerPiPAudioRelease(reason: "PlayerLayer视频管线续播")
        } else if shouldPlayBackingPlayerForKeepAlive {
            player.play()
        } else {
            player.pause()
        }
        updateDisplaySleepDiagnostics()
    }

    private func configurePiPAudioSession() {
        do {
            if shouldUsePlayerLayerPiPCompatibility {
                configureTransientPlayerLayerPiPStartAudioSession(reason: "PlayerLayer PiP启动")
                return
            }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print(error)
        }
    }

    private func configureTransientPlayerLayerPiPStartAudioSession(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        guard shouldUsePlayerLayerPiPStartupAudioSession else {
            AppDebugLogger.log("PlayerLayer PiP startup audio session skipped to preserve system volume keys: \(reason)")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            let mode = playerLayerPiPStartAudioMode
            try session.setCategory(mode.category, mode: .default, options: mode.options)
            if mode.shouldActivateSession {
                try session.setActive(true)
                isPlayerLayerAudioSessionSettled = false
            }
            AppDebugLogger.log("PlayerLayer PiP transient \(mode.logName) audio session prepared: \(reason)")
        } catch {
            AppDebugLogger.log("PlayerLayer PiP transient audio prepare failed: \(reason), \(error.localizedDescription)")
        }
    }

    private func preparePlayerLayerVideoOnlyAudioState(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        pipTasks.cancel(.playerLayerAudioRelease)
        BackgroundTaskManager.shared.forceStopAndDeactivate()
        isPlayerLayerAudioSessionSettled = true
        AppDebugLogger.log("PlayerLayer video-only audio state prepared: \(reason)")
    }

    private func primePlayerLayerPiPStartIfNeeded(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        guard !hasPrimedPlayerLayerPiPStart else { return }
        hasPrimedPlayerLayerPiPStart = true
        pipTasks.cancel(.playerLayerAudioRelease)
        BackgroundTaskManager.shared.forceStopAndDeactivate()
        configureTransientPlayerLayerPiPStartAudioSession(reason: reason)

        guard let player = playerLayer?.player else {
            AppDebugLogger.log("PlayerLayer PiP prime skipped: player nil, reason=\(reason)")
            return
        }
        configureBackingPlayerForPiP(player)
        player.isMuted = true
        player.volume = 0

        let beginPlayback: () -> Void = { [weak self, weak player] in
            guard
                let self,
                self.shouldUsePlayerLayerPiPCompatibility,
                self.isPiPTransitioning,
                self.wantsPiPActive,
                !self.isOwnPiPConfirmedActive
            else {
                player?.pause()
                return
            }
            // 仿原作者：启动阶段就让 PlayerLayer 视频管线跑起来，避免额外空 DisplayLink。
            player?.play()
            self.updateDisplaySleepDiagnostics(reason: "PlayerLayer PiP启动预热", shouldLog: true)
            AppDebugLogger.log("PlayerLayer PiP primed video pipeline: \(reason)")
        }

        // A newly created/local-bundled item is already at the head. An unconditional exact
        // seek adds an avoidable asynchronous round trip before every compatibility start.
        // Seek only when the reused player has actually advanced far enough to need it.
        let currentSeconds = player.currentTime().seconds
        if currentSeconds.isFinite, currentSeconds > 0.25 {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                beginPlayback()
            }
        } else {
            beginPlayback()
        }
    }

    private func activatePlayerLayerPiPStartAudioIfNeeded(attempt: Int) -> Bool {
        guard shouldUsePlayerLayerPiPCompatibility else { return false }
        guard shouldUsePlayerLayerPiPStartupAudioSession else {
            if attempt == playerLayerActivePlaybackFallbackAttempt {
                AppDebugLogger.log("PlayerLayer PiP playback fallback suppressed to preserve system volume keys: attempt=\(attempt)")
            }
            return false
        }
        guard playerLayerPiPStartAudioMode != .playbackActive else { return false }
        guard attempt >= playerLayerActivePlaybackFallbackAttempt else { return false }
        // 从 ambient 升级到 playback category-only，不 setActive，不劫持音量键
        playerLayerPiPStartAudioMode = .playbackCategoryOnly
        hasPrimedPlayerLayerPiPStart = false
        AppDebugLogger.log("PlayerLayer PiP fallback to active playback audio session after \(PlayerLayerPiPStartAudioMode.defaultStartupMode.logName) attempts: attempt=\(attempt)")
        primePlayerLayerPiPStartIfNeeded(reason: "PlayerLayer PiP启动兜底")
        return true
    }

    private func deactivatePiPAudioSessionIfPossible() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            AppDebugLogger.log("Deactivate audio session skipped: \(error.localizedDescription)")
        }
    }

    private func releaseMediaAudioSessionForPiPOnly(reason: String) {
        guard shouldUsePiPOnlyKeepAlive else { return }
        guard !shouldUsePlayerLayerPiPCompatibility else {
            AppDebugLogger.log("PiP-only audio release skipped for PlayerLayer route: \(reason)")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.soloAmbient, mode: .default)
            AppDebugLogger.log("PiP-only released media audio session: \(reason)")
        } catch {
            AppDebugLogger.log("PiP-only audio release skipped: \(reason), \(error.localizedDescription)")
        }
    }

    private func releaseTransientPlayerLayerPiPAudioSession(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        pipTasks.cancel(.playerLayerAudioRelease)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.soloAmbient, mode: .default)
            isPlayerLayerAudioSessionSettled = true
            AppDebugLogger.log("PlayerLayer PiP released transient audio session: \(reason)")
        } catch {
            AppDebugLogger.log("PlayerLayer PiP audio release skipped: \(reason), \(error.localizedDescription)")
        }
    }

    private func scheduleTransientPlayerLayerPiPAudioRelease(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        guard !isPlayerLayerAudioSessionSettled else { return }
        guard shouldSettlePlayerLayerAudioAfterStart else {
            keepTransientPlayerLayerPiPAudioSession(reason: reason)
            return
        }
        guard pipController?.isPictureInPictureActive == true, !isPiPTransitioning, wantsPiPActive else { return }
        pipTasks.cancel(.playerLayerAudioRelease)
        pipTasks.schedule(.playerLayerAudioRelease, after: playerLayerAudioReleaseDelay) { [weak self] in
            guard
                let self,
                self.shouldUsePlayerLayerPiPCompatibility,
                self.shouldSettlePlayerLayerAudioAfterStart,
                self.pipController?.isPictureInPictureActive == true,
                !self.isPiPTransitioning,
                self.wantsPiPActive
            else {
                return
            }
            self.settleTransientPlayerLayerPiPAudioSession(reason: reason)
            self.updateDisplaySleepDiagnostics(reason: "PlayerLayer延迟切换音频类别", shouldLog: true)
        }
        AppDebugLogger.log("PlayerLayer PiP scheduled transient audio settle: \(reason), delay=\(String(format: "%.1f", playerLayerAudioReleaseDelay))s")
    }

    private var shouldSettlePlayerLayerAudioAfterStart: Bool {
        // PiP 启动成功后只做 setActive(false)，不改 category
        // 目标：音量键归还给系统（Ringtone），同时 PiP 仍存活
        true
    }

    private var shouldUsePlayerLayerPiPStartupAudioSession: Bool {
        // PlayerLayer PiP 需要 .playback 才能让 pipPossible=true
        true
    }

    private func keepTransientPlayerLayerPiPAudioSession(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        pipTasks.cancel(.playerLayerAudioRelease)
        AppDebugLogger.log("PlayerLayer PiP keeps \(playerLayerPiPStartAudioMode.logName) audio session to avoid auto stop: \(reason)")
    }

    private func settleTransientPlayerLayerPiPAudioSession(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        pipTasks.cancel(.playerLayerAudioRelease)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            isPlayerLayerAudioSessionSettled = true
            AppDebugLogger.log("PlayerLayer PiP deactivated audio session (kept category): \(reason)")
        } catch {
            AppDebugLogger.log("PlayerLayer PiP audio deactivation skipped: \(reason), \(error.localizedDescription)")
        }
    }

    private func resetPlayerLayerTransientStateForHighRefreshOff(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        pipTasks.cancel(.playerLayerAudioRelease)
        hasPrimedPlayerLayerPiPStart = false
        playerLayerPiPStartAudioMode = .defaultStartupMode
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            isPlayerLayerAudioSessionSettled = true
            AppDebugLogger.log("PlayerLayer transient state reset for high refresh off: \(reason)")
        } catch {
            AppDebugLogger.log("PlayerLayer high refresh off audio deactivate skipped: \(reason), \(error.localizedDescription)")
        }
    }

    private func settlePlayerLayerPiPAfterStart() {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        guard let player = playerLayer?.player else {
            preparePlayerLayerVideoOnlyAudioState(reason: "PiP启动完成但播放器不存在")
            return
        }
        guard FrameRatePreference.isHighRefreshEnabled else {
            player.pause()
            resetPlayerLayerTransientStateForHighRefreshOff(reason: "PiP启动完成但强制120关闭")
            updateDisplaySleepDiagnostics(reason: "PlayerLayer PiP启动后强制120关闭", shouldLog: true)
            return
        }
        player.play()
        scheduleTransientPlayerLayerPiPAudioRelease(reason: "PiP启动完成")
        updateDisplaySleepDiagnostics(reason: "PlayerLayer PiP启动后保持视频管线", shouldLog: true)
    }

    private var shouldKeepPiPPlaybackAlive: Bool {
        wantsPiPActive && (isOwnPiPConfirmedActive || isPiPTransitioning)
    }

    private var currentKeepAlivePolicy: KeepAlivePolicy {
        KeepAlivePolicy.current
    }

    private var shouldUsePiPOnlyKeepAlive: Bool {
        !currentKeepAlivePolicy.usesAudioContinuously && !isLockScreenAudioBoostActive
    }

    private func updateContinuousDiagnosticsForStableVideoCall(reason: String) {
        let shouldSuppress = !shouldUsePlayerLayerPiPCompatibility
            && currentKeepAlivePolicy == .pipOnly
            && shouldKeepPiPPlaybackAlive
        PerformanceDiagnosticsLogger.setRuntimeSamplingSuppressed(shouldSuppress, reason: reason)
    }

    private func updatePiPAutomaticStartPolicy() {
        pipController?.canStartPictureInPictureAutomaticallyFromInline = wantsPiPActive
    }

    private func beginPiPTransition(expectedActive: Bool, reason: String) {
        didRecoverStalePiPStop = false
        if shouldUsePlayerLayerPiPCompatibility, expectedActive {
            hasPrimedPlayerLayerPiPStart = false
            playerLayerPiPStartAudioMode = .defaultStartupMode
        }
        // A UIKit background task is only a short bridge while AVKit is taking
        // ownership of a PiP start. Stable PiP must not keep a generic background
        // assertion alive indefinitely.
        if expectedActive {
            beginBackgroundTaskIfNeeded()
        } else {
            endBackgroundTask()
        }
        // Delegate callbacks can arrive after our request path already created the same
        // transition. Do not replace an in-flight transition with an identical one; doing
        // so used to restart the watchdog/timestamps and created two runtime truths.
        if pipLifecycle.transitionExpectedActive != expectedActive {
            pipLifecycle.beginTransition(expectedActive: expectedActive, reason: reason)
        }
        schedulePiPTransitionWatchdog(reason: reason)
    }

    private func finishPiPTransition() {
        pipTasks.cancel(.transitionWatchdog)
        pipLifecycle.finishTransition()
        endBackgroundTask()
    }

    private func schedulePiPTransitionWatchdog(reason: String) {
        pipTasks.schedule(.transitionWatchdog, after: piPTransitionWatchdogDelay) { [weak self] in
            self?.recoverStalePiPTransition(reason: "watchdog: \(reason)")
        }
    }

    private var piPTransitionWatchdogDelay: TimeInterval {
        pipTransitionExpectedActive == false ? 6.0 : 4.0
    }

    private var piPStopTransitionGraceDelay: TimeInterval {
        1.5
    }

    private func recoverStalePiPTransition(reason: String) {
        guard isPiPTransitioning else { return }

        let active = pipController?.isPictureInPictureActive ?? false
        let elapsed = pipTransitionStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let expectedText = pipTransitionExpectedActive.map(String.init(describing:)) ?? "nil"
        AppDebugLogger.log(
            "PiP transition watchdog recovered: reason=\(reason), startedReason=\(pipTransitionReason), elapsed=\(String(format: "%.1f", elapsed))s, active=\(active), wants=\(wantsPiPActive), ui=\(isPiPActiveForUI), stopping=\(isStoppingPiP), expectedActive=\(expectedText)"
        )

        pipTasks.cancelAll()
        pipTasks.cancel(.playerLayerAudioRelease)
        hasPrimedPlayerLayerPiPStart = false
        playerLayerPiPStartAudioMode = .defaultStartupMode
        let recoveredExpectedStop = pipTransitionExpectedActive == false
        finishPiPTransition()
        isStoppingPiP = false
        didRecoverStalePiPStop = recoveredExpectedStop

        let pendingRoute = pendingPiPEngineRouteAfterStop
        if active {
            wantsPiPActive = true
            isOwnPiPConfirmedActive = true
            isPiPActiveForUI = true
            updatePiPAutomaticStartPolicy()
            prepareCustomViewForPiPStart()
            configureRunningText()
            showPiPContentForOpening()
            if pipRuntimeStartedAt == nil {
                beginPiPRuntimeSession()
            }
            if isScrollingEnabled, !shouldRenderClockMode {
                startDisplayLinks()
            }
            keepPlaybackAlive()
            KeepAliveLogger.heartbeat()

            // A route switch can lose its settle task when the watchdog cancels all
            // transition work. If AVKit is still active, preserve the pending route
            // and immediately restart the stop sequence after state has converged.
            if let pendingRoute {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.pendingPiPEngineRouteAfterStop == pendingRoute else { return }
                    self.stopPiPSmoothly()
                }
            }
        } else {
            releaseTransientPlayerLayerPiPAudioSession(reason: "PiP过渡状态恢复未启动")
            handleOwnPiPInvalidated(reason: "PiP过渡状态恢复：\(reason)")
            if let pendingRoute {
                pendingPiPEngineRouteAfterStop = nil
                DispatchQueue.main.async { [weak self] in
                    self?.applyPiPEngineRoute(pendingRoute)
                }
            }
        }

        updateDiagnosticsPiPState()
        updateDisplaySleepDiagnostics(reason: "PiP过渡状态恢复", shouldLog: true)
        updateHomeView()
    }

    @discardableResult
    private func recoverStalePiPTransitionIfNeeded(reason: String) -> Bool {
        if recoverStalePiPStopTransitionIfNeeded(reason: reason) {
            return true
        }
        guard isPiPTransitioning, let pipTransitionStartedAt else { return false }
        guard Date().timeIntervalSince(pipTransitionStartedAt) >= piPTransitionWatchdogDelay else { return false }
        recoverStalePiPTransition(reason: reason)
        return true
    }

    @discardableResult
    private func recoverStalePiPStopTransitionIfNeeded(reason: String) -> Bool {
        guard isPiPTransitioning, !wantsPiPActive else { return false }
        guard let pipTransitionStartedAt else {
            recoverStalePiPTransition(reason: "\(reason)：停止转场缺少开始时间")
            return true
        }
        guard Date().timeIntervalSince(pipTransitionStartedAt) >= piPStopTransitionGraceDelay else { return false }
        recoverStalePiPTransition(reason: "\(reason)：停止转场超时")
        return true
    }

    private var shouldPreviewPiPHeightLive: Bool {
        (isOwnPiPConfirmedActive || isPiPTransitioning) && !isPiPSuspendedAtSide
    }

    private var shouldRunPiPContentUpdates: Bool {
        guard !isExtremeSilentModeEnabled else { return false }
        return (isOwnPiPConfirmedActive || isPiPTransitioning) && !isPiPSuspendedAtSide && !isPiPVisuallyHidden
    }

    private var shouldRunLowCostPiPContentUpdates: Bool {
        (isOwnPiPConfirmedActive || isPiPTransitioning) && !isPiPSuspendedAtSide && !isPiPVisuallyHidden
    }

    private func updateAutoHiddenOverheadState(reason: String) {
        guard !shouldUsePlayerLayerPiPCompatibility else { return }
        guard isOwnPiPConfirmedActive || isPiPTransitioning else { return }
        if isPiPVisuallyHidden {
            pauseAutoHiddenOverheadIfNeeded(reason: reason)
        } else {
            resumeAutoHiddenOverheadIfNeeded(reason: reason)
        }
    }

    private func pauseAutoHiddenOverheadIfNeeded(reason: String) {
        if isAutoHiddenOverheadPaused {
            applyStableVideoCallHiddenSurface()
            return
        }
        isAutoHiddenOverheadPaused = true
        stopDisplayLinks()
        stopClockTimer()
        applyStableVideoCallHiddenSurface()
        AppDebugLogger.log("PiP 0.1pt hidden mode paused extra overhead: \(reason)")
    }

    private func applyStableVideoCallHiddenSurface() {
        textView?.isHidden = true
        textView?.alpha = 0
        textView?.layer.opacity = 0
        clockLabel?.isHidden = true
        clockLabel?.alpha = 0
        clockLabel?.layer.opacity = 0
        clockOverlayView?.isHidden = true
        clockOverlayView?.alpha = 0
        clockOverlayView?.layer.opacity = 0
    }

    private func resumeAutoHiddenOverheadIfNeeded(reason: String) {
        guard isAutoHiddenOverheadPaused else { return }
        isAutoHiddenOverheadPaused = false
        configureRunningText()
        if shouldRenderClockMode {
            startClockTimerIfNeeded()
        } else if isScrollingEnabled, !isContentExtremeModeEnabled {
            startDisplayLinks()
        }
        AppDebugLogger.log("PiP hidden mode resumed content overhead: \(reason)")
    }

    private func handleOwnPiPInvalidated(reason: String) {
        let hadOwnSession = isOwnPiPConfirmedActive || pipRuntimeStartedAt != nil
        let shouldNotifyStopped = hadOwnSession
            && !isStoppingPiP
            && !isClosingPiPFromCustomContentTap
            && !KeepAliveNotificationTester.shouldSuppressPiPStoppedNotification(reason: reason)
        let stoppedMode = currentKeepAlivePolicy.diagnosticsName
        pipExpectedActiveBeforeStop = nil
        resumeAutoHiddenOverheadIfNeeded(reason: "PiP失效")
        cancelDelayedPiPHideCountdown(reason: "悬浮窗失效")
        wantsPiPActive = false
        isOwnPiPConfirmedActive = false
        isPiPActiveForUI = false
        isStoppingPiP = false
        didRecoverStalePiPStop = false
        hasPrimedPlayerLayerPiPStart = false
        playerLayerPiPStartAudioMode = .defaultStartupMode
        updatePiPAutomaticStartPolicy()
        detachLegacyCustomViewIfNeeded()
        stopDisplayLinks()
        stopClockTimer()
        resetLockScreenAudioBoost(reason: reason)
        BackgroundTaskManager.shared.stopPlay()
        releaseTransientPlayerLayerPiPAudioSession(reason: reason)
        PowerUsageLogger.markKeepAliveStop()
        pauseBackingPlayerIfIdle()
        endBackgroundTask()
        if pipRuntimeStartedAt != nil || pipRuntimeDuration > 0 {
            if reason.hasPrefix("进入前台") {
                let detectedAt = Date()
                let lastConfirmedDate = runtimeLastConfirmedDate(defaults: .standard, fallback: detectedAt)
                finishPiPRuntimeSession(stoppedAt: detectedAt)
                AppDebugLogger.log(
                    "PiP invalidation discovered in foreground, lastConfirmed=\(formattedStopTime(lastConfirmedDate)), detectedAt=\(formattedStopTime(detectedAt))"
                )
            } else {
                finishPiPRuntimeSession()
            }
        }
        if hadOwnSession {
            KeepAliveLogger.markPiPStopped(reason: reason)
        }
        if shouldNotifyStopped {
            KeepAliveNotificationTester.schedulePiPStoppedNotification(mode: stoppedMode, reason: reason)
        }
        updateContinuousDiagnosticsForStableVideoCall(reason: "PiP失效")
        ProcessTerminationDiagnostics.recordCheckpoint(reason: "PiP失效：\(reason)")
        AppDebugLogger.log("Own PiP invalidated: \(reason)")
    }

    private func validateOwnPiPState(reason: String) {
        guard isOwnPiPConfirmedActive, pipController?.isPictureInPictureActive != true else { return }
        handleOwnPiPInvalidated(reason: "\(reason)：本App悬浮窗已失效，可能被其他PiP挤掉")
        updateDiagnosticsPiPState()
        updateHomeView()
    }

    private var isPlayerReadyForPiP: Bool {
        guard requiresPlayerLayerForPiP else {
            return true
        }
        guard
            let player = playerLayer?.player,
            let item = player.currentItem,
            item.status == .readyToPlay
        else {
            return false
        }
        return player.status != .failed
    }

    private var requiresPlayerLayerForPiP: Bool {
        shouldUsePlayerLayerPiPCompatibility
    }

    private var shouldPrepareBackingPlayerForPlayback: Bool {
        // BETA4_ANCHOR_BILIBILI_DANMAKU_FIX:
        // 回归 beta3：iOS 15+ VideoCall contentSource 不额外准备 PlayerLayer backing player。
        return requiresPlayerLayerForPiP
    }

    private func makePlayerItem() -> AVPlayerItem? {
        if shouldUsePlayerLayerPiPCompatibility {
            switch effectivePiPEngineRoute {
            case .playerLayerGenerated:
                return makeGeneratedPlayerLayerLongVideoItem()
            case .auto, .videoCall:
                break
            }
        }

        let videoScale = max(AppDisplayContext.scale, 1)
        let backingVideoSize = CGSize(
            width: evenVideoDimension(max(currentPiPSize.width * videoScale, 2)),
            height: evenVideoDimension(max(currentPiPSize.height * videoScale, 2))
        )
        let videoText = shouldRenderClockMode ? "" : L10n.text("120Hz 已启动", "120 Hz started")
        let url = GeneratedPiPVideoCache.videoURL(
            named: "pip-static-h264-clear-v3-\(Int(backingVideoSize.width))x\(Int(backingVideoSize.height))-\(videoText.isEmpty ? "blank" : "text").mov"
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try PlaceholderVideoFactory.makeBackingVideo(
                    at: url,
                    size: backingVideoSize,
                    text: videoText
                )
            } catch {
                print(error)
                AppDebugLogger.log("Placeholder video failed: \(error.localizedDescription)")
                return nil
            }
        }
        GeneratedPiPVideoCache.trim(excluding: [url])
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        return item
    }

    private func makeGeneratedPlayerLayerLongVideoItem() -> AVPlayerItem? {
        // PlayerLayer PiP derives the system window aspect ratio from media presentation
        // size. Keep the known-good 30 fps cadence, but use a cached low-pixel asset whose
        // aspect ratio exactly matches the requested 300pt-wide compatibility surface.
        let targetHeight = clampedPiPHeight
        guard let url = PlaceholderVideoFactory.resolvedPlayerLayerBackingVideoURL(forPointHeight: targetHeight) else {
            // Bundled media is the normal 2.3.6 path. Keep runtime generation only as a
            // resilience fallback for a damaged/missing resource package.
            PlaceholderVideoFactory.prewarmPlayerLayerBackingVideo(forPointHeight: targetHeight)
            AppDebugLogger.log("PlayerLayer geometry video not ready; PiP setup deferred")
            return nil
        }
        if !url.isFileURL || !url.path.contains("/CompatibilityMedia/") {
            GeneratedPiPVideoCache.trim(excluding: [url])
        }
        return AVPlayerItem(asset: PlaceholderVideoFactory.cachedAsset(for: url))
    }

    private func evenVideoDimension(_ value: CGFloat) -> CGFloat {
        max(2, ceil(value / 2) * 2)
    }

    private func evenVideoDimensionFloor(_ value: CGFloat) -> CGFloat {
        max(2, floor(value / 2) * 2)
    }

    private func beginBackgroundTaskIfNeeded() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PiPStartTransition") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func startDisplayLinks() {
        // Production Speed has no scrolling-content cadence. Invalidate any object left
        // by an in-process migration instead of allowing a second persistent display link.
        stopDisplayLinks()
    }

    private func stopDisplayLinks() {
        scrollDisplayLink?.invalidate()
        scrollDisplayLink = nil
        lastScrollTimestamp = nil
    }

    private func startClockTimerIfNeeded() {
        // Clock/FPS rendering is removed from the production runtime. Never create a
        // Timer or CADisplayLink here; the only persistent cadence is RefreshRateController.
        stopClockTimer()
    }

    private func stopClockTimer() {
        clockDisplayLink?.invalidate()
        clockDisplayLink = nil
        clockRenderTimer?.invalidate()
        clockRenderTimer = nil
        lastClockTimestamp = nil
        clockFrameCount = 0
        pendingMeasuredPiPFPS = nil
        pendingMeasuredPiPFPSCount = 0
        pendingMeasuredPiPFPSStartedAt = nil
        lastClockOverlayTimeText = ""
        lastClockOverlayFPSText = ""
        lastClockRenderTick = -1
        lastBackgroundClockDiagnosticsTimestamp = nil
    }

    private func resetClockMetrics() {
        stopClockTimer()
        measuredPiPFPS = 0
    }

    @objc private func handlePiPContentTap(_ gesture: UITapGestureRecognizer) {
        _ = gesture
    }

    @objc private func handlePiPDirectCloseTap(_ gesture: UITapGestureRecognizer) {
        _ = gesture
    }

    private func closePiPFromFloatingContent(reason: String) {
        isClosingPiPFromCustomContentTap = true
        wantsPiPActive = false
        updatePiPAutomaticStartPolicy()
        stopPiPSmoothly()
    }

    @objc private func updateClockLabel() {
        let shouldRun = isContentExtremeModeEnabled ? shouldRunLowCostPiPContentUpdates : shouldRunPiPContentUpdates
        guard shouldRenderClockMode, shouldRun else {
            stopClockTimer()
            return
        }
        updateClockOverlay(timestamp: CACurrentMediaTime())
    }

    @objc private func updateClockDisplay(_ displayLink: CADisplayLink) {
        guard shouldRenderClockMode, shouldRunPiPContentUpdates else {
            stopClockTimer()
            return
        }
        logBackgroundClockDiagnosticsIfNeeded(displayLink)
        updateMeasuredFPS(from: displayLink)
        updateClockOverlay(timestamp: displayLink.timestamp)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "isPictureInPictureSuspended" {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let isSuspended = self.pipController?.isPictureInPictureSuspended ?? false
                self.pipLifecycle.setSuspendedAtSide(isSuspended)
                AppDebugLogger.log("PiP suspend state changed: \(isSuspended), height=\(self.formattedHeight(self.clampedPiPHeight)), clock=\(self.shouldRenderClockMode), scroll=\(self.isScrollingEnabled)")
                if self.shouldUsePlayerLayerPiPCompatibility {
                    self.updateDiagnosticsPiPState()
                    return
                }
                // VideoCall PiP has no backing media/audio pipeline. Dock/undock should
                // therefore be a pure AVKit lifecycle event with zero extra media work.
                self.stopDisplayLinks()
                self.stopClockTimer()
                self.updateDiagnosticsPiPState()
            }
        }
    }

    private func scheduleAutoHideAfterStablePiPStartIfNeeded(reason: String) {
        guard shouldAutoHideAfterNextStart else { return }
        pipTasks.cancel(.autoHideAfterStart)
        pipTasks.schedule(.autoHideAfterStart, after: 0.90) { [weak self] in
            guard let self else { return }
            guard self.shouldAutoHideAfterNextStart else { return }
            guard let controller = self.pipController, controller.isPictureInPictureActive else { return }
            // `isPictureInPictureSuspended` means the system has suspended PiP; it is not
            // a public "docked to screen edge" signal. Never shrink while system-suspended.
            guard !controller.isPictureInPictureSuspended else { return }
            self.shouldAutoHideAfterNextStart = false
            AppDebugLogger.log("Stable-post-start auto-hide committed: \(reason)")
            if self.shouldUsePlayerLayerPiPCompatibility {
                self.commitPiPHeight(self.currentMinimumPiPHeight)
            } else {
                self.animatePiPHeight(to: self.currentMinimumPiPHeight)
            }
            self.configureRunningText()
        }
    }

    private func logBackgroundClockDiagnosticsIfNeeded(_ displayLink: CADisplayLink) {
        // This function is called from a display-link callback. When diagnostics are off,
        // leave the 120 Hz hot path before reading state, calculating FPS or formatting logs.
        guard AppDebugLogger.isDebugModeEnabled else {
            lastBackgroundClockDiagnosticsTimestamp = nil
            return
        }
        let isSuspended = isPiPSuspendedAtSide
        if lastLoggedPiPSuspendedAtSide != isSuspended {
            lastLoggedPiPSuspendedAtSide = isSuspended
            if let clockDisplayLink {
                configureForClockRefreshRate(clockDisplayLink)
            }
            AppDebugLogger.log("PiP suspended state changed: \(isSuspended)")
        }
        guard UIApplication.shared.applicationState == .background else {
            lastBackgroundClockDiagnosticsTimestamp = nil
            return
        }
        if let lastBackgroundClockDiagnosticsTimestamp,
           displayLink.timestamp - lastBackgroundClockDiagnosticsTimestamp < 5.0 {
            return
        }
        lastBackgroundClockDiagnosticsTimestamp = displayLink.timestamp
        let interval = displayLink.targetTimestamp - displayLink.timestamp
        let instantFPS = interval > 0.001 ? Int((1.0 / interval).rounded()) : 0
        AppDebugLogger.log(
            "后台时间悬浮窗采样：suspended=\(isSuspended),height=\(formattedHeight(clampedPiPHeight)),instantFPS=\(instantFPS),measuredFPS=\(measuredPiPFPS),timestamp=\(String(format: "%.3f", displayLink.timestamp))"
        )
    }

    private func updateMeasuredFPS(from displayLink: CADisplayLink) {
        let frameInterval = displayLink.targetTimestamp - displayLink.timestamp
        guard frameInterval > 0.001 else { return }

        let instantFPS = Int((1.0 / frameInterval).rounded())
        let normalizedFPS = normalizedMeasuredFPS(instantFPS)

        // 调试日志：查看 DisplayLink 实际读到的刷新率
        if measuredPiPFPS != normalizedFPS {
            AppDebugLogger.log("FPS probe: instant=\(instantFPS), normalized=\(normalizedFPS), current=\(measuredPiPFPS), force120Hz=\(FrameRatePreference.isHighRefreshEnabled)")
        }

        if measuredPiPFPS == 0 {
            measuredPiPFPS = normalizedFPS
            pendingMeasuredPiPFPS = nil
            pendingMeasuredPiPFPSCount = 0
            pendingMeasuredPiPFPSStartedAt = nil
            return
        }

        guard normalizedFPS != measuredPiPFPS else {
            pendingMeasuredPiPFPS = nil
            pendingMeasuredPiPFPSCount = 0
            pendingMeasuredPiPFPSStartedAt = nil
            return
        }

        if pendingMeasuredPiPFPS == normalizedFPS {
            pendingMeasuredPiPFPSCount += 1
        } else {
            pendingMeasuredPiPFPS = normalizedFPS
            pendingMeasuredPiPFPSCount = 1
            pendingMeasuredPiPFPSStartedAt = displayLink.timestamp
        }

        let confirmation = fpsConfirmationRequirement(
            from: measuredPiPFPS,
            to: normalizedFPS,
            forceHighRefreshEnabled: FrameRatePreference.isHighRefreshEnabled
        )
        let pendingDuration = displayLink.timestamp - (pendingMeasuredPiPFPSStartedAt ?? displayLink.timestamp)
        if pendingMeasuredPiPFPSCount >= confirmation.count && pendingDuration >= confirmation.duration {
            measuredPiPFPS = normalizedFPS
            pendingMeasuredPiPFPS = nil
            pendingMeasuredPiPFPSCount = 0
            pendingMeasuredPiPFPSStartedAt = nil
        }
    }

    private func fpsConfirmationRequirement(
        from currentFPS: Int,
        to candidateFPS: Int,
        forceHighRefreshEnabled: Bool
    ) -> (count: Int, duration: CFTimeInterval) {
        guard candidateFPS > currentFPS else { return (3, 0) }

        if forceHighRefreshEnabled, candidateFPS >= 120 {
            return (3, 0.02)
        }

        if candidateFPS >= 120 {
            if currentFPS <= 60 {
                return (8, 0.18)
            }
            return (24, 0.9)
        }
        return (5, 0.12)
    }

    private var displayedFPS: Int {
        return measuredPiPFPS
    }

    private func updateClockOverlay(timestamp: CFTimeInterval) {
        guard let clockOverlayView else { return }
        let now = Date()
        let renderTick = isContentExtremeModeEnabled
            ? Int(now.timeIntervalSince1970.rounded(.down))
            : Int((now.timeIntervalSince1970 * 10).rounded(.down))
        let fpsText = isContentExtremeModeEnabled ? "" : "\(displayedFPS)Hz"
        guard renderTick != lastClockRenderTick
            || fpsText != lastClockOverlayFPSText else {
            return
        }

        let timeText = clockFormatter.string(from: now)
        guard timeText != lastClockOverlayTimeText
            || fpsText != lastClockOverlayFPSText else {
            return
        }
        lastClockRenderTick = renderTick
        lastClockOverlayTimeText = timeText
        lastClockOverlayFPSText = fpsText
        clockLabel?.text = timeText
        clockOverlayView.update(time: timeText, fps: fpsText)
    }

    private func normalizedMeasuredFPS(_ rawFPS: Int) -> Int {
        let hardwareMaximum = max(60, AppDisplayContext.maximumFramesPerSecond)
        let clampedFPS = min(max(30, rawFPS), hardwareMaximum)
        let standardRates = [30, 45, 60, 75, 80, 90, 100, 120].filter { $0 <= hardwareMaximum }
        guard let nearest = standardRates.min(by: { abs($0 - clampedFPS) < abs($1 - clampedFPS) }) else {
            return clampedFPS
        }
        let distance = abs(nearest - clampedFPS)
        if distance <= 5 {
            return nearest
        }
        return Int((Double(clampedFPS) / 5.0).rounded() * 5.0)
    }

    @discardableResult
    private func activateAutoCompatibilityFallbackIfNeeded(reason: String) -> Bool {
        guard pipEngineRoute == .auto, !isLegacyPlayerLayerFallbackActive else { return false }
        let shouldRestart = wantsPiPActive || isPiPTransitioning
        AppDebugLogger.log("Auto engine falling back to PlayerLayer: \(reason)")

        pipTasks.cancelAll()
        if isPiPTransitioning { finishPiPTransition() }
        isStoppingPiP = false
        isLegacyPlayerLayerFallbackActive = true
        autoFallbackRestartAttempts = 0
        if hasPreparedPiPInfrastructure { teardownPiPInfrastructure() }
        pipHeight = playerLayerDefaultPiPHeight
        isCompactPiPStyle = true
        RefreshRateController.shared.setRuntimeMode(.playerLayer)
        PlaceholderVideoFactory.prefetchPlayerLayerBackingVideos(
            around: clampedPiPHeight,
            direction: 0,
            policy: SmartPerformanceGovernor.shared.snapshot
        )
        wantsPiPActive = shouldRestart
        updateHomeView(animated: true)
        if shouldRestart { scheduleAutoFallbackRestart() }
        return true
    }

    private func scheduleAutoFallbackRestart() {
        autoFallbackRestartAttempts += 1
        let attempt = autoFallbackRestartAttempts
        guard attempt <= 12 else {
            resetPiPStartStateAfterFailure()
            AppDebugLogger.log("Auto fallback exhausted after \(attempt - 1) attempts")
            return
        }
        pipTasks.schedule(.startRetry, after: attempt == 1 ? 0.05 : 0.10) { [weak self] in
            guard let self, self.pipEngineRoute == .auto, self.isLegacyPlayerLayerFallbackActive, self.wantsPiPActive else { return }
            if self.preparePiPInfrastructureIfNeeded() {
                self.startPiPSmoothly()
            } else {
                PlaceholderVideoFactory.prefetchPlayerLayerBackingVideos(
                    around: self.clampedPiPHeight,
                    direction: 0,
                    policy: SmartPerformanceGovernor.shared.snapshot
                )
                self.scheduleAutoFallbackRestart()
            }
        }
    }

    private func startPiPSmoothly() {
        guard pipController != nil else {
            isPiPActiveForUI = false
            return
        }
        if shouldUsePlayerLayerPiPCompatibility {
            startLegacyPlayerLayerPiP()
            return
        }

        guard !isPiPTransitioning else {
            isPiPActiveForUI = pipController.isPictureInPictureActive
            return
        }
        restoreMinimumRememberedHeightIfNeeded()
        beginPiPTransition(expectedActive: true, reason: "start smooth")
        isStoppingPiP = false
        AppDebugLogger.log("Start PiP smoothly, route=VideoCall, size=\(Int(currentPiPSize.width))x\(Int(currentPiPSize.height))")
        prepareCustomViewForPiPStart()
        restorePiPVisualSurfaces()
        showPiPContentForOpening()
        prepareSourceLayerForPiP()
        keepPlaybackAlive()
        requestPiPStartWhenReady()
    }

    private func startLegacyPlayerLayerPiP() {
        guard pipController != nil else {
            isPiPActiveForUI = false
            return
        }
        guard !isPiPTransitioning else {
            isPiPActiveForUI = pipController.isPictureInPictureActive
            return
        }
        restoreMinimumRememberedHeightIfNeeded()
        captureWindowsBeforePiPStart()
        beginPiPTransition(expectedActive: true, reason: "start legacy")
        isStoppingPiP = false
        prepareCustomViewForPiPStart()
        restorePiPVisualSurfaces()
        showPiPContentForOpening()
        prepareSourceLayerForPiP()
        primePlayerLayerPiPStartIfNeeded(reason: "PlayerLayer PiP开始启动")
        schedulePiPStartTimeout()
        requestLegacyPlayerLayerPiPStartWhenReady()
    }

    private func requestLegacyPlayerLayerPiPStartWhenReady(attempt: Int = 0) {
        pipTasks.cancel(.startRetry)
        pipTasks.schedule(.startRetry, after: piPStartRetryDelay(for: attempt)) { [weak self] in
            guard
                let self,
                self.isPiPTransitioning,
                let pipController = self.pipController,
                !pipController.isPictureInPictureActive
            else {
                return
            }
            guard self.isPlayerReadyForPiP && pipController.isPictureInPicturePossible else {
                AppDebugLogger.log("Wait PlayerLayer PiP: attempt=\(attempt), possible=\(pipController.isPictureInPicturePossible), playerReady=\(self.isPlayerReadyForPiP)")
                if attempt < self.maximumPiPStartAttempts {
                    _ = self.activatePlayerLayerPiPStartAudioIfNeeded(attempt: attempt)
                    self.requestLegacyPlayerLayerPiPStartWhenReady(attempt: attempt + 1)
                } else {
                    self.resetPiPStartStateAfterFailure()
                    let message = "PlayerLayer PiP暂时不可启动：possible=\(pipController.isPictureInPicturePossible), playerReady=\(self.isPlayerReadyForPiP)"
                    AppDebugLogger.log(message)
                    print(message)
                }
                return
            }
            AppDebugLogger.log("PlayerLayer PiP startPictureInPicture requested at attempt=\(attempt)")
            _ = self.pipEngine.requestStart()
            self.schedulePlayerLayerPiPStartConfirmationRetry(afterStartAttempt: attempt)
        }
    }

    private func schedulePlayerLayerPiPStartConfirmationRetry(afterStartAttempt attempt: Int) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        pipTasks.schedule(.startRetry, after: 0.85) { [weak self] in
            guard
                let self,
                self.shouldUsePlayerLayerPiPCompatibility,
                self.isPiPTransitioning,
                self.wantsPiPActive,
                let pipController = self.pipController,
                !pipController.isPictureInPictureActive
            else {
                return
            }
            guard attempt < self.maximumPiPStartAttempts else {
                self.resetPiPStartStateAfterFailure()
                AppDebugLogger.log("PlayerLayer PiP start ignored and retries exhausted: attempt=\(attempt)")
                return
            }
            AppDebugLogger.log("PlayerLayer PiP start request was ignored; retrying, attempt=\(attempt + 1), possible=\(pipController.isPictureInPicturePossible), playerReady=\(self.isPlayerReadyForPiP)")
            self.requestLegacyPlayerLayerPiPStartWhenReady(attempt: attempt + 1)
        }
    }

    private func restoreMinimumRememberedHeightIfNeeded() {
        guard !shouldUsePlayerLayerPiPCompatibility, clampedPiPHeight <= currentGeometryMetrics.minimumHeight + 0.01 else { return }
        pipHeight = compactPiPHeight
        isCompactPiPStyle = true
        submitPiPGeometryIfNeeded(force: true)
        configureRunningText()
        if remembersPiPHeight {
            saveCurrentPiPHeightPreference()
        }
        updateHomeView()
    }

    private func restorePlayerLayerDefaultHeightAfterStopIfNeeded(reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        guard clampedPiPHeight <= currentMinimumPiPHeight + 0.01 else { return }

        pipTasks.cancel(.playerLayerGeometryPreview)
        pipHeight = playerLayerDefaultPiPHeight
        isCompactPiPStyle = true
        if remembersPiPHeight {
            saveCurrentPiPHeightPreference()
        }
        requestPlayerLayerMedia(for: playerLayerDefaultPiPHeight, reason: "关闭后恢复默认尺寸")
        updateHomeView()
        AppDebugLogger.log("PlayerLayer restored default height after stop: \(formattedHeight(playerLayerDefaultPiPHeight)), reason=\(reason)")
    }

    private func stopPiPSmoothly() {
        guard pipController != nil else {
            isPiPActiveForUI = false
            return
        }
        guard !isPiPTransitioning else {
            pipTasks.cancel(.startRetry)
            finishPiPTransition()
            isPiPActiveForUI = pipController.isPictureInPictureActive
            return
        }
        wantsPiPActive = false
        updatePiPAutomaticStartPolicy()
        beginPiPTransition(expectedActive: false, reason: "stop smooth")
        isStoppingPiP = true
        pipTasks.cancel(.startRetry)
        pipTasks.cancel(.startTimeout)
        stopDisplayLinks()
        stopClockTimer()
        if shouldUseVideoCallOffscreenCloseAnimation {
            movePiPSourceViewOffscreenForClosing()
        } else {
            hidePiPContentForClosing()
            preparePiPVisualSurfacesForClosing()
            movePiPSourceViewOffscreenForClosing()
        }
        _ = pipEngine.requestStop()
    }

    private func resignForegroundAfterPiPCloseIfNeeded(reason: String) {
        guard shouldResignForegroundAfterPiPClose else { return }
        foregroundResignRetryGeneration &+= 1
        let generation = foregroundResignRetryGeneration
        hideForegroundWindowsForPiPClose(reason: reason)
        if UIApplication.shared.applicationState != .background {
            AppDebugLogger.log("PiP close resign foreground immediately: reason=\(reason), state=\(UIApplication.shared.applicationState.rawValue)")
            guard PiPCompatibilityAdapter.requestResignForeground() else {
                shouldResignForegroundAfterPiPClose = false
                restoreForegroundWindowsHiddenForPiPCloseIfNeeded()
                return
            }
        }

        let delays: [TimeInterval] = [0, 0.03, 0.12, 0.3]
        for (index, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard
                    let self,
                    self.foregroundResignRetryGeneration == generation,
                    self.shouldResignForegroundAfterPiPClose
                else { return }
                if UIApplication.shared.applicationState != .background {
                    AppDebugLogger.log("PiP close resign foreground: reason=\(reason), delay=\(delay)")
                    _ = PiPCompatibilityAdapter.requestResignForeground()
                } else if UIApplication.shared.applicationState == .background {
                    self.shouldResignForegroundAfterPiPClose = false
                }
                if index == delays.indices.last {
                    self.shouldResignForegroundAfterPiPClose = false
                }
            }
        }
    }

    private func hideForegroundWindowsForPiPClose(reason: String) {
        guard windowsHiddenForPiPClose.isEmpty else { return }
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !$0.isHidden && $0.alpha > 0.001 }
        guard !windows.isEmpty else { return }
        windowsHiddenForPiPClose = windows.map { ($0, $0.alpha) }
        UIView.performWithoutAnimation {
            windows.forEach { $0.alpha = 0 }
        }
        AppDebugLogger.log("Hide app windows before PiP close foreground restore: reason=\(reason), count=\(windows.count)")
        pipTasks.schedule(.foregroundWindowRestore, after: 1.5) { [weak self] in
            guard let self, !self.shouldResignForegroundAfterPiPClose else { return }
            self.restoreForegroundWindowsHiddenForPiPCloseIfNeeded()
        }
    }

    private func restoreForegroundWindowsHiddenForPiPCloseIfNeeded() {
        guard !windowsHiddenForPiPClose.isEmpty else { return }
        UIView.performWithoutAnimation {
            windowsHiddenForPiPClose.forEach { item in
                item.window.alpha = item.alpha
            }
        }
        windowsHiddenForPiPClose.removeAll()
        AppDebugLogger.log("Restore app windows hidden for PiP close")
    }

    @discardableResult
    private func triggerSystemPiPCloseControlIfAvailable(reason: String) -> Bool {
        guard pipController?.isPictureInPictureActive == true else { return false }
        let controls = systemPiPControls()
        let diagnostics = controls.map(systemPiPControlDescription).joined(separator: ";")
        let sortedControls = controls.sorted { lhs, rhs in
            let lhsFrame = lhs.convert(lhs.bounds, to: nil)
            let rhsFrame = rhs.convert(rhs.bounds, to: nil)
            if abs(lhsFrame.midY - rhsFrame.midY) > 2 {
                return lhsFrame.midY < rhsFrame.midY
            }
            return lhsFrame.midX < rhsFrame.midX
        }
        guard let control = sortedControls.first(where: isLikelySystemPiPCloseControl) else {
            AppDebugLogger.log("System PiP close control unavailable: reason=\(reason), controls=\(diagnostics)")
            return false
        }

        AppDebugLogger.log("Trigger system PiP close control: reason=\(reason), control=\(systemPiPControlDescription(control))")
        wantsPiPActive = false
        isPiPActiveForUI = false
        updatePiPAutomaticStartPolicy()
        if !control.accessibilityActivate() {
            control.sendActions(for: [.touchUpInside, .primaryActionTriggered])
        }
        return true
    }

    private func systemPiPControls() -> [UIControl] {
        allApplicationWindows()
            .filter { window in
                window !== view.window
                    && !window.isHidden
                    && window.alpha > 0
            }
            .flatMap { window in
                visibleControls(in: window)
            }
            .filter { control in
                control !== customView
                    && control.window !== view.window
                    && isControlOutsideCustomPiPContent(control)
            }
    }

    private func installDirectCloseGestureForSystemPiPControls(reason: String) {
        _ = reason
        removeDirectCloseGestureForSystemPiPControls()
    }

    private func removeDirectCloseGestureForSystemPiPControls() {
        if let gesture = pipDirectCloseTapGesture {
            pipDirectCloseGestureHost?.removeGestureRecognizer(gesture)
        }
        pipDirectCloseTapGesture = nil
        pipDirectCloseGestureHost = nil
    }

    private func candidatePiPGestureHostView() -> UIView? {
        let visibleWindows = allApplicationWindows().filter {
            $0 !== view.window
                && !$0.isHidden
                && $0.alpha > 0
                && $0.bounds.width > 1
                && $0.bounds.height > 1
        }
        if let newWindow = visibleWindows.first(where: { !windowsBeforePiPStart.contains(ObjectIdentifier($0)) }) {
            return newWindow
        }
        return visibleWindows.first
    }

    private func updateSystemPiPControlsForDirectClose(reason: String) {
        let controls = systemPiPControls()
        guard !controls.isEmpty else {
            AppDebugLogger.log("No system PiP controls to adjust: reason=\(reason)")
            return
        }
        for control in controls {
            let frame = control.convert(control.bounds, to: nil)
            let screen = control.window?.windowScene?.screen.bounds ?? AppDisplayContext.bounds
            let isLeftCloseArea = frame.minX <= screen.width * 0.40
            control.alpha = 0.01
            control.isHidden = false
            control.isUserInteractionEnabled = isLeftCloseArea
            AppDebugLogger.log("Adjust PiP system control: reason=\(reason), left=\(isLeftCloseArea), control=\(systemPiPControlDescription(control))")
        }
    }

    private func visibleControls(in rootView: UIView) -> [UIControl] {
        var controls: [UIControl] = []
        func visit(_ view: UIView) {
            if let control = view as? UIControl {
                controls.append(control)
            }
            view.subviews.forEach(visit)
        }
        visit(rootView)
        return controls
    }

    private func isControlOutsideCustomPiPContent(_ control: UIControl) -> Bool {
        var current: UIView? = control
        while let view = current {
            if view === customView || view === textView || view === clockOverlayView || view === clockLabel {
                return false
            }
            current = view.superview
        }
        return true
    }

    private func isLikelySystemPiPCloseControl(_ control: UIControl) -> Bool {
        let text = [
            String(describing: type(of: control)),
            control.accessibilityLabel,
            control.accessibilityIdentifier,
            control.accessibilityHint
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        if text.contains("close")
            || text.contains("dismiss")
            || text.contains("stop")
            || text.contains("关闭")
            || text.contains("結束")
            || text.contains("退出")
            || text.contains("xmark") {
            return true
        }

        let frame = control.convert(control.bounds, to: nil)
        let screen = control.window?.windowScene?.screen.bounds ?? AppDisplayContext.bounds
        let maxSide = max(frame.width, frame.height)
        let minSide = min(frame.width, frame.height)
        let isSmallButton = maxSide <= 72 && minSide >= 16
        let isNearTopLeft = frame.minY <= screen.height * 0.28
            && frame.minX <= screen.width * 0.40
        return isSmallButton && isNearTopLeft && control.allTargets.count > 0
    }

    private func systemPiPControlDescription(_ control: UIControl) -> String {
        let frame = control.convert(control.bounds, to: nil)
        let label = control.accessibilityLabel ?? "-"
        let identifier = control.accessibilityIdentifier ?? "-"
        return "\(type(of: control)){hidden=\(control.isHidden),alpha=\(String(format: "%.2f", control.alpha)),enabled=\(control.isEnabled),frame=\(formatRect(frame)),label=\(label),id=\(identifier),targets=\(control.allTargets.count)}"
    }

    private func requestPiPStartWhenReady(attempt: Int = 0) {
        pipTasks.cancel(.startRetry)
        pipTasks.schedule(.startRetry, after: piPStartRetryDelay(for: attempt)) { [weak self] in
            guard let self else { return }

            self.prepareCustomViewForPiPStart()
            self.restorePiPVisualSurfaces()
            self.showPiPContentForOpening()
            self.prepareSourceLayerForPiP()
            self.keepPlaybackAlive()

            guard let pipSourceView = self.pipSourceView, let pipController = self.pipController else {
                self.resetPiPStartStateAfterFailure()
                return
            }

            let sourceReady = !pipSourceView.bounds.isEmpty && pipSourceView.window != nil
            let canStartNow = self.isPlayerReadyForPiP && sourceReady && pipController.isPictureInPicturePossible

            if canStartNow {
                _ = self.pipEngine.requestStart()
                return
            }

            if attempt < self.maximumPiPStartAttempts {
                self.requestPiPStartWhenReady(attempt: attempt + 1)
            } else {
                let message = "画中画暂时不可启动：possible=\(pipController.isPictureInPicturePossible), playerReady=\(self.isPlayerReadyForPiP), sourceReady=\(sourceReady)"
                if self.activateAutoCompatibilityFallbackIfNeeded(reason: message) { return }
                self.resetPiPStartStateAfterFailure()
                AppDebugLogger.log(message)
                print(message)
            }
        }
    }

    private var maximumPiPStartAttempts: Int {
        if shouldUsePlayerLayerPiPCompatibility {
            return 36
        }
        return 8
    }

    private func piPStartRetryDelay(for attempt: Int) -> TimeInterval {
        if shouldUsePlayerLayerPiPCompatibility {
            // 2.3.6 ships ready-to-use compatibility media, so the first readiness probe
            // no longer needs to wait for a background encoder. Give AVPlayer only one
            // short run-loop settle, then retry quickly if AVKit is not possible yet.
            return attempt == 0 ? 0.03 : 0.08
        }
        return attempt == 0 ? 0.02 : 0.12
    }

    private func schedulePiPStartTimeout() {
        pipTasks.cancel(.startTimeout)
        pipTasks.schedule(.startTimeout, after: piPStartTimeoutDuration) { [weak self] in
            guard
                let self,
                self.isPiPTransitioning,
                let pipController = self.pipController,
                !pipController.isPictureInPictureActive
            else {
                return
            }
            if self.activateAutoCompatibilityFallbackIfNeeded(reason: "PiP start timeout") { return }
            self.resetPiPStartStateAfterFailure()
            AppDebugLogger.log("PiP start timeout")
            print("画中画启动超时，已恢复按钮状态")
        }
    }

    private var piPStartTimeoutDuration: TimeInterval {
        shouldUsePlayerLayerPiPCompatibility ? 8.0 : 8.0
    }

    private func resetPiPStartStateAfterFailure() {
        pipTasks.cancelAll()
        cancelDelayedPiPHideCountdown(reason: "悬浮窗启动失败")
        shouldAutoHideAfterNextStart = false
        pipExpectedActiveBeforeStop = nil
        hasPrimedPlayerLayerPiPStart = false
        isLegacyPlayerLayerFallbackActive = false
        playerLayerPiPStartAudioMode = .defaultStartupMode
        wantsPiPActive = false
        isOwnPiPConfirmedActive = pipController?.isPictureInPictureActive ?? false
        updatePiPAutomaticStartPolicy()
        detachLegacyCustomViewIfNeeded()
        isPiPActiveForUI = pipController?.isPictureInPictureActive ?? false
        isStoppingPiP = false
        finishPiPTransition()
        if pipController?.isPictureInPictureActive != true {
            finishPiPRuntimeSession()
        }
        if pipController?.isPictureInPictureActive != true {
            stopDisplayLinks()
            BackgroundTaskManager.shared.stopPlay()
            pauseBackingPlayerIfIdle()
            releaseTransientPlayerLayerPiPAudioSession(reason: "PiP启动失败恢复")
            endBackgroundTask()
        }
    }

    private func prepareCustomViewForPiPStart() {
        if shouldUsePlayerLayerPiPCompatibility {
            guard shouldAttachCustomViewInPlayerLayerPiP else {
                detachLegacyCustomViewIfNeeded()
                return
            }
            attachCustomViewToPiPWindowIfAvailable(reason: "prepare start")
        } else {
            attachCustomViewToPiPContent()
        }
    }

    private func attachCustomViewToKeyWindow() {
        guard shouldAttachCustomViewInPlayerLayerPiP else { return }
        attachCustomViewToPiPWindowIfAvailable(reason: "legacy fallback")
    }

    private func captureWindowsBeforePiPStart() {
        windowsBeforePiPStart = Set(allApplicationWindows().map { ObjectIdentifier($0) })
    }

    @discardableResult
    private func attachCustomViewToPiPWindowIfAvailable(reason: String) -> Bool {
        guard shouldUsePlayerLayerPiPCompatibility, let customView else { return false }
        guard let hostView = candidatePiPHostViewForCustomView() else {
            AppDebugLogger.log("Skip attach custom view: PiP host unavailable, reason=\(reason), windows=\(windowDiagnosticsForPiPAttach())")
            return false
        }
        if customView.superview !== hostView {
            customView.removeFromSuperview()
            hostView.addSubview(customView)
            AppDebugLogger.log("Attach custom view to PiP host, reason=\(reason), host=\(type(of: hostView)), bounds=\(hostView.bounds), window=\(type(of: hostView.window))")
        }
        updateLegacyCustomViewGeometry()
        hostView.layoutIfNeeded()
        return true
    }

    private func allApplicationWindows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
    }

    private func candidatePiPHostViewForCustomView() -> UIView? {
        let windows = allApplicationWindows()
        let visibleWindows = windows.filter {
            !$0.isHidden
                && $0.alpha > 0
                && $0.bounds.width > 1
                && $0.bounds.height > 1
        }

        if let currentHost = customView?.superview,
           currentHost !== view,
           currentHost.window !== view.window,
           isSafePiPHostView(currentHost) {
            return currentHost
        }

        let newWindows = visibleWindows.filter { window in
            window !== view.window && !windowsBeforePiPStart.contains(ObjectIdentifier(window))
        }
        if let host = newWindows.compactMap({ safePiPHostView(in: $0) }).first {
            return host
        }

        if pipController?.isPictureInPictureActive == true {
            let nonMainWindows = visibleWindows.filter { $0 !== view.window }
            if let host = nonMainWindows.compactMap({ safePiPHostView(in: $0) }).first {
                return host
            }
        }

        return nil
    }

    private func safePiPHostView(in window: UIWindow) -> UIView? {
        if isSafePiPHostView(window) {
            return window
        }
        return safePiPSubviewCandidates(in: window).first
    }

    private func safePiPSubviewCandidates(in rootView: UIView) -> [UIView] {
        var candidates: [UIView] = []
        func visit(_ candidate: UIView) {
            if isSafePiPHostView(candidate) {
                candidates.append(candidate)
            }
            candidate.subviews.forEach(visit)
        }
        rootView.subviews.forEach(visit)
        return candidates.sorted { lhs, rhs in
            let lhsArea = lhs.bounds.width * lhs.bounds.height
            let rhsArea = rhs.bounds.width * rhs.bounds.height
            return lhsArea > rhsArea
        }
    }

    private func isSafePiPHostView(_ candidate: UIView) -> Bool {
        guard !candidate.isHidden, candidate.alpha > 0 else { return false }
        let bounds = candidate.bounds
        guard bounds.width >= currentPiPSize.width * 0.5,
              bounds.height >= currentPiPSize.height * 0.5 else {
            return false
        }

        let screenBounds = candidate.window?.windowScene?.screen.bounds ?? AppDisplayContext.bounds
        let screenWidth = max(screenBounds.width, screenBounds.height)
        let screenHeight = min(screenBounds.width, screenBounds.height)
        let candidateWidth = max(bounds.width, bounds.height)
        let candidateHeight = min(bounds.width, bounds.height)
        let isFullscreenLike = candidateWidth >= screenWidth * 0.92
            && candidateHeight >= screenHeight * 0.92
        return !isFullscreenLike
    }

    private func windowDiagnosticsForPiPAttach() -> String {
        allApplicationWindows().enumerated().map { index, window in
            let marker = windowsBeforePiPStart.contains(ObjectIdentifier(window)) ? "old" : "new"
            let isMain = window === view.window ? "main" : "other"
            return "#\(index){\(marker),\(isMain),hidden=\(window.isHidden),alpha=\(String(format: "%.2f", window.alpha)),bounds=\(formatRect(window.bounds)),type=\(type(of: window))}"
        }.joined(separator: ";")
    }

    private func detachLegacyCustomViewIfNeeded() {
        guard shouldUsePlayerLayerPiPCompatibility, let customView else { return }
        customView.removeFromSuperview()
    }

    private func hidePiPContentForClosing() {
        guard let customView, let textView else { return }
        UIView.performWithoutAnimation {
            customView.layer.removeAllAnimations()
            customView.alpha = 0
            customView.layer.opacity = 0
            textView.alpha = 0
            textView.layer.opacity = 0
            clockLabel?.alpha = 0
            clockLabel?.layer.opacity = 0
            clockOverlayView?.alpha = 0
            clockOverlayView?.layer.opacity = 0
            customView.superview?.layoutIfNeeded()
        }
    }

    private func showPiPContentForOpening() {
        guard let customView, let textView else { return }
        guard !shouldUsePlayerLayerPiPCompatibility || shouldAttachCustomViewInPlayerLayerPiP else {
            hidePiPContentForClosing()
            return
        }
        if shouldRenderClockMode {
            updateClockAppearance()
            updateClockOverlay(timestamp: CACurrentMediaTime())
        }
        UIView.performWithoutAnimation {
            textView.alpha = 1
            clockLabel?.alpha = 0
            clockLabel?.isHidden = true
            customView.alpha = 1
            customView.layer.opacity = 1
            textView.layer.opacity = textView.isHidden ? 0 : 1
            clockLabel?.layer.opacity = 0
            clockOverlayView?.layer.opacity = (shouldRenderClockMode && !isPiPVisuallyHidden) ? 1 : 0
            clockOverlayView?.alpha = (shouldRenderClockMode && !isPiPVisuallyHidden) ? 1 : 0
            customView.superview?.layoutIfNeeded()
        }
    }

    private func preparePiPVisualSurfacesForClosing() {
        guard let pipSourceView else { return }
        UIView.performWithoutAnimation {
            pipSourceView.backgroundColor = .clear
            pipSourceView.layer.backgroundColor = UIColor.clear.cgColor
            pipSourceView.alpha = 0.01
            videoCallContentController?.preferredContentSize = CGSize(width: 1, height: 1)
            videoCallContentController?.view.backgroundColor = .clear
            videoCallContentController?.view.layer.backgroundColor = UIColor.clear.cgColor
            videoCallContentController?.view.alpha = 0.01
            playerLayer?.opacity = 0
            playerLayer?.backgroundColor = UIColor.clear.cgColor
            playerLayer?.removeAllAnimations()
            view.layoutIfNeeded()
        }
    }

    private func restorePiPVisualSurfaces() {
        guard let pipSourceView else { return }
        UIView.performWithoutAnimation {
            restorePiPSourceViewFrame()
            pipSourceView.alpha = 1
            pipSourceView.layer.opacity = 1
            pipSourceView.backgroundColor = .clear
            pipSourceView.layer.backgroundColor = UIColor.clear.cgColor
            pipSourceView.isOpaque = false
            pipSourceView.layer.isOpaque = false
            submitPiPGeometryIfNeeded(force: true)
            videoCallContentController?.view.alpha = 1
            videoCallContentController?.view.backgroundColor = .clear
            videoCallContentController?.view.layer.backgroundColor = UIColor.clear.cgColor
            videoCallContentController?.view.isOpaque = false
            videoCallContentController?.view.layer.isOpaque = false
            playerLayer?.opacity = shouldUsePlayerLayerPiPCompatibility ? 1 : 0
            playerLayer?.backgroundColor = UIColor.clear.cgColor
            view.layoutIfNeeded()
        }
    }

    private func movePiPSourceViewOffscreenForClosing() {
        guard let pipSourceView else { return }
        UIView.performWithoutAnimation {
            NSLayoutConstraint.deactivate(pipSourcePlacementConstraints)
            pipSourceWidthConstraint = nil
            pipSourceHeightConstraint = nil
            let closingConstraints = [
                pipSourceView.topAnchor.constraint(equalTo: view.topAnchor, constant: -8),
                pipSourceView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -8),
                pipSourceView.widthAnchor.constraint(equalToConstant: 1),
                pipSourceView.heightAnchor.constraint(equalToConstant: 1)
            ]
            pipSourcePlacementConstraints = closingConstraints
            NSLayoutConstraint.activate(closingConstraints)
            view.layoutIfNeeded()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer?.frame = CGRect(x: -8, y: -8, width: 1, height: 1)
            playerLayer?.removeAllAnimations()
            CATransaction.commit()
        }
    }

    private func restorePiPSourceViewFrame() {
        updatePiPSourceGeometry(force: true)
    }

    private func updatePiPSourceGeometry(force: Bool = false, synchronousLayout: Bool = true) {
        guard let pipSourceView else { return }
        let size = currentPiPSize
        let scale = AppDisplayContext.scale
        let pixelSize = CGSize(
            width: (size.width * scale).rounded(),
            height: (size.height * scale).rounded()
        )
        let constraintsMissing = pipSourceWidthConstraint == nil || pipSourceHeightConstraint == nil
        guard force || constraintsMissing || lastAppliedPiPSourceSizeInPixels != pixelSize else { return }
        lastAppliedPiPSourceSizeInPixels = pixelSize

        pipSourceView.alpha = 1
        pipSourceView.layer.opacity = 1
        videoCallContentController?.view.alpha = 1
        playerLayer?.opacity = shouldUsePlayerLayerPiPCompatibility ? 1 : 0
        if synchronousLayout {
            if let pipSourceWidthConstraint, let pipSourceHeightConstraint {
                pipSourceWidthConstraint.constant = size.width
                pipSourceHeightConstraint.constant = size.height
            } else {
                installCenteredPiPSourceConstraints(size: size)
            }
            // Full layout is required for setup/commit boundaries, but not for every
            // display-clock tick of the standard-route hide animation.
            view.layoutIfNeeded()
            centerPlayerLayer()
            updateLegacyCustomViewGeometry()
        } else if !shouldUsePlayerLayerPiPCompatibility {
            // Do not touch Auto Layout constraints here: changing NSLayoutConstraint
            // constants would schedule a root layout pass on every 120 Hz animation tick.
            // The source view is center constrained, so bounds-only animation is enough;
            // the final commit updates constraints and performs one synchronous layout.
            pipSourceView.bounds.size = size
        }
    }

    private func updateLegacyCustomViewGeometry() {
        guard shouldUsePlayerLayerPiPCompatibility, let customView, customView.superview != nil else { return }
        customView.superview?.layoutIfNeeded()
    }

    private func configureRunningText() {
        guard let textView else { return }
        if shouldUsePlayerLayerPiPCompatibility && !shouldAttachCustomViewInPlayerLayerPiP {
            stopDisplayLinks()
            stopClockTimer()
            customView?.removeFromSuperview()
            textView.isHidden = true
            clockLabel?.isHidden = true
            clockOverlayView?.isHidden = true
            return
        }
        if isPiPVisuallyHidden {
            stopDisplayLinks()
            stopClockTimer()
            applyStableVideoCallHiddenSurface()
            return
        }
        if shouldRenderClockMode {
            stopDisplayLinks()
            customView?.backgroundColor = .white
            customView?.layer.backgroundColor = UIColor.white.cgColor
            customView?.layer.opacity = 1
            customView?.layer.isOpaque = true
            customView?.isOpaque = true
            pipSourceView?.backgroundColor = .clear
            pipSourceView?.layer.backgroundColor = UIColor.clear.cgColor
            pipSourceView?.isOpaque = false
            pipSourceView?.layer.isOpaque = false
            videoCallContentController?.view.backgroundColor = .clear
            videoCallContentController?.view.layer.backgroundColor = UIColor.clear.cgColor
            videoCallContentController?.view.isOpaque = false
            videoCallContentController?.view.layer.isOpaque = false
            textView.isHidden = true
            textView.alpha = 0
            textView.layer.opacity = 0
            clockLabel?.isHidden = true
            clockLabel?.alpha = 0
            clockLabel?.layer.opacity = 0
            clockOverlayView?.isHidden = false
            clockOverlayView?.alpha = 1
            clockOverlayView?.layer.opacity = 1
            updateClockAppearance()
            if shouldPreviewPiPHeightLive {
                startClockTimerIfNeeded()
            } else {
                stopClockTimer()
            }
            return
        }

        stopClockTimer()
        customView?.backgroundColor = .white
        customView?.layer.backgroundColor = UIColor.white.cgColor
        customView?.layer.opacity = 1
        customView?.layer.isOpaque = true
        customView?.isOpaque = true
        clockLabel?.isHidden = true
        clockLabel?.alpha = 0
        clockLabel?.layer.opacity = 0
        clockOverlayView?.isHidden = true
        clockOverlayView?.alpha = 0
        clockOverlayView?.layer.opacity = 0
        clockLabel?.backgroundColor = .clear
        clockLabel?.layer.backgroundColor = UIColor.clear.cgColor
        clockLabel?.isOpaque = false
        clockLabel?.layer.isOpaque = false
        pipSourceView?.backgroundColor = .clear
        pipSourceView?.layer.backgroundColor = UIColor.clear.cgColor
        pipSourceView?.isOpaque = false
        pipSourceView?.layer.isOpaque = false
        videoCallContentController?.view.backgroundColor = .clear
        videoCallContentController?.view.layer.backgroundColor = UIColor.clear.cgColor
        videoCallContentController?.view.isOpaque = false
        videoCallContentController?.view.layer.isOpaque = false
        textView.isHidden = false
        textView.alpha = 1
        textView.text = originalPiPText
        textView.backgroundColor = .black
        textView.layer.backgroundColor = UIColor.black.cgColor
        textView.layer.opacity = 1
        textView.layer.isOpaque = true
        textView.textColor = .white
        textView.isOpaque = true
        textView.setContentOffset(.zero, animated: false)
        textView.layoutIfNeeded()
        if isScrollingEnabled, !isContentExtremeModeEnabled, shouldPreviewPiPHeightLive {
            startDisplayLinks()
        } else {
            stopDisplayLinks()
        }
    }

    private func updateClockAppearance() {
        guard let clockLabel else { return }
        let shouldHideClockSurface = isPiPVisuallyHidden
        let fontSize = min(max(clampedPiPHeight * 0.74, 18), 58)
        clockLabel.font = .monospacedDigitSystemFont(ofSize: fontSize, weight: .black)
        clockLabel.textColor = shouldHideClockSurface ? .clear : .black
        clockLabel.backgroundColor = shouldHideClockSurface ? .clear : .white
        clockLabel.layer.backgroundColor = (shouldHideClockSurface ? UIColor.clear : UIColor.white).cgColor
        clockLabel.isHidden = true
        clockLabel.alpha = 0
        clockLabel.layer.opacity = 0
        clockLabel.layer.isOpaque = false
        clockLabel.isOpaque = false
        clockOverlayView?.configure(height: clampedPiPHeight, hidden: shouldHideClockSurface)
        customView?.backgroundColor = shouldHideClockSurface ? .clear : .white
        customView?.layer.backgroundColor = (shouldHideClockSurface ? UIColor.clear : UIColor.white).cgColor
        customView?.layer.opacity = shouldHideClockSurface ? 0 : 1
        customView?.layer.isOpaque = !shouldHideClockSurface
        customView?.isOpaque = !shouldHideClockSurface
        pipSourceView?.backgroundColor = .clear
        pipSourceView?.layer.backgroundColor = UIColor.clear.cgColor
        pipSourceView?.isOpaque = false
        pipSourceView?.layer.isOpaque = false
        videoCallContentController?.view.backgroundColor = .clear
        videoCallContentController?.view.layer.backgroundColor = UIColor.clear.cgColor
        videoCallContentController?.view.isOpaque = false
        videoCallContentController?.view.layer.isOpaque = false
        textView?.isHidden = true
        textView?.backgroundColor = .clear
        textView?.layer.backgroundColor = UIColor.clear.cgColor
        textView?.alpha = 0
        textView?.layer.opacity = 0
        textView?.layer.isOpaque = false
        textView?.textColor = .clear
        textView?.isOpaque = false
        updateClockOverlay(timestamp: CACurrentMediaTime())
    }

    private func toggleScrolling() {
        guard !isContentExtremeModeEnabled else {
            showMessage(L10n.text("内容极限模式下已固定为静态文本", "Text is fixed in content extreme mode."))
            return
        }
        guard !isClockModeEnabled else {
            AppDebugLogger.log("Ignore text scrolling toggle while clock mode is enabled")
            return
        }
        DiagnosticsRuntimeState.recordUserAction(isScrollingEnabled ? "关闭悬浮窗内容滚动" : "开启悬浮窗内容滚动")
        isScrollingEnabled.toggle()
        AppDebugLogger.log("PiP text scrolling changed, enabled=\(isScrollingEnabled)")
        if isScrollingEnabled, !shouldRenderClockMode {
            if pipController?.isPictureInPictureActive == true {
                startDisplayLinks()
            }
        } else {
            stopDisplayLinks()
        }
    }

    private func setClockMode(_ isEnabled: Bool) {
        DiagnosticsRuntimeState.recordUserAction(isEnabled ? "切换为时分秒悬浮窗" : "切换为文本悬浮窗")
        if isEnabled {
            guard isClockModeFeatureEnabled else {
                UserDefaults.standard.set(false, forKey: userDefaultsClockModeEnabledKey)
                isClockModeEnabled = false
                prefersTextScrolling = true
                UserDefaults.standard.set(true, forKey: userDefaultsScrollingEnabledKey)
                isScrollingEnabled = true
                updateHomeView()
                AppDebugLogger.log("Clock mode blocked below iOS 26 to avoid ProMotion fallback")
                return
            }
            isClockModeEnabled = true
            isScrollingEnabled = false
        } else {
            prefersTextScrolling = true
            UserDefaults.standard.set(true, forKey: userDefaultsScrollingEnabledKey)
            isClockModeEnabled = false
            isScrollingEnabled = true
        }
        AppDebugLogger.log("PiP clock mode changed, enabled=\(isClockModeEnabled)")
        submitPiPGeometryIfNeeded(force: true)
        if pipController?.isPictureInPictureActive == true {
            configureRunningText()
            if !shouldRenderClockMode && isScrollingEnabled && !isContentExtremeModeEnabled {
                startDisplayLinks()
            }
        } else if !shouldRenderClockMode {
            stopClockTimer()
        }
        updateDiagnosticsPiPState()
        logPiPSurfaceDiagnostics("clock mode changed")
    }

    private var heightEditorPresets: [CGFloat] {
        let compatibility = shouldUseCompatibilityRefreshPolicy
        let builtIn: [CGFloat] = compatibility ? [1, 22, 42, 80, 120] : [0.1, 22, 44, 80, 120]
        let favorites = HeightProfileStore.favorites(isCompatibility: compatibility)
        let learned = SmartHeightLearningStore.preferredHeights(isCompatibility: compatibility, limit: 3)
        var values: [CGFloat] = []
        for value in favorites + learned + builtIn {
            let clamped = clampedHeight(value)
            guard !values.contains(where: { abs($0 - clamped) < 0.05 }) else { continue }
            values.append(clamped)
            if values.count >= 6 { break }
        }
        return values
    }

    private func presentPiPHeightEditor() {
        DiagnosticsRuntimeState.recordUserAction("打开自定义悬浮窗高度")
        if shouldUsePlayerLayerPiPCompatibility {
            // Warm only the neighborhood the user is likely to touch. Materializing all
            // 220 heights up front creates unnecessary CPU, memory pressure and file I/O.
            lastPlayerLayerPrefetchHeight = Int(clampedPiPHeight.rounded())
            PlaceholderVideoFactory.prefetchPlayerLayerBackingVideos(
                around: clampedPiPHeight,
                direction: 0,
                policy: SmartPerformanceGovernor.shared.snapshot
            )
        }
        let editor = PiPHeightEditorViewController(
            height: clampedPiPHeight,
            range: currentMinimumPiPHeight...currentGeometryMetrics.maximumHeight,
            step: currentPiPHeightStep,
            defaultHeight: currentDefaultPiPHeight,
            minimumHintText: shouldUsePlayerLayerPiPCompatibility
                ? L10n.text("兼容模式最低1pt；拖动时实时同步，松手后精确收敛到目标尺寸", "Compatibility mode: minimum 1 pt. Dragging updates live and release converges exactly to the selected size.")
                : L10n.text("标准模式最低0.1pt，调节精度为0.1pt", "Standard mode: minimum 0.1 pt, step 0.1 pt."),
            presetHeights: heightEditorPresets,
            favoriteHeights: HeightProfileStore.favorites(isCompatibility: shouldUseCompatibilityRefreshPolicy),
            onToggleFavorite: { [weak self] height in
                guard let self else { return false }
                return HeightProfileStore.toggleFavorite(height: self.clampedHeight(height), isCompatibility: self.shouldUseCompatibilityRefreshPolicy)
            },
            onSetDefault: { [weak self] height in
                guard let self else { return }
                HeightProfileStore.setDefault(height: self.clampedHeight(height), isCompatibility: self.shouldUseCompatibilityRefreshPolicy)
                self.updateHomeView(animated: true)
            },
            onChange: { [weak self] height in
                self?.previewPiPHeight(height)
            },
            onFinish: { [weak self] height in
                self?.commitPiPHeight(height)
            },
            onReset: { [weak self] in
                guard let self else { return }
                self.commitPiPHeight(self.currentDefaultPiPHeight)
            }
        )
        editor.configureAdaptivePageSheet(preferredHeightRatio: 0.52)
        present(editor, animated: true)
    }

    private func previewPiPHeight(_ height: CGFloat) {
        SmartPerformanceGovernor.shared.beginInteractiveBurst()
        isPreviewingPiPHeight = true
        pipHeight = clampedHeight(height)
        isCompactPiPStyle = abs(clampedPiPHeight - currentCompactPiPHeight) < 0.5
        updateAutoHiddenOverheadState(reason: "预览高度 \(formattedHeight(clampedPiPHeight))")

        if shouldUsePlayerLayerPiPCompatibility {
            // Keep source geometry immediate and prefetch only in the direction of travel.
            // Media work stays off-main; only the newest requested height may be applied.
            UIView.performWithoutAnimation {
                submitPiPGeometryIfNeeded(synchronousLayout: false)
            }
            let integralHeight = Int(clampedPiPHeight.rounded())
            let direction: Int
            if let previous = lastPlayerLayerPrefetchHeight {
                direction = integralHeight == previous ? 0 : (integralHeight > previous ? 1 : -1)
            } else {
                direction = 0
            }
            lastPlayerLayerPrefetchHeight = integralHeight
            PlaceholderVideoFactory.prefetchPlayerLayerBackingVideos(
                around: clampedPiPHeight,
                direction: direction,
                policy: SmartPerformanceGovernor.shared.snapshot
            )
            schedulePlayerLayerGeometryPreview(for: clampedPiPHeight)
            return
        }

        guard shouldPreviewPiPHeightLive else { return }
        UIView.performWithoutAnimation {
            // Slider changes can arrive at display cadence. Mirror the hide-animation fast
            // path and defer the one full Auto Layout convergence to commitPiPHeight().
            submitPiPGeometryIfNeeded(synchronousLayout: false)
            if textView != nil, shouldRenderClockMode {
                updateClockAppearance()
            }
        }
        if isPiPVisuallyHidden {
            configureRunningText()
        }
    }

    private func commitPiPHeight(_ height: CGFloat, persistPreference: Bool = true) {
        SmartPerformanceGovernor.shared.endInteractiveBurst()
        isPreviewingPiPHeight = false
        pipTasks.cancel(.playerLayerGeometryPreview)
        pendingPlayerLayerPreviewHeight = nil
        lastPlayerLayerPrefetchHeight = nil
        pipHeight = clampedHeight(height)
        isCompactPiPStyle = abs(clampedPiPHeight - currentCompactPiPHeight) < 0.5

        if remembersPiPHeight, persistPreference {
            saveCurrentPiPHeightPreference()
        }
        if persistPreference {
            SmartHeightLearningStore.record(height: clampedPiPHeight, isCompatibility: shouldUseCompatibilityRefreshPolicy)
        }
        if pipSourceView != nil {
            submitPiPGeometryIfNeeded(force: true)
        }
        if shouldUsePlayerLayerPiPCompatibility {
            // Prioritize the actual PiP geometry change before SwiftUI/state bookkeeping.
            // Compact bundled media makes the final item swap local without runtime H.264 encoding.
            lastPlayerLayerPreviewSubmissionAt = CACurrentMediaTime()
            requestPlayerLayerMedia(for: clampedPiPHeight, reason: "提交高度")
        }
        updateHomeView()
        if textView != nil {
            configureRunningText()
        }
        updateAutoHiddenOverheadState(reason: "提交高度 \(formattedHeight(clampedPiPHeight))")
        updateDiagnosticsPiPState()
        AppDebugLogger.log("PiP height committed: \(formattedHeight(clampedPiPHeight))")
        logPiPSurfaceDiagnostics("height committed")
    }

    private func schedulePlayerLayerGeometryPreview(for height: CGFloat) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        let requestedHeight = clampedHeight(height)
        pendingPlayerLayerPreviewHeight = requestedHeight

        let now = CACurrentMediaTime()
        let elapsed = now - lastPlayerLayerPreviewSubmissionAt
        let remaining = max(0, playerLayerPreviewSubmissionInterval - elapsed)

        // This is a throttle, not a debounce: continuous dragging keeps producing visible
        // geometry updates at up to 60 Hz instead of waiting for the finger to pause.
        if remaining <= 0.0005, !pipTasks.isScheduled(.playerLayerGeometryPreview) {
            pendingPlayerLayerPreviewHeight = nil
            lastPlayerLayerPreviewSubmissionAt = now
            requestPlayerLayerMedia(for: requestedHeight, reason: "滑杆实时预览")
            return
        }

        guard !pipTasks.isScheduled(.playerLayerGeometryPreview) else { return }
        pipTasks.schedule(.playerLayerGeometryPreview, after: remaining) { [weak self] in
            guard let self, self.shouldUsePlayerLayerPiPCompatibility else { return }
            guard let latestHeight = self.pendingPlayerLayerPreviewHeight else { return }
            self.pendingPlayerLayerPreviewHeight = nil
            self.lastPlayerLayerPreviewSubmissionAt = CACurrentMediaTime()
            guard abs(self.clampedPiPHeight - latestHeight) < 0.01 else { return }
            self.requestPlayerLayerMedia(for: latestHeight, reason: "滑杆实时预览")
        }
    }

    private func requestPlayerLayerMedia(for height: CGFloat, reason: String) {
        guard shouldUsePlayerLayerPiPCompatibility else { return }
        guard let playerLayer, let player = playerLayer.player else { return }

        let requestedHeight = clampedHeight(height)
        // Every slider event advances the generation, even when the requested media is
        // already current. That invalidates an older in-flight completion and prevents a
        // late preview from snapping the PiP back after the user reverses direction.
        playerLayerMediaRequestGeneration &+= 1
        let generation = playerLayerMediaRequestGeneration
        SpeedPerformanceLab.recordResizeRequest(generation: generation)

        // Avoid rebuilding the same AVPlayerItem when repeated slider callbacks snap to
        // the same integer-point height. A committed height also closes the temporary
        // slider burst cache so the normal 8-file LRU policy resumes immediately.
        if let targetURL = PlaceholderVideoFactory.resolvedPlayerLayerBackingVideoURL(forPointHeight: requestedHeight),
           let currentURL = (player.currentItem?.asset as? AVURLAsset)?.url,
           currentURL == targetURL {
            if !isPreviewingPiPHeight, !targetURL.path.contains("/CompatibilityMedia/") {
                GeneratedPiPVideoCache.trim(excluding: [targetURL])
            }
            return
        }

        PlaceholderVideoFactory.preparePlayerLayerBackingVideo(
            forPointHeight: requestedHeight,
            requestGeneration: generation
        ) { [weak self, weak player] url in
            let apply = { [weak self, weak player] in
                guard let self, let player else { return }
                guard self.shouldUsePlayerLayerPiPCompatibility else { return }

                // Never make the system PiP chase obsolete slider positions. Older decode
                // work may finish and populate cache, but only the latest request whose height
                // still matches the UI is allowed to touch AVPlayer.
                guard generation == self.playerLayerMediaRequestGeneration else {
                    SpeedPerformanceLab.recordStaleDrop()
                    return
                }
                guard abs(self.clampedPiPHeight - requestedHeight) < 0.01 else {
                    SpeedPerformanceLab.recordStaleDrop()
                    return
                }

                let item = AVPlayerItem(asset: PlaceholderVideoFactory.cachedAsset(for: url))
                self.observeLooping(for: item)
                self.configureBackingPlayerForPiP(player)
                self.observePlayerLayerPipelineHealth(for: player, item: item)
                player.replaceCurrentItem(with: item)
                if self.shouldKeepPiPPlaybackAlive {
                    self.updateBackingPlayerPlaybackForCurrentMode()
                } else {
                    player.pause()
                }

                // While the editor is being dragged, keep the tiny materialized media bank
                // available so nearby point heights remain instant. Commit/end restores the
                // bounded generated-media cache and bounds persistent disk usage.
                if !url.path.contains("/CompatibilityMedia/"), !self.isPreviewingPiPHeight {
                    GeneratedPiPVideoCache.trim(excluding: [url])
                }
                SpeedPerformanceLab.recordMediaApply(generation: generation)
                self.updateHomeView()
                AppDebugLogger.log("PlayerLayer geometry media applied (\(reason)): \(self.formattedHeight(requestedHeight))")
            }

            if Thread.isMainThread {
                apply()
            } else {
                DispatchQueue.main.async(execute: apply)
            }
        }
    }

    private func formattedHeight(_ height: CGFloat) -> String {
        let roundedHeight = (height * 10).rounded() / 10
        if roundedHeight.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(roundedHeight))pt"
        }
        return String(format: "%.1fpt", roundedHeight)
    }

    private func togglePiPStyle() {
        SmartPerformanceGovernor.shared.beginInteractiveBurst()
        SmartPerformanceGovernor.shared.endInteractiveBurst(after: 0.45)
        DiagnosticsRuntimeState.recordUserAction("修改悬浮窗样式")
        // Derive from requested geometry every tap instead of trusting stale UI state.
        // Compatibility mode uses 22pt <-> 120pt. Both hot assets stay as raw bundled .mov files, so
        // the media swap starts in the same turn as the tap rather than waiting on encoding.
        let compactHeight = currentCompactPiPHeight
        let isCurrentlyCompact = abs(clampedPiPHeight - compactHeight) < 0.5
        let nextHeight = isCurrentlyCompact ? defaultPiPHeight : compactHeight
        commitPiPHeight(nextHeight)
    }

    private func showMessage(_ message: String) {
        let alert = UIAlertController(title: message, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.ok, style: .default))
        present(alert, animated: true)
    }

    private func prepareSourceLayerForPiP() {
        view.layoutIfNeeded()
        centerPlayerLayer()
        let surfaceAlpha: Float = isPiPVisuallyHidden ? 0.01 : 1
        playerLayer?.opacity = shouldUsePlayerLayerPiPCompatibility ? surfaceAlpha : 0
    }

    private func centerPlayerLayer() {
        guard let playerLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = centeredPreviewFrame()
        playerLayer.zPosition = -1
        playerLayer.removeAllAnimations()
        CATransaction.commit()
    }

    private func centeredPreviewFrame() -> CGRect {
        let bounds = view.bounds.isEmpty ? AppDisplayContext.bounds : view.bounds
        return PiPGeometryController.shared.centeredFrame(
            size: currentPiPSize,
            in: bounds,
            safeAreaInsets: view.safeAreaInsets
        )
    }

    private func activateLockScreenAudioBoostIfNeeded(reason: String) {
        guard currentKeepAlivePolicy.usesAudioWhileLocked else { return }
        guard !shouldUsePlayerLayerPiPCompatibility else {
            AppDebugLogger.log("锁屏音频增强未介入PlayerLayer，保持原视频管线：\(reason)")
            return
        }
        guard shouldKeepPiPPlaybackAlive else {
            AppDebugLogger.log("锁屏音频增强未启动：当前无活动PiP，原因=\(reason)")
            return
        }
        guard !isLockScreenAudioBoostActive else { return }

        isLockScreenAudioBoostActive = true
        keepPlaybackAlive()
        updateDiagnosticsPiPState()
        ProcessTerminationDiagnostics.recordCheckpoint(reason: "锁屏音频增强启动")
        AppDebugLogger.log("锁屏音频增强-BETA启动：\(reason)")
    }

    private func deactivateLockScreenAudioBoostIfNeeded(reason: String) {
        guard isLockScreenAudioBoostActive else { return }
        guard UIApplication.shared.isProtectedDataAvailable else {
            AppDebugLogger.log("锁屏音频增强仍保持：设备尚未解锁，原因=\(reason)")
            return
        }

        isLockScreenAudioBoostActive = false
        if shouldKeepPiPPlaybackAlive {
            keepPlaybackAlive()
        } else {
            BackgroundTaskManager.shared.forceStopAndDeactivate()
            PowerUsageLogger.markKeepAliveStop()
        }
        updateDiagnosticsPiPState()
        ProcessTerminationDiagnostics.recordCheckpoint(reason: "锁屏音频增强结束")
        AppDebugLogger.log("锁屏音频增强-BETA结束，已恢复仅PiP：\(reason)")
    }

    private func resetLockScreenAudioBoost(reason: String) {
        guard isLockScreenAudioBoostActive else { return }
        isLockScreenAudioBoostActive = false
        AppDebugLogger.log("锁屏音频增强状态重置：\(reason)")
    }

    @objc private func handleProtectedDataWillBecomeUnavailable() {
        AppDebugLogger.log("收到设备锁定事件：policy=\(currentKeepAlivePolicy.diagnosticsName)，PiP=\(shouldKeepPiPPlaybackAlive)")
        activateLockScreenAudioBoostIfNeeded(reason: "protectedDataWillBecomeUnavailable")
    }

    @objc private func handleProtectedDataDidBecomeAvailable() {
        AppDebugLogger.log("收到设备解锁事件：policy=\(currentKeepAlivePolicy.diagnosticsName)")
        deactivateLockScreenAudioBoostIfNeeded(reason: "protectedDataDidBecomeAvailable")
    }

    @objc private func handleEnterForeground() {
        if shouldResignForegroundAfterPiPClose {
            DiagnosticsRuntimeState.updateAppState("PiP关闭后阻止回前台")
            AppDebugLogger.log("Suppress foreground restore after PiP close: willEnterForeground")
            resignForegroundAfterPiPCloseIfNeeded(reason: "即将回前台")
            return
        }
        restoreForegroundWindowsHiddenForPiPCloseIfNeeded()
        DiagnosticsRuntimeState.updateAppState("即将回前台")
        recoverStalePiPTransitionIfNeeded(reason: "进入前台")
        validateOwnPiPState(reason: "进入前台")
        if UIApplication.shared.isProtectedDataAvailable {
            deactivateLockScreenAudioBoostIfNeeded(reason: "App回到前台")
        }
        updateDiagnosticsPiPState()
        PowerUsageLogger.markForegroundStart()
        AppDebugLogger.log("Enter foreground, keepAlive=\(shouldKeepPiPPlaybackAlive), policy=\(currentKeepAlivePolicy.diagnosticsName)")
        if shouldKeepPiPPlaybackAlive {
            pipRuntimeDuration = pipRuntimeStartedAt.map { max(0, Date().timeIntervalSince($0)) } ?? pipRuntimeDuration
            updateHomeView()
        }
        if shouldRenderClockMode {
            startClockTimerIfNeeded()
        } else if isScrollingEnabled {
            startDisplayLinks()
        }
        updateAutoHiddenOverheadState(reason: "进入前台")
        if shouldKeepPiPPlaybackAlive {
            KeepAliveLogger.markEnterForeground()
        }
        endBackgroundTask()
        BackgroundTaskManager.shared.stopPlay()
        PowerUsageLogger.markKeepAliveStop()
        pauseBackingPlayerIfIdle()
        updateDisplaySleepDiagnostics(reason: "进入前台", shouldLog: true)
        KeepAliveNotificationTester.presentPendingLocalNotificationAlertIfNeeded(from: self)
    }

    @objc private func handleDidBecomeActive() {
        if UIApplication.shared.isProtectedDataAvailable {
            deactivateLockScreenAudioBoostIfNeeded(reason: "App已活跃")
        }
        LatencyExperimentController.shared.reconcile()
        updateHomeView()
        guard shouldResignForegroundAfterPiPClose else { return }
        DiagnosticsRuntimeState.updateAppState("PiP关闭后阻止激活")
        AppDebugLogger.log("Suppress foreground restore after PiP close: didBecomeActive")
        resignForegroundAfterPiPCloseIfNeeded(reason: "已激活")
    }

    @objc private func handleEnterBackground() {
        cancelPiPHeightAnimation(settleCurrentGeometry: true)
        // The UI-only elapsed-time ticker must never compete with the global high-refresh
        // keep-alive path while the app is backgrounded. Duration is recomputed on return.
        if shouldResignForegroundAfterPiPClose {
            shouldResignForegroundAfterPiPClose = false
        }
        DiagnosticsRuntimeState.updateAppState("后台")
        if currentKeepAlivePolicy.usesAudioWhileLocked {
            if UIApplication.shared.isProtectedDataAvailable {
                AppDebugLogger.log("锁屏音频增强-BETA等待系统锁屏事件，当前保持仅PiP")
            } else {
                activateLockScreenAudioBoostIfNeeded(reason: "进入后台时设备已锁定")
            }
        }
        recoverStalePiPTransitionIfNeeded(reason: "进入后台")
        updateDiagnosticsPiPState()
        PowerUsageLogger.markBackgroundStart()
        AppDebugLogger.log("Enter background, keepAlive=\(shouldKeepPiPPlaybackAlive), policy=\(currentKeepAlivePolicy.diagnosticsName)")
        guard shouldKeepPiPPlaybackAlive else {
            BackgroundTaskManager.shared.stopPlay()
            PowerUsageLogger.markKeepAliveStop()
            pauseBackingPlayerIfIdle()
            endBackgroundTask()
            KeepAliveNotificationTester.cancelBackgroundInterruptionProbe(reason: "进入后台未保活")
            updateDisplaySleepDiagnostics(reason: "进入后台未保活", shouldLog: true)
            return
        }
        if isPiPTransitioning, pipTransitionExpectedActive == true {
            beginBackgroundTaskIfNeeded()
        } else {
            // AVKit owns stable PiP background execution. Remove any stale startup
            // assertion rather than extending it for the whole PiP session.
            endBackgroundTask()
        }
        KeepAliveLogger.markEnterBackground(mode: currentKeepAlivePolicy.diagnosticsName)
        keepPlaybackAlive()
        if shouldRenderClockMode {
            stopDisplayLinks()
            startClockTimerIfNeeded()
        } else if isScrollingEnabled {
            startDisplayLinks()
        }
        updateAutoHiddenOverheadState(reason: "进入后台")
        updateDisplaySleepDiagnostics(reason: "进入后台保活", shouldLog: true)
    }

    @objc private func handleKeepAliveModeDidChange() {
        if currentKeepAlivePolicy.usesAudioWhileLocked,
           !UIApplication.shared.isProtectedDataAvailable,
           shouldKeepPiPPlaybackAlive,
           !shouldUsePlayerLayerPiPCompatibility {
            isLockScreenAudioBoostActive = true
        } else {
            isLockScreenAudioBoostActive = false
        }
        updateDiagnosticsPiPState()
        AppDebugLogger.log("KeepAlive mode changed, policy=\(currentKeepAlivePolicy.diagnosticsName), PiPOnly=\(shouldUsePiPOnlyKeepAlive), active=\(shouldKeepPiPPlaybackAlive)")
        updateContinuousDiagnosticsForStableVideoCall(reason: "保活方案切换")
        updateHomeView()
        if shouldUsePiPOnlyKeepAlive {
            BackgroundTaskManager.shared.forceStopAndDeactivate()
            PowerUsageLogger.markKeepAliveStop()
            releaseMediaAudioSessionForPiPOnly(reason: "保活方案切换为低功耗")
        }
        guard shouldKeepPiPPlaybackAlive else { return }
        keepPlaybackAlive()
        KeepAliveLogger.markPiPStarted(mode: currentKeepAlivePolicy.diagnosticsName)
        updateDisplaySleepDiagnostics(reason: "保活方案切换", shouldLog: true)
    }

    @objc private func handleLanguageDidChange() {
        updateHomeView()
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else {
            return
        }

        switch type {
        case .began:
            AppDebugLogger.log("Audio interruption began")
            KeepAliveNotificationTester.markAudioInterruptionBegan()
            BackgroundTaskManager.shared.stopPlay()
            PowerUsageLogger.markKeepAliveStop()
        case .ended:
            KeepAliveNotificationTester.markAudioInterruptionEnded()
            guard shouldKeepPiPPlaybackAlive else { return }
            AppDebugLogger.log("Audio interruption ended, resume keepAlive")
            keepPlaybackAlive()
        @unknown default:
            break
        }
    }

    @objc private func handleAudioRouteChange(_ notification: Notification) {
        AppDebugLogger.log("Audio route changed: \(currentAudioRouteDescription), external=\(hasExternalAudioRoute)")
        guard shouldKeepPiPPlaybackAlive else { return }
        guard !shouldUsePiPOnlyKeepAlive else { return }
        keepPlaybackAlive()
    }

    private var hasExternalAudioRoute: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
            switch output.portType {
            case .airPlay, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                return true
            default:
                return false
            }
        }
    }

    private var currentAudioRouteDescription: String {
        AVAudioSession.sharedInstance().currentRoute.outputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ",")
    }

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        pipLifecycle.willStart(reason: "AVPictureInPictureController delegate")
        AppDebugLogger.log("画中画初始化后，应用窗口数：\(allApplicationWindows().count)")
        updateDiagnosticsPiPState()
        AppDebugLogger.log("PiP will start")
        prepareCustomViewForPiPStart()
        showPiPContentForOpening()
        scheduleLegacyCustomViewAttachRetries()
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        pipLifecycle.didStart()
        pipTasks.cancel(.startRetry)
        pipTasks.cancel(.startTimeout)
        wantsPiPActive = true
        updatePiPAutomaticStartPolicy()
        prepareCustomViewForPiPStart()
        configureRunningText()
        showPiPContentForOpening()
        scheduleLegacyCustomViewAttachRetries()
        finishPiPTransition()
        hasPrimedPlayerLayerPiPStart = false
        isOwnPiPConfirmedActive = true
        isPiPActiveForUI = true
        if currentKeepAlivePolicy.usesAudioWhileLocked,
           !UIApplication.shared.isProtectedDataAvailable,
           !shouldUsePlayerLayerPiPCompatibility {
            isLockScreenAudioBoostActive = true
            AppDebugLogger.log("PiP启动时设备已锁定，锁屏音频增强-BETA立即生效")
        }
        beginPiPRuntimeSession()
        pipLifecycle.setSuspendedAtSide(pictureInPictureController.isPictureInPictureSuspended)
        scheduleAutoHideAfterStablePiPStartIfNeeded(reason: "PiP启动稳定窗口")
        updateContinuousDiagnosticsForStableVideoCall(reason: "PiP启动完成")
        startDisplayLinks()
        settlePlayerLayerPiPAfterStart()
        if !shouldUsePlayerLayerPiPCompatibility {
            keepPlaybackAlive()
        }
        updateAutoHiddenOverheadState(reason: "PiP启动完成")
        PowerUsageLogger.markPiPStart()
        KeepAliveLogger.markPiPStarted(mode: currentKeepAlivePolicy.diagnosticsName)
        updateDiagnosticsPiPState()
        updateDisplaySleepDiagnostics(reason: "PiP启动完成", shouldLog: true)
        ProcessTerminationDiagnostics.recordCheckpoint(reason: "PiP启动完成")
        AppDebugLogger.log("PiP did start")
        AppDebugLogger.log("画中画弹出后，应用窗口数：\(allApplicationWindows().count)")
    }

    private func scheduleSystemPiPDirectCloseGestureRetries(reason: String) {
        directCloseGestureRetryGeneration &+= 1
        let generation = directCloseGestureRetryGeneration
        let delays: [TimeInterval] = [0, 0.08, 0.2, 0.5, 1.0]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard
                    let self,
                    self.directCloseGestureRetryGeneration == generation,
                    self.pipController?.isPictureInPictureActive == true
                else { return }
                self.installDirectCloseGestureForSystemPiPControls(reason: "\(reason) retry \(String(format: "%.2f", delay))")
            }
        }
    }

    private func scheduleLegacyCustomViewAttachRetries() {
        guard shouldUsePlayerLayerPiPCompatibility, shouldAttachCustomViewInPlayerLayerPiP else { return }
        legacyCustomViewAttachRetryGeneration &+= 1
        let generation = legacyCustomViewAttachRetryGeneration
        let delays: [TimeInterval] = [0, 0.08, 0.2, 0.5, 1.0]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard
                    let self,
                    self.legacyCustomViewAttachRetryGeneration == generation,
                    self.shouldUsePlayerLayerPiPCompatibility,
                    self.pipController?.isPictureInPictureActive == true
                else {
                    return
                }
                _ = self.attachCustomViewToPiPWindowIfAvailable(reason: "did start retry \(String(format: "%.2f", delay))")
                self.showPiPContentForOpening()
            }
        }
    }

    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        pipLifecycle.willStop(reason: isStoppingPiP ? "app requested" : "system/user requested")
        pipExpectedActiveBeforeStop = wantsPiPActive
            && !isStoppingPiP
            && !isClosingPiPFromCustomContentTap
            && pipTransitionExpectedActive != false
        removeDirectCloseGestureForSystemPiPControls()
        cancelDelayedPiPHideCountdown(reason: "悬浮窗即将停止")
        pipTasks.cancelAll()
        pipTasks.cancel(.playerLayerAudioRelease)
        hasPrimedPlayerLayerPiPStart = false
        playerLayerPiPStartAudioMode = .defaultStartupMode
        wantsPiPActive = false
        updatePiPAutomaticStartPolicy()
        beginPiPTransition(expectedActive: false, reason: "will stop")
        isPiPActiveForUI = false
        stopDisplayLinks()
        stopClockTimer()
        updateDiagnosticsPiPState()
        updateDisplaySleepDiagnostics(reason: "PiP即将停止", shouldLog: true)
        AppDebugLogger.log("PiP will stop")
        if shouldUseVideoCallOffscreenCloseAnimation {
            movePiPSourceViewOffscreenForClosing()
        } else {
            hidePiPContentForClosing()
            preparePiPVisualSurfacesForClosing()
            movePiPSourceViewOffscreenForClosing()
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        hidePiPContentForClosing()
        // Capture the pre-stop intent before collapsing lifecycle state. This preserves
        // the distinction between a requested stop and an unexpected AVKit eviction.
        let expectedActiveBeforeStop = pipExpectedActiveBeforeStop ?? (
            wantsPiPActive
                && !isStoppingPiP
                && !isClosingPiPFromCustomContentTap
                && pipTransitionExpectedActive != false
        )
        pipLifecycle.didStop()
        pipExpectedActiveBeforeStop = nil
        // willStop 中已捕获“是否为用户主动停止”，这里仅负责收敛最终状态。
        let wasExpectedStop = !expectedActiveBeforeStop || didRecoverStalePiPStop
        let stoppedMode = currentKeepAlivePolicy.diagnosticsName
        detachLegacyCustomViewIfNeeded()
        restorePiPVisualSurfaces()
        isOwnPiPConfirmedActive = false
        isPiPActiveForUI = false
        isStoppingPiP = false
        let shouldSuppressStopNotification = !wasExpectedStop
            && KeepAliveNotificationTester.shouldSuppressPiPStoppedNotification(
                reason: "悬浮窗异常停止",
                allowWhileLocked: true
            )
        finishPiPTransition()
        finishPiPRuntimeSession()
        didRecoverStalePiPStop = false
        hasPrimedPlayerLayerPiPStart = false
        isLegacyPlayerLayerFallbackActive = false
        playerLayerPiPStartAudioMode = .defaultStartupMode
        wantsPiPActive = false
        updatePiPAutomaticStartPolicy()
        updateContinuousDiagnosticsForStableVideoCall(reason: "PiP停止完成")
        resetLockScreenAudioBoost(reason: "PiP停止完成")
        BackgroundTaskManager.shared.stopPlay()
        pauseBackingPlayerIfIdle()
        restorePlayerLayerDefaultHeightAfterStopIfNeeded(reason: "PiP停止完成")
        releaseTransientPlayerLayerPiPAudioSession(reason: "PiP停止完成")
        PowerUsageLogger.markPiPStop()
        PowerUsageLogger.markKeepAliveStop()
        KeepAliveLogger.markPiPStopped(reason: "PiP did stop")
        if !wasExpectedStop, !shouldSuppressStopNotification {
            KeepAliveNotificationTester.schedulePiPStoppedNotification(mode: stoppedMode, reason: "悬浮窗异常停止")
        }
        endBackgroundTask()
        updateDisplaySleepDiagnostics(reason: "PiP停止完成", shouldLog: true)
        updateDiagnosticsPiPState()
        ProcessTerminationDiagnostics.recordCheckpoint(
            reason: wasExpectedStop ? "PiP正常停止" : "PiP异常停止"
        )
        AppDebugLogger.log("PiP did stop")
        resignForegroundAfterPiPCloseIfNeeded(reason: "PiP停止完成")
        isClosingPiPFromCustomContentTap = false
        if let pendingRoute = pendingPiPEngineRouteAfterStop {
            pendingPiPEngineRouteAfterStop = nil
            DispatchQueue.main.async { [weak self] in
                self?.applyPiPEngineRoute(pendingRoute)
            }
        }

    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        if isClosingPiPFromCustomContentTap || isStoppingPiP || pipTransitionExpectedActive == false {
            DiagnosticsRuntimeState.recordUserAction("自定义悬浮窗关闭PiP")
            AppDebugLogger.log("PiP restore UI requested during expected close; keep app out of foreground")
            wantsPiPActive = false
            isPiPActiveForUI = false
            shouldResignForegroundAfterPiPClose = false
            restoreForegroundWindowsHiddenForPiPCloseIfNeeded()
            updatePiPAutomaticStartPolicy()
            completionHandler(false)
            return
        }

        DiagnosticsRuntimeState.recordUserAction("系统悬浮窗控件还原App")
        AppDebugLogger.log("PiP restore UI requested by system control, suppress app foreground restore")
        wantsPiPActive = false
        isPiPActiveForUI = false
        updatePiPAutomaticStartPolicy()
        shouldResignForegroundAfterPiPClose = true
        resignForegroundAfterPiPCloseIfNeeded(reason: "系统请求恢复UI")
        completionHandler(false)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        pipLifecycle.didFail(error)
        AppDebugLogger.log("PiP failed to start: \(error.localizedDescription)")
        if activateAutoCompatibilityFallbackIfNeeded(reason: error.localizedDescription) { return }
        resetPiPStartStateAfterFailure()
        releaseTransientPlayerLayerPiPAudioSession(reason: "PiP启动失败")
        print(error)
    }

}

private extension UIColor {
    var debugRGBAString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "unresolved"
        }
        return String(format: "%.2f,%.2f,%.2f,%.2f", red, green, blue, alpha)
    }
}

private final class PiPHeightEditorViewController: UIViewController {
    private let range: ClosedRange<CGFloat>
    private let step: CGFloat
    private let defaultHeight: CGFloat
    private let minimumHintText: String
    private let presetHeights: [CGFloat]
    private let favoriteHeights: [CGFloat]
    private let onToggleFavorite: (CGFloat) -> Bool
    private let onSetDefault: (CGFloat) -> Void
    private let onChange: (CGFloat) -> Void
    private let onFinish: (CGFloat) -> Void
    private let onReset: () -> Void

    private let inputField = UITextField()
    private let slider = UISlider()
    private let initialHeight: CGFloat
    private var isUpdatingInputFieldProgrammatically = false
    private var inputFieldWidthConstraint: NSLayoutConstraint?

    init(
        height: CGFloat,
        range: ClosedRange<CGFloat>,
        step: CGFloat,
        defaultHeight: CGFloat,
        minimumHintText: String,
        presetHeights: [CGFloat],
        favoriteHeights: [CGFloat],
        onToggleFavorite: @escaping (CGFloat) -> Bool,
        onSetDefault: @escaping (CGFloat) -> Void,
        onChange: @escaping (CGFloat) -> Void,
        onFinish: @escaping (CGFloat) -> Void,
        onReset: @escaping () -> Void
    ) {
        self.range = range
        self.step = step
        self.defaultHeight = min(max(defaultHeight, range.lowerBound), range.upperBound)
        self.minimumHintText = minimumHintText
        self.presetHeights = presetHeights
        self.favoriteHeights = favoriteHeights
        self.onToggleFavorite = onToggleFavorite
        self.onSetDefault = onSetDefault
        self.onChange = onChange
        self.onFinish = onFinish
        self.onReset = onReset
        self.initialHeight = height
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let contentView = applyLegacyGlassSheetBackground()

        let titleLabel = UILabel()
        titleLabel.text = L10n.text("自定义悬浮窗高度", "Custom PiP Height")
        titleLabel.font = .systemFont(ofSize: 24, weight: .black)
        titleLabel.textColor = .label

        inputField.keyboardType = .decimalPad
        inputField.textAlignment = .right
        inputField.font = .monospacedDigitSystemFont(ofSize: 18, weight: .black)
        inputField.textColor = .label
        inputField.tintColor = .systemBlue
        inputField.placeholder = formattedHeightValue(defaultHeight)
        inputField.borderStyle = .none
        inputField.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.82)
        inputField.clearButtonMode = .whileEditing
        inputField.layer.cornerRadius = 12
        inputField.layer.cornerCurve = .continuous
        inputField.layer.borderWidth = 1
        inputField.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.28).cgColor
        inputField.clipsToBounds = true
        inputField.addTarget(self, action: #selector(handleHeightInputChange), for: .editingChanged)
        inputField.addTarget(self, action: #selector(handleHeightInputBegin), for: .editingDidBegin)
        inputField.addTarget(self, action: #selector(handleHeightInputEnd), for: [.editingDidEnd, .editingDidEndOnExit])
        inputField.inputAccessoryView = makeInputAccessoryToolbar()
        let inputLeftPadding = UIView(frame: CGRect(x: 0, y: 0, width: 4, height: 1))
        inputField.leftView = inputLeftPadding
        inputField.leftViewMode = .always

        let unitLabel = UILabel()
        unitLabel.text = "pt"
        unitLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .black)
        unitLabel.textColor = .secondaryLabel
        unitLabel.sizeToFit()
        let unitContainer = UIView(frame: CGRect(x: 0, y: 0, width: 26, height: 24))
        unitContainer.addSubview(unitLabel)
        unitLabel.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        inputField.rightView = unitContainer
        inputField.rightViewMode = .always
        inputField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        inputField.translatesAutoresizingMaskIntoConstraints = false
        let inputWidth = inputField.widthAnchor.constraint(
            equalToConstant: adaptiveInputFieldWidth(for: formattedHeightValue(defaultHeight))
        )
        inputFieldWidthConstraint = inputWidth
        NSLayoutConstraint.activate([
            inputWidth,
            inputField.heightAnchor.constraint(equalToConstant: 36)
        ])

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, inputField])
        headerStack.axis = .horizontal
        headerStack.alignment = .firstBaseline
        headerStack.spacing = 12

        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.value = Float(min(max(initialHeight, range.lowerBound), range.upperBound))
        slider.minimumTrackTintColor = .systemBlue
        slider.maximumTrackTintColor = .tertiaryLabel
        slider.thumbTintColor = .systemBlue
        slider.isContinuous = true
        slider.addTarget(self, action: #selector(handleSliderChange), for: .valueChanged)
        slider.addTarget(self, action: #selector(handleSliderFinish), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let sliderContainer = makeSliderGlassContainer()
        sliderContainer.contentView.addSubview(slider)
        slider.translatesAutoresizingMaskIntoConstraints = false
        sliderContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: sliderContainer.contentView.leadingAnchor, constant: 18),
            slider.trailingAnchor.constraint(equalTo: sliderContainer.contentView.trailingAnchor, constant: -18),
            slider.centerYAnchor.constraint(equalTo: sliderContainer.contentView.centerYAnchor),
            sliderContainer.heightAnchor.constraint(equalToConstant: 72)
        ])

        let presetTitle = UILabel()
        presetTitle.text = L10n.text("智能预设", "Smart presets")
        presetTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        presetTitle.textColor = .secondaryLabel

        let presetStack = UIStackView()
        presetStack.axis = .horizontal
        presetStack.alignment = .fill
        presetStack.distribution = .fillEqually
        presetStack.spacing = 8
        for height in presetHeights.prefix(6) {
            let button = UIButton(type: .system)
            let isFavorite = favoriteHeights.contains(where: { abs($0 - height) < 0.05 })
            button.setTitle("\(isFavorite ? "★ " : "")\(formattedHeightValue(height))", for: .normal)
            button.titleLabel?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            button.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.72)
            button.layer.cornerRadius = 11
            button.layer.cornerCurve = .continuous
            button.tag = Int((height * 10).rounded())
            button.addTarget(self, action: #selector(handlePresetTap(_:)), for: .touchUpInside)
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handlePresetLongPress(_:)))
            button.addGestureRecognizer(longPress)
            presetStack.addArrangedSubview(button)
        }
        presetStack.heightAnchor.constraint(equalToConstant: 38).isActive = true

        let presetContainer = UIStackView(arrangedSubviews: [presetTitle, presetStack])
        presetContainer.axis = .vertical
        presetContainer.spacing = 8

        let hintLabel = UILabel()
        hintLabel.text = [
            L10n.text("滑动时会实时调整已打开悬浮窗的高度", "Drag to adjust the active floating window height in real time."),
            minimumHintText,
            L10n.text("可根据自身喜好调节侧边吸附框大小", "Use it to tune the side dock size.")
        ].joined(separator: "\n")
        hintLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        hintLabel.textColor = .secondaryLabel
        hintLabel.numberOfLines = 0

        let favoriteButton = makeGlassButton(title: L10n.text("☆ 收藏当前尺寸", "☆ Favorite current"), isPrimary: false)
        favoriteButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        favoriteButton.addTarget(self, action: #selector(handleFavoriteCurrent(_:)), for: .touchUpInside)

        let defaultText = formattedHeightValue(defaultHeight)
        let resetButton = makeGlassButton(
            title: L10n.text("恢复默认值 \(defaultText)pt", "Reset to \(defaultText) pt"),
            isPrimary: false
        )
        resetButton.addTarget(self, action: #selector(handleReset), for: .touchUpInside)

        let doneButton = makeGlassButton(title: L10n.text("完成", "Done"), isPrimary: true)
        doneButton.addTarget(self, action: #selector(handleDone), for: .touchUpInside)

        let buttonStack = UIStackView(arrangedSubviews: [resetButton, doneButton])
        buttonStack.axis = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 12
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.heightAnchor.constraint(equalToConstant: 52).isActive = true

        let stackView = UIStackView(arrangedSubviews: [headerStack, sliderContainer, presetContainer, favoriteButton, hintLabel, buttonStack])
        favoriteButton.heightAnchor.constraint(equalToConstant: 42).isActive = true
        stackView.axis = .vertical
        stackView.spacing = 16
        contentView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stackView.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 28)
        ])

        updateValueLabel()
        updateInputField()
    }

    private func makeSliderGlassContainer() -> UIVisualEffectView {
        let effect = UIGlassEffect(style: .regular)
        effect.isInteractive = true
        effect.tintColor = UIColor.systemBlue.withAlphaComponent(0.08)
        let effectView = UIVisualEffectView(effect: effect)

        effectView.layer.cornerRadius = 24
        effectView.layer.cornerCurve = .continuous
        effectView.clipsToBounds = true
        effectView.contentView.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.28)
        effectView.layer.borderWidth = 1
        effectView.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
        return effectView
    }

    private func makeGlassButton(title: String, isPrimary: Bool) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: isPrimary ? .black : .bold)
        button.tintColor = isPrimary ? .white : .systemBlue
        button.backgroundColor = isPrimary
            ? UIColor.systemBlue.withAlphaComponent(0.88)
            : UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.74)
        button.layer.cornerRadius = 18
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1
        button.layer.borderColor = (isPrimary
            ? UIColor.white.withAlphaComponent(0.32)
            : UIColor.black.withAlphaComponent(0.46)
        ).cgColor
        button.clipsToBounds = true
        return button
    }

    private func makeInputAccessoryToolbar() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneItem = UIBarButtonItem(
            title: L10n.text("完成", "Done"),
            style: .prominent,
            target: self,
            action: #selector(handleInputAccessoryDone)
        )
        toolbar.items = [flexibleSpace, doneItem]
        return toolbar
    }

    @objc private func handleSliderChange() {
        syncSliderToCurrentHeight(animated: false)
        updateValueLabel()
        updateInputField()
        onChange(currentHeight)
    }

    @objc private func handleSliderFinish() {
        syncSliderToCurrentHeight(animated: true)
        updateValueLabel()
        updateInputField()
        onFinish(currentHeight)
    }

    @objc private func handleHeightInputBegin() {
        updateInputFieldAppearance(isEditing: true)
    }

    @objc private func handleHeightInputChange() {
        updateInputFieldWidth(for: inputField.text ?? "44")
        guard !isUpdatingInputFieldProgrammatically, let parsedHeight = parsedInputHeight else { return }
        applyInputHeight(parsedHeight, shouldCommit: false)
    }

    @objc private func handleHeightInputEnd() {
        updateInputFieldAppearance(isEditing: false)
        guard let parsedHeight = parsedInputHeight else {
            updateInputField()
            return
        }
        applyInputHeight(parsedHeight, shouldCommit: true)
    }

    @objc private func handleInputAccessoryDone() {
        handleHeightInputEnd()
        inputField.resignFirstResponder()
    }

    @objc private func handlePresetTap(_ sender: UIButton) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let value = CGFloat(sender.tag) / 10.0
        let snapped = snappedClampedHeight(value)
        slider.setValue(Float(snapped), animated: true)
        updateValueLabel()
        updateInputField()
        onChange(currentHeight)
        onFinish(currentHeight)
    }

    @objc private func handleFavoriteCurrent(_ sender: UIButton) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let isFavorite = onToggleFavorite(currentHeight)
        sender.setTitle(
            isFavorite ? L10n.text("★ 已收藏", "★ Favorited") : L10n.text("☆ 收藏当前尺寸", "☆ Favorite current"),
            for: .normal
        )
    }

    @objc private func handlePresetLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let button = gesture.view as? UIButton else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let value = snappedClampedHeight(CGFloat(button.tag) / 10.0)
        onSetDefault(value)
        button.setTitle("✓ \(formattedHeightValue(value))", for: .normal)
    }

    @objc private func handleReset() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        slider.setValue(Float(defaultHeight), animated: true)
        updateValueLabel()
        updateInputField()
        onReset()
    }

    @objc private func handleDone() {
        if inputField.isFirstResponder {
            if let parsedHeight = parsedInputHeight {
                applyInputHeight(parsedHeight, shouldCommit: false)
                updateInputField()
            } else {
                updateInputField()
            }
            inputField.resignFirstResponder()
        }
        onFinish(currentHeight)
        dismiss(animated: true)
    }

    private var currentHeight: CGFloat {
        let rawHeight = CGFloat(slider.value)
        let snappedHeight = (rawHeight / step).rounded() * step
        return min(max(snappedHeight, range.lowerBound), range.upperBound)
    }

    private func syncSliderToCurrentHeight(animated: Bool) {
        let snappedValue = Float(currentHeight)
        guard abs(slider.value - snappedValue) > 0.0001 else { return }
        slider.setValue(snappedValue, animated: animated)
    }

    private var parsedInputHeight: CGFloat? {
        let text = (inputField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "pt", with: "", options: .caseInsensitive)
        guard !text.isEmpty, let value = Double(text) else { return nil }
        return CGFloat(value)
    }

    private func applyInputHeight(_ height: CGFloat, shouldCommit: Bool) {
        let snappedHeight = snappedClampedHeight(height)
        slider.setValue(Float(snappedHeight), animated: true)
        updateValueLabel()
        if shouldCommit {
            updateInputField()
            onFinish(currentHeight)
        } else {
            onChange(currentHeight)
        }
    }

    private func snappedClampedHeight(_ height: CGFloat) -> CGFloat {
        let snappedHeight = (height / step).rounded() * step
        return min(max(snappedHeight, range.lowerBound), range.upperBound)
    }

    private func formattedHeightValue(_ height: CGFloat) -> String {
        if height.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(height))"
        }
        return String(format: "%.1f", height)
    }

    private func updateInputField() {
        isUpdatingInputFieldProgrammatically = true
        let text = formattedHeightValue(currentHeight)
        inputField.text = text
        updateInputFieldWidth(for: text)
        isUpdatingInputFieldProgrammatically = false
    }

    private func adaptiveInputFieldWidth(for text: String) -> CGFloat {
        let displayText = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "44" : text
        let font = inputField.font ?? .monospacedDigitSystemFont(ofSize: 18, weight: .black)
        let textWidth = (displayText as NSString).size(withAttributes: [.font: font]).width
        return min(max(ceil(textWidth) + 38, 62), 104)
    }

    private func updateInputFieldWidth(for text: String) {
        inputFieldWidthConstraint?.constant = adaptiveInputFieldWidth(for: text)
    }

    private func updateInputFieldAppearance(isEditing: Bool) {
        let borderColor = isEditing
            ? UIColor.systemBlue.withAlphaComponent(0.72)
            : UIColor.systemBlue.withAlphaComponent(0.28)
        inputField.layer.borderColor = borderColor.cgColor
        inputField.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(isEditing ? 0.96 : 0.82)
    }

    private func updateValueLabel() {
        guard !inputField.isFirstResponder else { return }
        updateInputField()
    }
}

private final class ClockOverlayView: UIView {
    private let timeLabel = UILabel()
    private let fpsLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(time: String, fps: String) {
        if timeLabel.text != time {
            timeLabel.text = time
        }
        if fpsLabel.text != fps {
            fpsLabel.text = fps
        }
    }

    func configure(height: CGFloat, hidden: Bool) {
        isHidden = hidden
        alpha = hidden ? 0 : 1
        layer.opacity = hidden ? 0 : 1
        backgroundColor = hidden ? .clear : .white
        layer.backgroundColor = (hidden ? UIColor.clear : UIColor.white).cgColor
        isOpaque = !hidden
        layer.isOpaque = !hidden

        let isCompactHeight = height < 40
        let shouldShowMetrics = !hidden && height >= 28
        let timeSize = isCompactHeight
            ? min(max(height * 0.56, 10), 22)
            : min(max(height * 0.58, 18), 40)
        let metricSize = isCompactHeight
            ? min(max(height * 0.22, 7), 11)
            : min(max(height * 0.3, 12), 18)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: timeSize, weight: .black)
	        fpsLabel.font = .monospacedDigitSystemFont(ofSize: metricSize, weight: .bold)

        let textColor: UIColor = hidden ? .clear : .black
	        timeLabel.textColor = textColor
        fpsLabel.textColor = shouldShowMetrics ? .darkGray : .clear
        fpsLabel.isHidden = !shouldShowMetrics
    }

    private func setup() {
        backgroundColor = .white
        layer.backgroundColor = UIColor.white.cgColor
        isOpaque = true
        layer.isOpaque = true
        isUserInteractionEnabled = false
        clipsToBounds = true

        timeLabel.textAlignment = .center
        timeLabel.adjustsFontSizeToFitWidth = true
        timeLabel.minimumScaleFactor = 0.45
        timeLabel.baselineAdjustment = .alignCenters
        timeLabel.textColor = .black

        fpsLabel.textAlignment = .center
        fpsLabel.adjustsFontSizeToFitWidth = true
        fpsLabel.minimumScaleFactor = 0.55
        fpsLabel.textColor = .darkGray

        addSubview(timeLabel)
        addSubview(fpsLabel)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        fpsLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            timeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            timeLabel.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.74),
            fpsLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            fpsLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            fpsLabel.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5)
        ])
    }
}

enum PlaceholderVideoFactory {
    // Compatibility mode is fixed at 300pt wide and uses integer-point heights.
    // Use the smallest exact even H.264 dimensions: even point heights map to 300xh;
    // odd point heights map to 600x(2h). This preserves the PiP aspect ratio exactly
    // while minimizing decoded pixels. Examples: 1pt -> 600x2, 22pt -> 300x22.

    private static let generationQueue = DispatchQueue(
        label: "speed.playerlayer.media-prewarm",
        qos: .utility
    )
    // A serial user-initiated lane gives the newest slider request deterministic priority
    // without spawning a burst of concurrent zlib/file-I/O work. Compact assets are tiny,
    // and stale queued requests are discarded before they touch disk.
    private static let interactiveGenerationQueue = DispatchQueue(
        label: "speed.playerlayer.media-interactive",
        qos: .userInitiated
    )
    private static let generationStateLock = NSLock()
    private static var latestInteractiveGeneration: UInt = 0
    private static var prewarmGeneration: UInt = 0
    private static var pendingPrefetchHeights: [Int] = []
    private static var isPrefetchWorkerScheduled = false

    // Only one thread may materialize a given height at a time. Other background callers
    // wait for that tiny decode to complete instead of duplicating zlib work and file writes.
    private static let materializationStateLock = NSLock()
    private static var inFlightMaterializations: [Int: DispatchGroup] = [:]

    private static let playerLayerAssetCache: NSCache<NSURL, AVURLAsset> = {
        let cache = NSCache<NSURL, AVURLAsset>()
        cache.countLimit = 40
        return cache
    }()

    private enum GenerationError: Error {
        case cancelled
        case invalidBundledMedia
        case bundledMediaDecompressionFailed
    }

    static func playerLayerBackingVideoSize(forPointHeight height: CGFloat) -> CGSize {
        let integralHeight = max(1, Int(height.rounded()))
        if integralHeight.isMultiple(of: 2) {
            return CGSize(width: 300, height: integralHeight)
        }
        return CGSize(width: 600, height: integralHeight * 2)
    }

    static func playerLayerBackingVideoURL(forPointHeight height: CGFloat) -> URL {
        let size = playerLayerBackingVideoSize(forPointHeight: height)
        return GeneratedPiPVideoCache.videoURL(
            named: "speed-playerlayer-geometry-\(Int(size.width))x\(Int(size.height))-30fps-60s-v2.mov"
        )
    }

    static func bundledPlayerLayerBackingVideoURL(forPointHeight height: CGFloat) -> URL? {
        let integralHeight = min(max(1, Int(height.rounded())), 220)
        return Bundle.main.url(
            forResource: String(format: "h%03d", integralHeight),
            withExtension: "mov",
            subdirectory: "CompatibilityMedia"
        )
    }

    private static func compressedBundledPlayerLayerBackingVideoURL(forPointHeight height: CGFloat) -> URL? {
        let integralHeight = min(max(1, Int(height.rounded())), 220)
        return Bundle.main.url(
            forResource: String(format: "h%03d", integralHeight),
            withExtension: "spm",
            subdirectory: "CompatibilityMedia"
        )
    }

    static func resolvedPlayerLayerBackingVideoURL(forPointHeight height: CGFloat) -> URL? {
        // The three hot paths (1pt hide, 22pt compact/default and 120pt large style) remain
        // normal .mov resources and therefore never pay decompression or cache I/O latency.
        if let bundled = bundledPlayerLayerBackingVideoURL(forPointHeight: height) {
            return bundled
        }
        let cached = playerLayerBackingVideoURL(forPointHeight: height)
        guard FileManager.default.fileExists(atPath: cached.path) else { return nil }
        return cached
    }

    private static func materializeCompressedBundledPlayerLayerBackingVideoIfAvailable(
        forPointHeight height: CGFloat,
        shouldContinue: @escaping () -> Bool
    ) throws -> URL? {
        let integralHeight = min(max(1, Int(height.rounded())), 220)
        let normalizedHeight = CGFloat(integralHeight)

        if let ready = resolvedPlayerLayerBackingVideoURL(forPointHeight: normalizedHeight) {
            return ready
        }
        guard compressedBundledPlayerLayerBackingVideoURL(forPointHeight: normalizedHeight) != nil else {
            return nil
        }
        guard shouldContinue() else { throw GenerationError.cancelled }

        // Coalesce concurrent requests for the same point height. A waiter periodically
        // checks cancellation so route changes never strand a background task. Keep the
        // ownership gate alive for the entire decode/write, not merely the acquisition loop.
        var ownedMaterializationGroup: DispatchGroup?
        while ownedMaterializationGroup == nil {
            materializationStateLock.lock()
            if let inFlight = inFlightMaterializations[integralHeight] {
                materializationStateLock.unlock()
                while inFlight.wait(timeout: .now() + .milliseconds(20)) == .timedOut {
                    guard shouldContinue() else { throw GenerationError.cancelled }
                }
                if let ready = resolvedPlayerLayerBackingVideoURL(forPointHeight: normalizedHeight) {
                    return ready
                }
                guard shouldContinue() else { throw GenerationError.cancelled }
                continue
            }

            let group = DispatchGroup()
            group.enter()
            inFlightMaterializations[integralHeight] = group
            ownedMaterializationGroup = group
            materializationStateLock.unlock()
        }

        guard let ownedMaterializationGroup else {
            throw GenerationError.bundledMediaDecompressionFailed
        }
        defer {
            materializationStateLock.lock()
            inFlightMaterializations.removeValue(forKey: integralHeight)
            materializationStateLock.unlock()
            ownedMaterializationGroup.leave()
        }

        if let ready = resolvedPlayerLayerBackingVideoURL(forPointHeight: normalizedHeight) {
            return ready
        }
        guard let resourceURL = compressedBundledPlayerLayerBackingVideoURL(forPointHeight: normalizedHeight) else {
            return nil
        }
        guard shouldContinue() else { throw GenerationError.cancelled }

        // .spm = 4-byte little-endian uncompressed byte count + zlib stream. Decode
        // directly from the mapped payload instead of creating a second Data copy.
        let packed = try Data(contentsOf: resourceURL, options: [.mappedIfSafe])
        guard packed.count > 4 else { throw GenerationError.invalidBundledMedia }
        let expectedSize = Int(packed[0])
            | (Int(packed[1]) << 8)
            | (Int(packed[2]) << 16)
            | (Int(packed[3]) << 24)
        guard expectedSize > 0, expectedSize <= 1_000_000 else {
            throw GenerationError.invalidBundledMedia
        }
        guard shouldContinue() else { throw GenerationError.cancelled }

        var decoded = Data(count: expectedSize)
        let decodedCount = decoded.withUnsafeMutableBytes { destinationBuffer -> Int in
            guard let destinationBase = destinationBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return packed.withUnsafeBytes { sourceBuffer -> Int in
                guard let sourceBase = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationBase,
                    expectedSize,
                    sourceBase.advanced(by: 4),
                    packed.count - 4,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decodedCount == expectedSize else {
            throw GenerationError.bundledMediaDecompressionFailed
        }
        guard shouldContinue() else { throw GenerationError.cancelled }

        let destinationURL = playerLayerBackingVideoURL(forPointHeight: normalizedHeight)
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporaryURL = destinationURL.deletingLastPathComponent().appendingPathComponent(
            ".\(UUID().uuidString)-\(destinationURL.lastPathComponent)"
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        // We already own a unique temporary file and finish with a rename. Avoid Data's
        // additional .atomic temporary-file layer, which otherwise doubles file-system work.
        try decoded.write(to: temporaryURL)
        guard shouldContinue() else { throw GenerationError.cancelled }

        if !fileManager.fileExists(atPath: destinationURL.path) {
            do {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            } catch {
                if !fileManager.fileExists(atPath: destinationURL.path) { throw error }
            }
        }
        return destinationURL
    }

    static func cachedAsset(for url: URL) -> AVURLAsset {
        let key = url as NSURL
        if let cached = playerLayerAssetCache.object(forKey: key) {
            return cached
        }
        let asset = AVURLAsset(url: url)
        playerLayerAssetCache.setObject(asset, forKey: key)
        return asset
    }

    static func isPlayerLayerBackingVideoReady(forPointHeight height: CGFloat) -> Bool {
        resolvedPlayerLayerBackingVideoURL(forPointHeight: height) != nil
    }

    static func prewarmPlayerLayerBackingVideo(forPointHeight height: CGFloat) {
        schedulePrefetchPlan([min(max(1, Int(height.rounded())), 220)])
    }

    static func prefetchPlayerLayerBackingVideos(
        around height: CGFloat,
        direction: Int,
        policy: PerformanceGovernorSnapshot
    ) {
        let center = min(max(1, Int(height.rounded())), 220)
        var plan: [Int] = [center]
        guard policy.permitsSpeculativePrefetch else {
            schedulePrefetchPlan(plan)
            return
        }

        @inline(__always) func appendIfValid(_ candidate: Int) {
            guard (1...220).contains(candidate), !plan.contains(candidate) else { return }
            plan.append(candidate)
        }

        if direction > 0 {
            if policy.prefetchAhead > 0 {
                for delta in 1...policy.prefetchAhead { appendIfValid(center + delta) }
            }
            if policy.prefetchBehind > 0 {
                for delta in 1...policy.prefetchBehind { appendIfValid(center - delta) }
            }
        } else if direction < 0 {
            if policy.prefetchAhead > 0 {
                for delta in 1...policy.prefetchAhead { appendIfValid(center - delta) }
            }
            if policy.prefetchBehind > 0 {
                for delta in 1...policy.prefetchBehind { appendIfValid(center + delta) }
            }
        } else if policy.neutralPrefetchRadius > 0 {
            for delta in 1...policy.neutralPrefetchRadius {
                appendIfValid(center + delta)
                appendIfValid(center - delta)
            }
        }

        let learned = SmartHeightLearningStore.preferredHeights(isCompatibility: true, limit: 3)
        for height in learned { appendIfValid(Int(height.rounded())) }
        schedulePrefetchPlan(plan)
    }

    private static func schedulePrefetchPlan(_ heights: [Int]) {
        var shouldStartWorker = false
        generationStateLock.lock()
        prewarmGeneration &+= 1
        pendingPrefetchHeights = heights
        if !isPrefetchWorkerScheduled {
            isPrefetchWorkerScheduled = true
            shouldStartWorker = true
        }
        generationStateLock.unlock()

        guard shouldStartWorker else { return }
        generationQueue.async { runPrefetchWorker() }
    }

    private static func runPrefetchWorker() {
        while true {
            generationStateLock.lock()
            guard !pendingPrefetchHeights.isEmpty else {
                isPrefetchWorkerScheduled = false
                generationStateLock.unlock()
                return
            }
            let generation = prewarmGeneration
            let height = pendingPrefetchHeights.removeFirst()
            generationStateLock.unlock()

            guard isPrewarmGenerationCurrent(generation) else { continue }
            let pointHeight = CGFloat(height)
            if let ready = resolvedPlayerLayerBackingVideoURL(forPointHeight: pointHeight) {
                _ = cachedAsset(for: ready)
                continue
            }

            do {
                if let url = try materializeCompressedBundledPlayerLayerBackingVideoIfAvailable(
                    forPointHeight: pointHeight,
                    shouldContinue: { isPrewarmGenerationCurrent(generation) }
                ) {
                    _ = cachedAsset(for: url)
                }
            } catch GenerationError.cancelled {
                continue
            } catch {
#if DEBUG
                AppDebugLogger.log("Compatibility prediction prefetch failed at \(height)pt: \(error.localizedDescription)")
#endif
            }
        }
    }

    static func cancelPendingPlayerLayerMediaWork() {
        generationStateLock.lock()
        latestInteractiveGeneration &+= 1
        prewarmGeneration &+= 1
        generationStateLock.unlock()
    }

    private static func isPrewarmGenerationCurrent(_ generation: UInt) -> Bool {
        generationStateLock.lock()
        let current = prewarmGeneration == generation
        generationStateLock.unlock()
        return current
    }

    static func preparePlayerLayerBackingVideo(
        forPointHeight height: CGFloat,
        requestGeneration: UInt,
        completion: @escaping (URL) -> Void
    ) {
        setLatestInteractiveGeneration(requestGeneration)
        if let readyURL = resolvedPlayerLayerBackingVideoURL(forPointHeight: height) {
            SpeedPerformanceLab.recordCacheHit()
            completion(readyURL)
            return
        }
        SpeedPerformanceLab.recordCacheMiss()

        interactiveGenerationQueue.async {
            // Drop superseded work before it touches mapped data or disk. If a tiny decode
            // has already started, materialization itself completes atomically and becomes
            // useful cache for a later reversal.
            guard isInteractiveGenerationCurrent(requestGeneration) else { return }
            do {
                if let compactURL = try materializeCompressedBundledPlayerLayerBackingVideoIfAvailable(
                    forPointHeight: height,
                    shouldContinue: { true }
                ) {
                    _ = cachedAsset(for: compactURL)
                    guard isInteractiveGenerationCurrent(requestGeneration) else { return }
                    completion(compactURL)
                    return
                }
            } catch {
#if DEBUG
                AppDebugLogger.log("Compact interactive media decode failed: \(error.localizedDescription)")
#endif
            }

#if DEBUG
            // Keep the slow H.264 generator only for development diagnostics. Production
            // builds ship and CI-validate all 220 exact geometries, so a 1,800-frame encode
            // must never steal CPU/energy from the live UI.
            guard isInteractiveGenerationCurrent(requestGeneration) else { return }
            let url = playerLayerBackingVideoURL(forPointHeight: height)
            do {
                try makePlayerLayerBackingVideoIfNeeded(
                    forPointHeight: height,
                    shouldContinue: { isInteractiveGenerationCurrent(requestGeneration) }
                )
                guard isInteractiveGenerationCurrent(requestGeneration) else { return }
                completion(url)
            } catch GenerationError.cancelled {
            } catch {
                AppDebugLogger.log("PlayerLayer geometry debug generation failed: \(error.localizedDescription)")
            }
#endif
        }
    }

    private static func setLatestInteractiveGeneration(_ generation: UInt) {
        generationStateLock.lock()
        latestInteractiveGeneration = generation
        generationStateLock.unlock()
    }

    private static func isInteractiveGenerationCurrent(_ generation: UInt) -> Bool {
        generationStateLock.lock()
        let current = latestInteractiveGeneration == generation
        generationStateLock.unlock()
        return current
    }

    static func makePlayerLayerBackingVideoIfNeeded(
        forPointHeight height: CGFloat,
        shouldContinue: @escaping () -> Bool = { true }
    ) throws {
        guard resolvedPlayerLayerBackingVideoURL(forPointHeight: height) == nil else { return }

        // 2.3.7 compact-media fast path. Most compatibility geometries ship as tiny zlib
        // resources and are materialized into the bounded generated-media cache on demand. If
        // the compact resource is unavailable/corrupt on a future build, retain the proven
        // cancellable H.264 generator as a last-resort fallback rather than failing PiP.
        do {
            if try materializeCompressedBundledPlayerLayerBackingVideoIfAvailable(
                forPointHeight: height,
                shouldContinue: shouldContinue
            ) != nil {
                return
            }
        } catch GenerationError.cancelled {
            throw GenerationError.cancelled
        } catch {
#if DEBUG
            AppDebugLogger.log("Compact compatibility media fallback: \(error.localizedDescription)")
#endif
        }

        guard shouldContinue() else { throw GenerationError.cancelled }
#if DEBUG
        let url = playerLayerBackingVideoURL(forPointHeight: height)
        try makeVideoAtomically(
            at: url,
            size: playerLayerBackingVideoSize(forPointHeight: height),
            text: "",
            frameCount: 1_800,
            frameRate: 30,
            shouldContinue: shouldContinue
        )
#else
        throw GenerationError.invalidBundledMedia
#endif
    }

    static func makeBackingVideo(at url: URL, size: CGSize, text: String) throws {
        try makeVideoAtomically(at: url, size: size, text: text, frameCount: 1, frameRate: 10)
    }

    static func makeLongBackingVideo(at url: URL, size: CGSize, text: String) throws {
        try makeVideoAtomically(at: url, size: size, text: text, frameCount: 1_800, frameRate: 30)
    }

    private static func makeVideoAtomically(
        at url: URL,
        size: CGSize,
        text: String,
        frameCount: Int,
        frameRate: Int32,
        shouldContinue: @escaping () -> Bool = { true }
    ) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) { return }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(
            ".\(UUID().uuidString)-\(url.lastPathComponent)"
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try makeVideo(
            at: temporaryURL,
            size: size,
            text: text,
            frameCount: frameCount,
            frameRate: frameRate,
            shouldContinue: shouldContinue
        )
        guard shouldContinue() else { throw GenerationError.cancelled }

        // Another prewarm may have won the race. Never replace a complete cache file.
        guard !fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.moveItem(at: temporaryURL, to: url)
        } catch {
            if !fileManager.fileExists(atPath: url.path) { throw error }
        }
    }

    private static func makeVideo(
        at url: URL,
        size: CGSize,
        text: String,
        frameCount: Int,
        frameRate: Int32,
        shouldContinue: @escaping () -> Bool
    ) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 40_000,
                AVVideoMaxKeyFrameIntervalKey: Int(frameRate) * 2
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let sourceAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourceAttributes
        )

        guard writer.canAdd(input) else {
            throw NSError(domain: "PlaceholderVideoFactory", code: 1)
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "PlaceholderVideoFactory", code: 2)
        }
        writer.startSession(atSourceTime: .zero)

        guard let pixelBuffer = makePixelBuffer(size: size, text: text) else {
            throw NSError(domain: "PlaceholderVideoFactory", code: 3)
        }

        let frameDuration = CMTime(value: 1, timescale: frameRate)
        let group = DispatchGroup()
        group.enter()
        let writerQueue = DispatchQueue(
            label: "speed.playerlayer.media-writer.\(UUID().uuidString)",
            qos: .utility
        )
        let totalFrames = max(frameCount, 1)
        var frameIndex = 0
        var didFinishInput = false
        input.requestMediaDataWhenReady(on: writerQueue) {
            guard !didFinishInput else { return }
            while input.isReadyForMoreMediaData && frameIndex < totalFrames {
                guard shouldContinue() else {
                    didFinishInput = true
                    input.markAsFinished()
                    group.leave()
                    return
                }
                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
                guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                    didFinishInput = true
                    input.markAsFinished()
                    group.leave()
                    return
                }
                frameIndex += 1
            }
            if frameIndex >= totalFrames, !didFinishInput {
                didFinishInput = true
                input.markAsFinished()
                group.leave()
            }
        }
        guard group.wait(timeout: .now() + 30) == .success else {
            writer.cancelWriting()
            throw NSError(
                domain: "PlaceholderVideoFactory",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Timed out while feeding video frames"]
            )
        }
        guard shouldContinue() else {
            writer.cancelWriting()
            throw GenerationError.cancelled
        }

        let finish = DispatchSemaphore(value: 0)
        writer.finishWriting { finish.signal() }
        guard finish.wait(timeout: .now() + 15) == .success else {
            writer.cancelWriting()
            throw NSError(
                domain: "PlaceholderVideoFactory",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Timed out while finishing video"]
            )
        }
        if let error = writer.error { throw error }
    }

    private static func makePixelBuffer(size: CGSize, text: String) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: baseAddress,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Solid black compresses to a near-zero-entropy H.264 stream and costs less to decode.
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        if !text.isEmpty {
            UIGraphicsPushContext(context)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let fontSize = max(2, min(size.height * 0.34, 26))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let rect = CGRect(x: 2, y: max(0, (size.height - fontSize * 1.4) / 2), width: max(0, size.width - 4), height: fontSize * 1.4)
            NSString(string: text).draw(in: rect, withAttributes: attributes)
            UIGraphicsPopContext()
        }
        return pixelBuffer
    }
}

private extension ViewController {
    @inline(__always) func updateDiagnosticsPiPState() {}

    @inline(__always) func updateDisplaySleepDiagnostics(
        reason: String = "",
        shouldLog: Bool = false
    ) {
        _ = reason
        _ = shouldLog
    }

    @inline(__always) func logPiPSurfaceDiagnostics(_ reason: String) {
        _ = reason
    }

    @inline(__always) func configureForClockRefreshRate(_ displayLink: CADisplayLink) {
        displayLink.preferredFrameRateRange = CAFrameRateRange(
            minimum: 30,
            maximum: 30,
            preferred: 30
        )
    }

    @inline(__always) func formatRect(_ rect: CGRect) -> String {
        String(
            format: "{%.1f,%.1f,%.1f,%.1f}",
            rect.origin.x, rect.origin.y, rect.size.width, rect.size.height
        )
    }
}
