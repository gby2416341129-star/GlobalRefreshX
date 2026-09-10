import AVKit
import UIKit

/// Creates and owns the route-specific AVPictureInPictureController wiring.
///
/// Speed only targets iOS 26+, so this object intentionally contains
/// no legacy OS fallback branches. Route selection is explicit and construction
/// is kept out of the main view controller to make lifecycle failures easier to
/// reason about and test.
final class PiPEngineController {
    struct Session {
        let controller: AVPictureInPictureController
        let videoCallContentController: AVPictureInPictureVideoCallViewController?
        let route: PiPEngineRoute
    }

    enum EngineError: LocalizedError {
        case pictureInPictureUnsupported
        case missingSourceView
        case missingPlayerLayer
        case playerLayerControllerCreationFailed

        var errorDescription: String? {
            switch self {
            case .pictureInPictureUnsupported:
                return "Picture in Picture is not supported on this device."
            case .missingSourceView:
                return "VideoCall PiP source view is missing."
            case .missingPlayerLayer:
                return "PlayerLayer PiP route requires a prepared AVPlayerLayer."
            case .playerLayerControllerCreationFailed:
                return "PlayerLayer PiP controller could not be created."
            }
        }
    }

    private(set) var session: Session?

    var controller: AVPictureInPictureController? { session?.controller }
    var videoCallContentController: AVPictureInPictureVideoCallViewController? {
        session?.videoCallContentController
    }

    enum StartRequestResult: Equatable {
        case requested
        case alreadyActive
        case unavailable
    }

    @discardableResult
    func requestStart() -> StartRequestResult {
        guard let controller = session?.controller else {
            AppDebugLogger.log("PiP engine start skipped: no active session")
            return .unavailable
        }
        guard !controller.isPictureInPictureActive else {
            return .alreadyActive
        }
        controller.startPictureInPicture()
        AppDebugLogger.log("PiP engine start requested: \(session?.route.diagnosticsName ?? "unknown")")
        return .requested
    }

    @discardableResult
    func requestStop() -> Bool {
        guard let controller = session?.controller else {
            AppDebugLogger.log("PiP engine stop skipped: no active session")
            return false
        }
        guard controller.isPictureInPictureActive else {
            return false
        }
        controller.stopPictureInPicture()
        AppDebugLogger.log("PiP engine stop requested: \(session?.route.diagnosticsName ?? "unknown")")
        return true
    }

    @discardableResult
    func prepare(
        route: PiPEngineRoute,
        sourceView: UIView?,
        playerLayer: AVPlayerLayer?,
        preferredContentSize: CGSize,
        delegate: AVPictureInPictureControllerDelegate
    ) throws -> Session {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            throw EngineError.pictureInPictureUnsupported
        }

        reset()

        let newSession: Session
        if route.usesPlayerLayer {
            guard let playerLayer else {
                throw EngineError.missingPlayerLayer
            }
            guard let controller = AVPictureInPictureController(playerLayer: playerLayer) else {
                throw EngineError.playerLayerControllerCreationFailed
            }
            controller.delegate = delegate
            newSession = Session(
                controller: controller,
                videoCallContentController: nil,
                route: route
            )
        } else {
            guard let sourceView else {
                throw EngineError.missingSourceView
            }

            let contentController = AVPictureInPictureVideoCallViewController()
            contentController.preferredContentSize = preferredContentSize
            contentController.view.backgroundColor = .clear
            contentController.view.isOpaque = false
            contentController.view.layer.backgroundColor = UIColor.clear.cgColor
            contentController.view.layer.isOpaque = false
            contentController.view.clipsToBounds = true

            let contentSource = AVPictureInPictureController.ContentSource(
                activeVideoCallSourceView: sourceView,
                contentViewController: contentController
            )
            let controller = AVPictureInPictureController(contentSource: contentSource)
            controller.delegate = delegate
            newSession = Session(
                controller: controller,
                videoCallContentController: contentController,
                route: route
            )
        }

        session = newSession
        AppDebugLogger.log("PiP engine prepared: \(route.diagnosticsName)")
        return newSession
    }

    func reset() {
        guard let oldSession = session else { return }
        oldSession.controller.delegate = nil
        session = nil
        AppDebugLogger.log("PiP engine reset: \(oldSession.route.diagnosticsName)")
    }
}
