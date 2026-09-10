import UIKit

/// Centralizes PiP sizing rules and source-surface geometry.
///
/// Speed only targets iOS 26+, so this controller intentionally has
/// no legacy OS branches. It owns the geometry policy shared by VideoCall and
/// PlayerLayer routes while leaving AVKit lifecycle decisions to the PiP engine.
final class PiPGeometryController {
    enum Route {
        case videoCall
        case playerLayer
    }

    struct Metrics: Equatable {
        let minimumHeight: CGFloat
        let heightStep: CGFloat
        let defaultHeight: CGFloat
        let maximumHeight: CGFloat
    }

    static let shared = PiPGeometryController()

    let videoCallMetrics = Metrics(
        minimumHeight: 0.1,
        heightStep: 0.1,
        defaultHeight: 44,
        maximumHeight: 220
    )

    let playerLayerMetrics = Metrics(
        minimumHeight: 1,
        heightStep: 1,
        defaultHeight: 22,
        maximumHeight: 220
    )

    private init() {}

    func metrics(for route: Route) -> Metrics {
        switch route {
        case .videoCall:
            return videoCallMetrics
        case .playerLayer:
            return playerLayerMetrics
        }
    }

    func clampedHeight(_ height: CGFloat, route: Route) -> CGFloat {
        let metrics = metrics(for: route)
        let stepped: CGFloat
        switch route {
        case .videoCall:
            stepped = (height / metrics.heightStep).rounded() * metrics.heightStep
        case .playerLayer:
            stepped = metrics.minimumHeight
                + ((height - metrics.minimumHeight) / metrics.heightStep).rounded() * metrics.heightStep
        }
        return min(max(stepped, metrics.minimumHeight), metrics.maximumHeight)
    }

    func isVisuallyHidden(height: CGFloat, route: Route) -> Bool {
        guard route == .videoCall else { return false }
        return clampedHeight(height, route: route) <= 0.15
    }

    func effectiveSurfaceHeight(height: CGFloat, route: Route, visuallyHidden: Bool) -> CGFloat {
        let clamped = clampedHeight(height, route: route)
        guard route == .playerLayer, visuallyHidden else { return clamped }
        return playerLayerMetrics.minimumHeight
    }

    func centeredFrame(size: CGSize, in bounds: CGRect, safeAreaInsets: UIEdgeInsets) -> CGRect {
        let safeBounds = bounds.inset(by: safeAreaInsets)
        return CGRect(
            x: safeBounds.midX - size.width / 2,
            y: safeBounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
