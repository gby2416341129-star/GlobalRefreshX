import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
#if DEBUG
        DiagnosticsResetManager.resetDiagnosticsIfBuildChanged()
        DiagnosticsResetManager.clearDiagnosticsIfDebugModeDisabled()
        AppDebugLogger.trimOnLaunch()
        AppDebugLogger.registerBackgroundFlush()
        if AppDebugLogger.isDebugModeEnabled {
            DiagnosticsRuntimeState.startAppStateTracking()
            DiagnosticsRuntimeState.refreshAppState()
            MetricKitLogger.shared.start()
            DebugDiagnosticsMonitor.setEnabled(true)
            ProcessTerminationDiagnostics.prepareForLaunch()
        }
#endif
        CacheCleanupManager.cleanOnLaunch()
        KeepAliveModeText.migrateDefaultToLowPowerPiPIfNeeded()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
