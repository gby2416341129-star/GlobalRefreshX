//
//  AdaptiveSheetPresentation.swift
//  pip_swift
//

import UIKit

extension UIViewController {
    func configureAdaptivePageSheet(preferredHeightRatio: CGFloat = 0.58) {
        modalPresentationStyle = .pageSheet
        guard let sheet = sheetPresentationController else { return }

        let mediumDetent = UISheetPresentationController.Detent.medium()
        if #available(iOS 26.1, *) {
            mediumDetent.backgroundEffect = UIGlassEffect(style: .clear)
        }
        sheet.detents = [mediumDetent]
        sheet.selectedDetentIdentifier = .medium
        sheet.prefersGrabberVisible = true
        sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        sheet.prefersEdgeAttachedInCompactHeight = true
        sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
        sheet.preferredCornerRadius = adaptiveSheetCornerRadius
    }

    func applyLegacyGlassSheetBackground() -> UIView {
        view.backgroundColor = .clear

        let glassEffect = UIGlassEffect(style: .regular)
        glassEffect.isInteractive = true
        let glassView = UIVisualEffectView(effect: glassEffect)
        glassView.layer.cornerRadius = adaptiveSheetCornerRadius
        glassView.layer.cornerCurve = .continuous
        glassView.clipsToBounds = true
        glassView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(glassView)
        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            glassView.topAnchor.constraint(equalTo: view.topAnchor),
            glassView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        return glassView.contentView
    }

    private var adaptiveSheetCornerRadius: CGFloat {
        let screenBounds = AppDisplayContext.bounds
        let shortestSide = min(screenBounds.width, screenBounds.height)
        switch shortestSide {
        case ..<360:
            return 22
        case ..<430:
            return 26
        default:
            return 30
        }
    }
}
