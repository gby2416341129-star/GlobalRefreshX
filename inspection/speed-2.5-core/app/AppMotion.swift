//
//  AppMotion.swift
//  pip_swift
//
//  Centralized motion policy for native-feeling, interruption-safe animation.
//  The app never ties UI animation speed to the refresh-rate forcing mechanism.
//

import UIKit

enum AppMotion {
    enum Duration {
        static let quick: TimeInterval = 0.16
        static let standard: TimeInterval = 0.24
        static let emphasized: TimeInterval = 0.34
    }

    enum Transform {
        static let subtleLift = CGAffineTransform(translationX: 0, y: 6)
            .scaledBy(x: 0.992, y: 0.992)
    }

    static var reduceMotionEnabled: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    /// Creates an interruptible animator suitable for navigation/tab transitions.
    /// Keep animations on opacity/transform whenever possible so Core Animation can
    /// composite them efficiently at ProMotion refresh rates.
    static func makeAnimator(
        duration: TimeInterval = Duration.standard,
        curve: UIView.AnimationCurve = .easeOut,
        animations: @escaping () -> Void
    ) -> UIViewPropertyAnimator {
        let resolvedDuration = reduceMotionEnabled ? min(duration, 0.12) : duration
        return UIViewPropertyAnimator(duration: resolvedDuration, curve: curve, animations: animations)
    }

    static func prepareIncomingView(_ view: UIView) {
        view.alpha = 0
        view.transform = reduceMotionEnabled ? .identity : Transform.subtleLift
    }

    static func finishIncomingView(_ view: UIView) {
        view.alpha = 1
        view.transform = .identity
    }
}
