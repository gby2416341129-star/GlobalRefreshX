import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        AppDisplayContext.register(windowScene)
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = ViewController()
        AppAppearancePreference.apply(to: window)
        self.window = window
        window.makeKeyAndVisible()
        NotificationCenter.default.addObserver(self, selector: #selector(handleSpeedLaunchAction), name: SpeedLaunchActionRouter.didSubmitNotification, object: nil)
        RefreshRateController.shared.reconcile()
        dispatchPendingSpeedLaunchTarget()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        if let windowScene = scene as? UIWindowScene { AppDisplayContext.register(windowScene) }
        RefreshRateController.shared.reconcile()
        dispatchPendingSpeedLaunchTarget()
#if DEBUG
        DebugDiagnosticsMonitor.startIfNeeded()
#endif
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
#if DEBUG
        DebugDiagnosticsMonitor.stop()
#endif
        RefreshRateController.shared.reconcile()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        if let windowScene = scene as? UIWindowScene { AppDisplayContext.unregister(windowScene) }
        LatencyExperimentController.shared.detach()
        RefreshRateController.shared.stop()
    }

    @objc private func handleSpeedLaunchAction() {
        dispatchPendingSpeedLaunchTarget()
    }

    private func dispatchPendingSpeedLaunchTarget() {
        guard let target = SpeedLaunchActionRouter.consumePendingTarget() else { return }
        guard let controller = window?.rootViewController as? ViewController else {
            SpeedLaunchActionRouter.restorePending(target)
            return
        }
        controller.handleSystemLaunchTarget(target)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
