import AVKit
import UIKit

/// 集中隔离系统没有公开 API 的兼容行为。
///
/// Speed 的核心逻辑只使用公开 AVKit/UIKit API。确实影响现有功能、
/// 但 Apple 尚未提供公开替代方案的行为统一放在这里，便于后续 iOS 26/27
/// 实机验证、关闭或替换，而不会污染 PiP Engine。
enum PiPCompatibilityAdapter {
    /// 原项目依赖该 KVC 值来尽量隐藏系统 PiP 控件。
    /// `controlsStyle` 不是公开 API，因此必须保持单点隔离。
    @discardableResult
    static func applyHiddenSystemControls(to controller: AVPictureInPictureController) -> Bool {
        let key = "controlsStyle"
        let setter = NSSelectorFromString("setControlsStyle:")
        guard controller.responds(to: setter) else {
            AppDebugLogger.log("PiP 兼容层：系统不再暴露 controlsStyle setter，跳过隐藏控件")
            return false
        }
        controller.setValue(2, forKey: key)
        AppDebugLogger.log("PiP 兼容层：已应用隐藏系统控件样式")
        return true
    }

    /// 原项目在自定义关闭 PiP 时使用 `suspend` 避免 App 被系统重新拉回前台。
    /// 这不是公开 UIKit API，只保留在兼容层，并在系统不响应时安全失败。
    @discardableResult
    static func requestResignForeground() -> Bool {
        let selector = NSSelectorFromString("suspend")
        guard UIApplication.shared.responds(to: selector) else {
            AppDebugLogger.log("PiP 兼容层：系统不支持前台退出兼容动作")
            return false
        }
        UIApplication.shared.perform(selector)
        return true
    }
}
