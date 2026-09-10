//
//  HomePresentationState.swift
//  pip_swift
//
//  A small immutable snapshot for the home screen.  The UI renders this state;
//  it does not own PiP or refresh-rate behavior.  Keeping presentation state
//  separate prevents visual code from becoming another source of truth.
//

import Foundation

struct HomePresentationState: Equatable {
    enum Activity: Equatable {
        case ready
        case starting
        case running
        case hidden
        case stopping
        case failed
    }

    enum Engine: Equatable {
        case videoCall
        case playerLayer
    }

    let activity: Activity
    let engine: Engine
    let requestedFrameRate: Int
    let refreshRequestActive: Bool
    let pipHeightText: String

    var title: String {
        switch activity {
        case .ready: return "待启用"
        case .starting: return "正在启动"
        case .running: return "\(requestedFrameRate)Hz 运行中"
        case .hidden: return "\(requestedFrameRate)Hz 运行中 · 已隐藏"
        case .stopping: return "正在关闭"
        case .failed: return "需要检查"
        }
    }

    /// The app-level CADisplayLink is intentionally stopped on PlayerLayer.
    /// Therefore `refreshRequestActive` is diagnostic information, not the truth
    /// source for whether the PiP compatibility route is operating.
    var statusEmphasisActive: Bool {
        switch activity {
        case .running, .hidden:
            return true
        case .ready, .starting, .stopping, .failed:
            return false
        }
    }

    var engineTitle: String {
        switch engine {
        case .videoCall: return "标准模式"
        case .playerLayer: return "兼容模式"
        }
    }

    var primaryActionTitle: String {
        switch activity {
        case .starting: return "正在启动"
        case .running, .hidden: return "关闭悬浮窗"
        case .stopping: return "正在关闭"
        case .ready, .failed: return "开启悬浮窗"
        }
    }

    var primaryActionSystemImage: String {
        switch activity {
        case .running, .hidden, .stopping:
            return "pip.exit"
        case .ready, .starting, .failed:
            return "pip.enter"
        }
    }

    var allowsPrimaryAction: Bool {
        switch activity {
        case .starting, .stopping: return false
        case .ready, .running, .hidden, .failed: return true
        }
    }

    var hideActionTitle: String {
        engine == .playerLayer ? "一键 1pt" : "一键 0.1pt"
    }

    var allowsHideAction: Bool {
        switch activity {
        case .running, .hidden: return true
        case .ready, .starting, .stopping, .failed: return false
        }
    }

    var statusSystemImage: String {
        switch activity {
        case .ready: return "circle.dashed"
        case .starting: return "ellipsis.circle"
        case .running: return "waveform.path.ecg"
        case .hidden: return "eye.slash.circle.fill"
        case .stopping: return "stop.circle"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}
