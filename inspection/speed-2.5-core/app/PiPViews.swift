import SwiftUI
import UIKit
import Observation

@MainActor
@Observable
final class SpeedHomeViewModel {

    private(set) var isPiPActive: Bool
    private(set) var presentationState: HomePresentationState
    private(set) var pipHeight: String
    private(set) var isCurrentAppearanceDark: Bool
    private(set) var pipEngineRoute: PiPEngineRoute
    private(set) var latencyExperimentState: LatencyExperimentState
    private(set) var performanceGovernorSnapshot: PerformanceGovernorSnapshot
    private(set) var performanceLabSnapshot: PerformanceLabSnapshot

    let onTogglePiP: () -> Void
    let onHidePiP: () -> Void
    let onStartAndHidePiP: () -> Void
    let onToggleStyle: () -> Void
    let onCustomizeHeight: () -> Void
    let onToggleAppearanceMode: () -> Void
    let onClearCache: () -> Void
    let onSetPiPEngineRoute: (PiPEngineRoute) -> Void
    let onSetLatencyExperimentAll: (Bool) -> Void
    let onSetLowLatencyEventDispatch: (Bool) -> Void
    let onSetImmediatePresentation: (Bool) -> Void
    let onSetContinuousUpdates: (Bool) -> Void
    let onSetDirectCompatibilityResize: (Bool) -> Void
    let onSetRefreshDriverMode: (RefreshDriverMode) -> Void

    init(
        isPiPActive: Bool,
        presentationState: HomePresentationState,
        pipHeight: String,
        isCurrentAppearanceDark: Bool,
        pipEngineRoute: PiPEngineRoute,
        latencyExperimentState: LatencyExperimentState,
        performanceGovernorSnapshot: PerformanceGovernorSnapshot,
        performanceLabSnapshot: PerformanceLabSnapshot,
        onTogglePiP: @escaping () -> Void,
        onHidePiP: @escaping () -> Void,
        onStartAndHidePiP: @escaping () -> Void,
        onToggleStyle: @escaping () -> Void,
        onCustomizeHeight: @escaping () -> Void,
        onToggleAppearanceMode: @escaping () -> Void,
        onClearCache: @escaping () -> Void,
        onSetPiPEngineRoute: @escaping (PiPEngineRoute) -> Void,
        onSetLatencyExperimentAll: @escaping (Bool) -> Void,
        onSetLowLatencyEventDispatch: @escaping (Bool) -> Void,
        onSetImmediatePresentation: @escaping (Bool) -> Void,
        onSetContinuousUpdates: @escaping (Bool) -> Void,
        onSetDirectCompatibilityResize: @escaping (Bool) -> Void,
        onSetRefreshDriverMode: @escaping (RefreshDriverMode) -> Void
    ) {
        self.isPiPActive = isPiPActive
        self.presentationState = presentationState
        self.pipHeight = pipHeight
        self.isCurrentAppearanceDark = isCurrentAppearanceDark
        self.pipEngineRoute = pipEngineRoute
        self.latencyExperimentState = latencyExperimentState
        self.performanceGovernorSnapshot = performanceGovernorSnapshot
        self.performanceLabSnapshot = performanceLabSnapshot
        self.onTogglePiP = onTogglePiP
        self.onHidePiP = onHidePiP
        self.onStartAndHidePiP = onStartAndHidePiP
        self.onToggleStyle = onToggleStyle
        self.onCustomizeHeight = onCustomizeHeight
        self.onToggleAppearanceMode = onToggleAppearanceMode
        self.onClearCache = onClearCache
        self.onSetPiPEngineRoute = onSetPiPEngineRoute
        self.onSetLatencyExperimentAll = onSetLatencyExperimentAll
        self.onSetLowLatencyEventDispatch = onSetLowLatencyEventDispatch
        self.onSetImmediatePresentation = onSetImmediatePresentation
        self.onSetContinuousUpdates = onSetContinuousUpdates
        self.onSetDirectCompatibilityResize = onSetDirectCompatibilityResize
        self.onSetRefreshDriverMode = onSetRefreshDriverMode
    }

    func update(
        isPiPActive: Bool,
        presentationState: HomePresentationState,
        pipHeight: String,
        isCurrentAppearanceDark: Bool,
        pipEngineRoute: PiPEngineRoute,
        latencyExperimentState: LatencyExperimentState,
        performanceGovernorSnapshot: PerformanceGovernorSnapshot,
        performanceLabSnapshot: PerformanceLabSnapshot
    ) {
        guard self.isPiPActive != isPiPActive
            || self.presentationState != presentationState
            || self.pipHeight != pipHeight
            || self.isCurrentAppearanceDark != isCurrentAppearanceDark
            || self.pipEngineRoute != pipEngineRoute
            || self.latencyExperimentState != latencyExperimentState
            || self.performanceGovernorSnapshot != performanceGovernorSnapshot
            || self.performanceLabSnapshot != performanceLabSnapshot
        else { return }

        self.isPiPActive = isPiPActive
        self.presentationState = presentationState
        self.pipHeight = pipHeight
        self.isCurrentAppearanceDark = isCurrentAppearanceDark
        self.pipEngineRoute = pipEngineRoute
        self.latencyExperimentState = latencyExperimentState
        self.performanceGovernorSnapshot = performanceGovernorSnapshot
        self.performanceLabSnapshot = performanceLabSnapshot
    }
}

/// Speed's control surface plus an opt-in Laboratory page. The existing Speed
/// controls remain unchanged; the Laboratory reuses the same visual system and
/// contains no frame sampler, network reader, or update checker.
struct PiPHomeView: View {
    let model: SpeedHomeViewModel

    private var isPiPActive: Bool { model.isPiPActive }
    private var presentationState: HomePresentationState { model.presentationState }
    private var pipHeight: String { model.pipHeight }
    private var isCurrentAppearanceDark: Bool { model.isCurrentAppearanceDark }
    private var pipEngineRoute: PiPEngineRoute { model.pipEngineRoute }
    private var onTogglePiP: () -> Void { model.onTogglePiP }
    private var onHidePiP: () -> Void { model.onHidePiP }
    private var onStartAndHidePiP: () -> Void { model.onStartAndHidePiP }
    private var onToggleStyle: () -> Void { model.onToggleStyle }
    private var onCustomizeHeight: () -> Void { model.onCustomizeHeight }
    private var onToggleAppearanceMode: () -> Void { model.onToggleAppearanceMode }
    private var onClearCache: () -> Void { model.onClearCache }
    private var onSetPiPEngineRoute: (PiPEngineRoute) -> Void { model.onSetPiPEngineRoute }
    private var latencyExperimentState: LatencyExperimentState { model.latencyExperimentState }
    private var onSetLatencyExperimentAll: (Bool) -> Void { model.onSetLatencyExperimentAll }
    private var onSetLowLatencyEventDispatch: (Bool) -> Void { model.onSetLowLatencyEventDispatch }
    private var onSetImmediatePresentation: (Bool) -> Void { model.onSetImmediatePresentation }
    private var onSetContinuousUpdates: (Bool) -> Void { model.onSetContinuousUpdates }
    private var onSetDirectCompatibilityResize: (Bool) -> Void { model.onSetDirectCompatibilityResize }
    private var onSetRefreshDriverMode: (RefreshDriverMode) -> Void { model.onSetRefreshDriverMode }
    private var performanceGovernorSnapshot: PerformanceGovernorSnapshot { model.performanceGovernorSnapshot }
    private var performanceLabSnapshot: PerformanceLabSnapshot { model.performanceLabSnapshot }

    private enum Page: Hashable {
        case speed
        case laboratory
    }

    @State private var selectedPage: Page = .speed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            SpeedBackground().ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: proxy.size.height < 700 ? 15 : 20) {
                        header
                        pageSwitcher

                        Group {
                            switch selectedPage {
                            case .speed:
                                speedPage
                            case .laboratory:
                                laboratoryPage
                            }
                        }
                        .transition(reduceMotion ? .identity : .opacity)

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, max(proxy.safeAreaInsets.top + 10, 18))
                    .padding(.bottom, max(proxy.safeAreaInsets.bottom + 18, 26))
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    @ViewBuilder
    private var speedPage: some View {
        statusCard
        controls
        settingsCard
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Speed")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(-1.1)
                Text(L10n.text("让每一次滑动都更跟手", "Smoother motion, instantly"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            headerActions

        }
    }


    private var headerActions: some View {
        // iOS 27 currently shows halo/ghost artifacts when an interactive glass
        // circle is nested inside GlassEffectContainer. Keep exactly one glass
        // sampling layer per button and let SpeedPressButtonStyle own interaction.
        HStack(spacing: 8) {
            cacheCleanupButton
            iconButton(
                systemName: isCurrentAppearanceDark ? "sun.max.fill" : "moon.fill",
                accessibilityLabel: L10n.text("切换外观", "Change appearance"),
                action: onToggleAppearanceMode
            )
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    private var pageSwitcher: some View {
        HStack(spacing: 8) {
            pageButton(
                title: "Speed",
                systemName: "bolt.fill",
                page: .speed
            )
            pageButton(
                title: L10n.text("实验室", "Laboratory"),
                systemName: "flask.fill",
                page: .laboratory
            )
        }
        .padding(6)
        .background(SpeedGlassSurface(cornerRadius: 20, isInteractive: false))
    }

    private func pageButton(title: String, systemName: String, page: Page) -> some View {
        let selected = selectedPage == page
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if reduceMotion {
                selectedPage = page
            } else {
                withAnimation(.smooth(duration: 0.22)) {
                    selectedPage = page
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                selected ? Color.blue : Color.clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(SpeedPressButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var laboratoryPage: some View {
        VStack(spacing: 12) {
            SpeedGlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(L10n.text("智能性能引擎", "Smart Performance Governor"), systemImage: "gauge.with.dots.needle.50percent")
                            .font(.headline)
                        Spacer()
                        Text(performanceGovernorSnapshot.policyLabel)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.cyan)
                    }
                    HStack(spacing: 14) {
                        labValue(title: L10n.text("热状态", "Thermal"), value: performanceGovernorSnapshot.thermalLabel)
                        labValue(title: L10n.text("预览", "Preview"), value: "\(Int(performanceGovernorSnapshot.previewHz))Hz")
                        labValue(title: L10n.text("低电量", "Low Power"), value: performanceGovernorSnapshot.isLowPowerModeEnabled ? L10n.text("开", "On") : L10n.text("关", "Off"))
                    }
                }
            }

            SpeedGlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label(L10n.text("刷新驱动", "Refresh driver"), systemImage: "display")
                        .font(.headline)
                    HStack(spacing: 8) {
                        ForEach(RefreshDriverMode.allCases, id: \.self) { mode in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onSetRefreshDriverMode(mode)
                            } label: {
                                Text(mode.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(latencyExperimentState.refreshDriverMode == mode ? Color.white : Color.primary)
                                    .frame(maxWidth: .infinity, minHeight: 38)
                                    .background(latencyExperimentState.refreshDriverMode == mode ? Color.blue : Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            }
                            .buttonStyle(SpeedPressButtonStyle())
                        }
                    }
                    Text(L10n.text("低电量或高温时，UIUpdateLink/Hybrid 会自动降级到稳定 CADisplayLink。", "UIUpdateLink/Hybrid automatically falls back to CADisplayLink under Low Power Mode or high thermal pressure."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SpeedGlassCard {
                VStack(spacing: 0) {
                    laboratoryToggleRow(
                        title: L10n.text("兼容模式 Direct Resize", "Compatibility Direct Resize"),
                        subtitle: L10n.text("实验性使用 VideoCall geometry 直接调整尺寸；关闭时继续使用稳定媒体驱动兼容模式", "Experimentally use direct VideoCall geometry resizing; off keeps the stable media-driven compatibility path"),
                        systemName: "arrow.up.and.down.and.arrow.left.and.right",
                        isOn: latencyExperimentState.directCompatibilityResizeEnabled,
                        onChange: onSetDirectCompatibilityResize
                    )
                    divider
                    laboratoryToggleRow(
                        title: L10n.text("立即呈现", "Immediate presentation"),
                        subtitle: L10n.text("请求 UIUpdateLink 尽快提交当前 UI 更新；高温时自动限制", "Request immediate UI presentation; automatically constrained by thermal policy"),
                        systemName: "rectangle.and.hand.point.up.left.fill",
                        isOn: latencyExperimentState.immediatePresentationEnabled,
                        onChange: onSetImmediatePresentation
                    )
                    divider
                    laboratoryToggleRow(
                        title: L10n.text("连续 UI 更新", "Continuous UI updates"),
                        subtitle: L10n.text("仅实验使用；Governor 会在低电量/发热时阻止持续唤醒", "Experimental only; Governor blocks continuous wakeups under low power or thermal pressure"),
                        systemName: "arrow.triangle.2.circlepath",
                        isOn: latencyExperimentState.continuousUpdatesEnabled,
                        onChange: onSetContinuousUpdates
                    )
                    divider
                    laboratoryToggleRow(
                        title: L10n.text("Apple Pencil 低延迟事件", "Pencil low-latency events"),
                        subtitle: L10n.text("Apple 官方仅对符合条件的 Pencil 事件生效；iPhone 手指触控通常无收益", "Apple limits this to eligible Pencil events; normal iPhone touch typically gains nothing"),
                        systemName: "pencil.tip.crop.circle",
                        isOn: latencyExperimentState.lowLatencyEventDispatchEnabled,
                        onChange: onSetLowLatencyEventDispatch
                    )
                }
            }

            SpeedGlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label(L10n.text("Performance Lab", "Performance Lab"), systemImage: "chart.xyaxis.line")
                        .font(.headline)
                    HStack(spacing: 12) {
                        labValue(title: "P50", value: String(format: "%.1fms", performanceLabSnapshot.p50ApplyMilliseconds))
                        labValue(title: "P95", value: String(format: "%.1fms", performanceLabSnapshot.p95ApplyMilliseconds))
                        labValue(title: L10n.text("命中", "Cache"), value: String(format: "%.0f%%", performanceLabSnapshot.cacheHitRatePercent))
                    }
                    HStack(spacing: 12) {
                        labValue(title: L10n.text("请求", "Requests"), value: "\(performanceLabSnapshot.resizeRequests)")
                        labValue(title: L10n.text("丢弃旧请求", "Stale drops"), value: "\(performanceLabSnapshot.staleRequestsDropped)")
                        labValue(title: L10n.text("自愈", "Healing"), value: "\(performanceLabSnapshot.selfHealingAttempts)")
                    }
                }
            }

            Text(L10n.text(
                "实验功能默认不替换稳定路径。Auto/Governor 会优先保证可用性、响应与温度，再决定是否启用更激进的刷新策略。",
                "Experimental features do not replace the stable path by default. Auto/Governor prioritize reliability, responsiveness, and thermals before enabling aggressive refresh behavior."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func labValue(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.bold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func laboratoryToggleRow(
        title: String,
        subtitle: String,
        systemName: String,
        isOn: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        Toggle(
            isOn: Binding(
                get: { isOn },
                set: { enabled in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onChange(enabled)
                }
            )
        ) {
            HStack(spacing: 13) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.blue)
                    .frame(width: 34, height: 34)
                    .background(Color.blue.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(.blue)
        .padding(.vertical, 12)
    }

    private var statusCard: some View {
        SpeedGlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(presentationState.requestedFrameRate)")
                                .font(.system(size: 58, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(reduceMotion ? .identity : .numericText())
                            Text("Hz")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(L10n.text("目标刷新率", "Target refresh rate"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 12)

                    Image(systemName: presentationState.statusSystemImage)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(isPiPActive ? Color.cyan : Color.secondary)
                        .frame(width: 50, height: 50)
                        .background(.thinMaterial, in: Circle())
                }

                HStack(spacing: 10) {
                    Circle()
                        .fill(isPiPActive ? Color.green : Color.secondary.opacity(0.55))
                        .frame(width: 8, height: 8)
                    Text(localizedStatusTitle)
                        .font(.headline)
                    Spacer()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(localizedStatusTitle), \(presentationState.requestedFrameRate) Hz")
    }

    private var controls: some View {
        // Keep each control on its own glass surface. A single interactive
        // GlassEffectContainer around the whole control stack can retain stale
        // sampling/morph snapshots on iOS 27 when the persistent root view updates,
        // which shows up as duplicated icon/text ghosting in the two small buttons.
        controlsContent
    }

    private var controlsContent: some View {
        VStack(spacing: 12) {
            Button(action: withHaptic(onTogglePiP)) {
                HStack(spacing: 10) {
                    Image(systemName: presentationState.primaryActionSystemImage)
                        .foregroundStyle(Color.cyan)
                        .contentTransition(.symbolEffect(.replace))
                    Text(primaryActionTitle)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                        .opacity(0.68)
                }
                .font(.headline)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(SpeedGlassSurface(cornerRadius: 19, isInteractive: true))
            }
            .buttonStyle(SpeedPressButtonStyle())
            .disabled(!presentationState.allowsPrimaryAction)

            HStack(spacing: 12) {
                secondaryControlButton(
                    title: L10n.text("隐藏到最小", "Hide"),
                    systemName: "eye.slash.fill",
                    enabled: presentationState.allowsHideAction,
                    action: onHidePiP
                )
                secondaryControlButton(
                    title: L10n.text("启动并隐藏", "Start & Hide"),
                    systemName: "play.circle.fill",
                    enabled: presentationState.allowsPrimaryAction || presentationState.allowsHideAction,
                    action: onStartAndHidePiP
                )
            }
        }
    }

    private func secondaryControlButton(
        title: String,
        systemName: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: withHaptic(action)) {
            VStack(spacing: 7) {
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(enabled ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(SpeedGlassSurface(cornerRadius: 18, isInteractive: false))
        }
        .buttonStyle(SpeedPressButtonStyle())
        .disabled(!enabled)
    }

    private var settingsCard: some View {
        SpeedGlassCard {
            VStack(spacing: 0) {
                settingButton(
                    title: L10n.text("悬浮窗样式", "Floating style"),
                    value: L10n.text("轻点切换", "Tap to change"),
                    systemName: "rectangle.compress.vertical",
                    action: onToggleStyle
                )
                divider
                settingButton(
                    title: L10n.text("悬浮窗高度", "PiP height"),
                    value: pipHeight,
                    systemName: "arrow.up.and.down",
                    action: onCustomizeHeight
                )
                divider
                enginePicker
            }
        }
    }

    private var enginePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.text("运行模式", "Engine mode"), systemImage: "cpu")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                engineButton(
                    title: L10n.text("自动", "Auto"),
                    route: .auto
                )
                engineButton(
                    title: L10n.text("标准", "Standard"),
                    route: .videoCall
                )
                engineButton(
                    title: L10n.text("兼容", "Compatible"),
                    route: .playerLayerGenerated
                )
            }
        }
        .padding(.vertical, 15)
    }

    private func engineButton(title: String, route: PiPEngineRoute) -> some View {
        let selected = pipEngineRoute == route
        return Button(action: withHaptic { onSetPiPEngineRoute(route) }) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    selected ? Color.blue : Color.primary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(SpeedPressButtonStyle())
        .disabled(presentationState.activity == .starting || presentationState.activity == .stopping)
    }

    private func settingButton(
        title: String,
        value: String,
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: withHaptic(action)) {
            HStack(spacing: 13) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.blue)
                    .frame(width: 34, height: 34)
                    .background(Color.blue.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 56)
        }
        .buttonStyle(.plain)
    }

    private func iconButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: withHaptic(action)) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(SpeedGlassCircleSurface())
        }
        .buttonStyle(SpeedPressButtonStyle())
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var cacheCleanupButton: some View {
        Button(action: withHaptic(onClearCache)) {
            ZStack {
                Image(systemName: "trash.fill")
                    .font(.system(size: 15, weight: .semibold))
                Image(systemName: "sparkles")
                    .font(.system(size: 8, weight: .bold))
                    .offset(x: 8, y: -8)
            }
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .background(SpeedGlassCircleSurface())
        }
        .buttonStyle(SpeedPressButtonStyle())
        .contentShape(Circle())
        .accessibilityLabel(L10n.text("清理缓存", "Clear cache"))
    }

    private var divider: some View {
        Divider().padding(.leading, 47)
    }

    private var localizedStatusTitle: String {
        switch presentationState.activity {
        case .ready: return L10n.text("已就绪", "Ready")
        case .starting: return L10n.text("正在启动", "Starting")
        case .running, .hidden: return L10n.text("120Hz 已启动", "120 Hz started")
        case .stopping: return L10n.text("正在关闭", "Stopping")
        case .failed: return L10n.text("需要重新尝试", "Try again")
        }
    }

    private var primaryActionTitle: String {
        switch presentationState.activity {
        case .starting:
            return L10n.text("正在启动", "Starting")
        case .stopping:
            return L10n.text("正在关闭", "Stopping")
        case .running, .hidden:
            return L10n.text("关闭 Speed", "Stop Speed")
        case .ready, .failed:
            return L10n.text("启动悬浮窗", "Start PiP")
        }
    }

    private func withHaptic(_ action: @escaping () -> Void) -> () -> Void {
        {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }
    }
}

private struct SpeedBackground: View {
    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
            LinearGradient(
                colors: [Color.cyan.opacity(0.22), Color.blue.opacity(0.10), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct SpeedGlassCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SpeedGlassSurface(cornerRadius: 24, castsShadow: true))
    }
}

/// One glass recipe for cards and actions so adjacent controls never look like
/// unrelated opaque panels.
private struct SpeedGlassSurface: View {
    let cornerRadius: CGFloat
    var isInteractive = false
    var castsShadow = false

    @ViewBuilder
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if isInteractive {
            liquidGlass(shape: shape, interactive: true)
        } else {
            liquidGlass(shape: shape, interactive: false)
        }
    }

    @ViewBuilder
    private func liquidGlass(shape: RoundedRectangle, interactive: Bool) -> some View {
        let surface = shape
            .fill(Color.white.opacity(0.045))
            .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
            .overlay { shape.stroke(.white.opacity(0.28), lineWidth: 0.8) }
        if castsShadow {
            surface.shadow(color: .cyan.opacity(0.10), radius: 18, y: 8)
        } else {
            surface
        }
    }
}

private struct SpeedGlassCircleSurface: View {
    var body: some View {
        let shape = Circle()
        shape
            .fill(Color.white.opacity(0.035))
            .glassEffect(.regular, in: shape)
            .overlay { shape.stroke(.white.opacity(0.22), lineWidth: 0.6) }
    }
}

private struct SpeedPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
