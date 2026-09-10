#!/usr/bin/env python3
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit('usage: speed262_patch.py <project-root>')

root = Path(sys.argv[1]).resolve()
vc = root / 'pip_swift/pip_swift/ViewController.swift'
views = root / 'pip_swift/pip_swift/PiPViews.swift'
refresh = root / 'pip_swift/pip_swift/RefreshRateController.swift'
project = root / 'pip_swift/pip_swift.xcodeproj/project.pbxproj'
verify = root / 'scripts/verify_project.sh'


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'missing patch pattern: {label}')
    return text.replace(old, new, 1)

# --- ViewController.swift ---
text = vc.read_text()

# Production Compatibility now uses the same public VideoCall preferredContentSize geometry
# that is already proven to resize correctly on-device. Keep the Compatibility refresh policy
# separate: it still releases Standard's app-level refresh driver. Auto fallback remains on the
# legacy PlayerLayer route so the existing recovery path is not silently changed.
text = replace_once(
    text,
    '''    private var directCompatibilityResizeEnabled: Bool {\n        LatencyExperimentController.shared.state.directCompatibilityResizeEnabled\n    }\n    private var shouldUseDirectCompatibilityVideoCall: Bool {\n        pipEngineRoute == .playerLayerGenerated && directCompatibilityResizeEnabled\n    }\n    private var effectivePiPEngineRoute: PiPEngineRoute {\n        if pipEngineRoute == .auto {\n            return isLegacyPlayerLayerFallbackActive ? .playerLayerGenerated : .videoCall\n        }\n        if shouldUseDirectCompatibilityVideoCall {\n            return .videoCall\n        }\n        return pipEngineRoute\n    }''',
    '''    /// Manual Compatibility uses the VideoCall content source for geometry because\n    /// AVPictureInPictureVideoCallViewController.preferredContentSize is the public API that\n    /// reliably influences PiP aspect ratio/size while PiP is active. Compatibility's refresh\n    /// policy remains separate and still suppresses Standard's app-level hard-max driver.\n    /// Auto fallback intentionally keeps the legacy PlayerLayer route for recovery only.\n    private var shouldUseCompatibilityVideoCallGeometry: Bool {\n        pipEngineRoute == .playerLayerGenerated\n    }\n    private var effectivePiPEngineRoute: PiPEngineRoute {\n        if pipEngineRoute == .auto {\n            return isLegacyPlayerLayerFallbackActive ? .playerLayerGenerated : .videoCall\n        }\n        if shouldUseCompatibilityVideoCallGeometry {\n            return .videoCall\n        }\n        return pipEngineRoute\n    }''',
    'production compatibility geometry backend',
)

# Geometry rules are a user-facing Compatibility policy (1...220pt, integer step), not a
# statement about which AVKit content source is active. This preserves the Compatibility UI
# while its actual PiP controller uses the reliable VideoCall sizing API.
text = replace_once(
    text,
    '''    private var currentGeometryRoute: PiPGeometryController.Route {\n        shouldUsePlayerLayerPiPCompatibility ? .playerLayer : .videoCall\n    }''',
    '''    private var currentGeometryRoute: PiPGeometryController.Route {\n        shouldUseCompatibilityRefreshPolicy ? .playerLayer : .videoCall\n    }''',
    'compatibility geometry metrics independent of backend',
)

# Retire the Lab Direct Resize switch: that working path is now the production Compatibility
# geometry backend. Leaving a second switch would allow UI state to disagree with engine state.
start = text.find('    private func setDirectCompatibilityResize(_ enabled: Bool) {')
if start == -1:
    raise SystemExit('missing setDirectCompatibilityResize')
end_marker = '\n    @objc private func handlePerformanceGovernorDidChange()'
end = text.find(end_marker, start)
if end == -1:
    raise SystemExit('missing direct resize method end marker')
text = text[:start] + text[end+1:]

text = replace_once(
    text,
    '            onSetDirectCompatibilityResize: { [weak self] enabled in self?.setDirectCompatibilityResize(enabled) },\n',
    '',
    'remove retired direct resize view-model callback',
)

# Compatibility copy now describes the actual production split: compatible refresh policy +
# independently resizable VideoCall geometry. No Lab dependency and no claim about media swapping.
text = replace_once(
    text,
    '''            "兼容模式用于处理部分应用在标准模式下出现刷新节奏冲突、滚动或动画不稳定、固定刷新率内容表现异常等情况。开启后 Speed 会改用兼容媒体节奏驱动，并避免与标准模式的应用级刷新请求同时竞争。兼容模式本身即可正常调节悬浮窗高度；实验室中的 Direct Resize 只是可选实验路径，并不是高度调节的前置条件。",\n            "Compatibility mode is for apps that show refresh-cadence conflicts, unstable scrolling or animation, or issues with fixed-refresh content under Standard mode. Speed switches to the compatibility media-cadence path and avoids competing with the Standard app-level refresh request. Floating-window height adjustment works in Compatibility mode itself; Lab Direct Resize is optional and is not required for resizing."''',
    '''            "兼容模式用于处理部分应用在标准模式下出现刷新节奏冲突、滚动或动画不稳定、固定刷新率内容表现异常等情况。开启后 Speed 会停用标准模式的应用级高刷新请求，改用兼容刷新策略，并使用独立的可调悬浮窗几何路径，减少两套刷新请求相互竞争。悬浮窗高度调节已直接内置在兼容模式中，不需要开启实验室开关。",\n            "Compatibility mode is for apps that show refresh-cadence conflicts, unstable scrolling or animation, or issues with fixed-refresh content under Standard mode. Speed disables Standard's app-level high-refresh request, uses the Compatibility refresh policy, and uses an independently resizable PiP geometry path to avoid competing refresh requests. Floating-window height adjustment is built directly into Compatibility mode and requires no Lab switch."''',
    'compatibility production copy',
)

# Compatibility keeps its 1pt geometry language even though the public VideoCall content source
# now performs the actual resize.
text = text.replace(
    '            minimumHintText: shouldUsePlayerLayerPiPCompatibility\n',
    '            minimumHintText: shouldUseCompatibilityRefreshPolicy\n',
    1,
)

# One-tap minimum UI should follow the user-selected mode, while the actual implementation still
# chooses commit-vs-animation by backend. VideoCall Compatibility animates cleanly to 1pt.
text = replace_once(
    text,
    '        let actionTitle = shouldUsePlayerLayerPiPCompatibility ? "一键1pt" : "一键0.1pt"',
    '        let actionTitle = shouldUseCompatibilityRefreshPolicy ? "一键1pt" : "一键0.1pt"',
    'compatibility one-tap label',
)
text = replace_once(
    text,
    '''        showMessage(shouldUsePlayerLayerPiPCompatibility\n            ? L10n.text("已调整到1pt", "Set to 1 pt.")\n            : L10n.text("已调整到0.1pt", "Set to 0.1 pt."))''',
    '''        showMessage(shouldUseCompatibilityRefreshPolicy\n            ? L10n.text("已调整到1pt", "Set to 1 pt.")\n            : L10n.text("已调整到0.1pt", "Set to 0.1 pt."))''',
    'compatibility one-tap message',
)

# Do not apply Standard's "minimum means hidden; restore to 44pt" migration to Compatibility.
# Compatibility's minimum is 1pt and is a valid, intentional geometry.
text = replace_once(
    text,
    '        guard !shouldUsePlayerLayerPiPCompatibility, clampedPiPHeight <= currentGeometryMetrics.minimumHeight + 0.01 else { return }',
    '        guard !shouldUseCompatibilityRefreshPolicy, clampedPiPHeight <= currentGeometryMetrics.minimumHeight + 0.01 else { return }',
    'do not standard-restore compatibility 1pt',
)

# When Compatibility 1pt was used as a transient one-tap state, restore its 22pt default after
# PiP stops even though the production controller is now VideoCall-backed. Legacy auto fallback
# retains its existing PlayerLayer-specific media restoration.
insert_after = '''    private func restorePlayerLayerDefaultHeightAfterStopIfNeeded(reason: String) {\n        guard shouldUsePlayerLayerPiPCompatibility else { return }\n        guard clampedPiPHeight <= currentMinimumPiPHeight + 0.01 else { return }\n\n        pipTasks.cancel(.playerLayerGeometryPreview)\n        pipHeight = playerLayerDefaultPiPHeight\n        isCompactPiPStyle = true\n        if remembersPiPHeight {\n            saveCurrentPiPHeightPreference()\n        }\n        requestPlayerLayerMedia(for: playerLayerDefaultPiPHeight, reason: "关闭后恢复默认尺寸")\n        updateHomeView()\n        AppDebugLogger.log("PlayerLayer restored default height after stop: \\(formattedHeight(playerLayerDefaultPiPHeight)), reason=\\(reason)")\n    }'''
if insert_after not in text:
    raise SystemExit('missing playerLayer restore function')
compat_restore = insert_after + '''\n\n    private func restoreDirectCompatibilityDefaultHeightAfterStopIfNeeded(reason: String) {\n        guard shouldUseCompatibilityRefreshPolicy, !shouldUsePlayerLayerPiPCompatibility else { return }\n        guard clampedPiPHeight <= currentMinimumPiPHeight + 0.01 else { return }\n\n        pipHeight = playerLayerDefaultPiPHeight\n        isCompactPiPStyle = true\n        lastSubmittedPiPSizeInPixels = nil\n        if remembersPiPHeight {\n            saveCurrentPiPHeightPreference()\n        }\n        updateHomeView()\n        AppDebugLogger.log("Compatibility geometry restored default height after stop: \\(formattedHeight(playerLayerDefaultPiPHeight)), reason=\\(reason)")\n    }'''
text = text.replace(insert_after, compat_restore, 1)
text = replace_once(
    text,
    '        restorePlayerLayerDefaultHeightAfterStopIfNeeded(reason: "PiP停止完成")\n',
    '        restorePlayerLayerDefaultHeightAfterStopIfNeeded(reason: "PiP停止完成")\n        restoreDirectCompatibilityDefaultHeightAfterStopIfNeeded(reason: "PiP停止完成")\n',
    'restore direct compatibility transient minimum',
)

vc.write_text(text)

# --- PiPViews.swift ---
ui = views.read_text()
ui = replace_once(ui, '    let onSetDirectCompatibilityResize: (Bool) -> Void\n', '', 'remove direct callback property')
ui = replace_once(ui, '        onSetDirectCompatibilityResize: @escaping (Bool) -> Void,\n', '', 'remove direct callback init arg')
ui = replace_once(ui, '        self.onSetDirectCompatibilityResize = onSetDirectCompatibilityResize\n', '', 'remove direct callback assignment')
ui = replace_once(ui, '    private var onSetDirectCompatibilityResize: (Bool) -> Void { model.onSetDirectCompatibilityResize }\n', '', 'remove direct callback computed property')
row = '''                    laboratoryToggleRow(\n                        title: L10n.text("兼容模式 Direct Resize", "Compatibility Direct Resize"),\n                        subtitle: L10n.text("兼容模式本身已支持高度调节；此开关仅实验性改用 VideoCall geometry，非必需", "Compatibility mode already supports height adjustment; this optional experiment only switches resizing to VideoCall geometry"),\n                        systemName: "arrow.up.and.down.and.arrow.left.and.right",\n                        isOn: latencyExperimentState.directCompatibilityResizeEnabled,\n                        onChange: onSetDirectCompatibilityResize\n                    )\n                    divider\n'''
ui = replace_once(ui, row, '', 'remove retired Direct Resize Lab row')
views.write_text(ui)

# --- RefreshRateController.swift ---
r = refresh.read_text()
r = replace_once(r, '    var directCompatibilityResizeEnabled = false\n', '', 'remove retired direct state')
r = replace_once(r, '            || directCompatibilityResizeEnabled\n', '', 'remove direct from anyPreference')
r = replace_once(r, '            && directCompatibilityResizeEnabled\n', '', 'remove direct from allPreferences')
r = replace_once(r, '    private let directCompatibilityResizeKey = "speed.lab.directCompatibilityResize"\n', '', 'remove direct key property')
r = replace_once(
    r,
    '        state.directCompatibilityResizeEnabled = UserDefaults.standard.bool(forKey: directCompatibilityResizeKey)\n',
    '        UserDefaults.standard.removeObject(forKey: "speed.lab.directCompatibilityResize")\n',
    'clear retired direct preference',
)
setter_start = r.find('    func setDirectCompatibilityResizeEnabled(_ enabled: Bool) {')
if setter_start == -1:
    raise SystemExit('missing direct resize setter in LatencyExperimentController')
setter_end = r.find('\n    func setRefreshDriverMode', setter_start)
if setter_end == -1:
    raise SystemExit('missing direct setter end')
r = r[:setter_start] + r[setter_end+1:]
r = replace_once(r, '        state.directCompatibilityResizeEnabled = enabled\n        UserDefaults.standard.set(enabled, forKey: directCompatibilityResizeKey)\n', '', 'remove direct from setAll')
refresh.write_text(r)

# --- Version ---
p = project.read_text()
if 'MARKETING_VERSION = 2.6.1;' not in p:
    raise SystemExit('missing 2.6.1 marketing version')
if 'CURRENT_PROJECT_VERSION = 2026091005;' not in p:
    raise SystemExit('missing 2.6.1 build number')
p = p.replace('MARKETING_VERSION = 2.6.1;', 'MARKETING_VERSION = 2.6.2;')
p = p.replace('CURRENT_PROJECT_VERSION = 2026091005;', 'CURRENT_PROJECT_VERSION = 2026091006;')
project.write_text(p)

# --- Verification ---
v = verify.read_text()
v = v.replace(
    "check_sh 'Speed version 2.6.1' \"grep -q 'MARKETING_VERSION = 2.6.1' '$PROJECT'\"",
    "check_sh 'Speed version 2.6.2' \"grep -q 'MARKETING_VERSION = 2.6.2' '$PROJECT'\"",
)
v = v.replace(
    "check_sh 'Speed build 2026091005' \"grep -q 'CURRENT_PROJECT_VERSION = 2026091005' '$PROJECT'\"",
    "check_sh 'Speed build 2026091006' \"grep -q 'CURRENT_PROJECT_VERSION = 2026091006' '$PROJECT'\"",
)
old_direct_checks = "\n".join([
    "check_sh 'Direct Compatibility experiment is wired' \"grep -q 'directCompatibilityResizeEnabled' '$VC' && grep -q 'shouldUseDirectCompatibilityVideoCall' '$VC'\"",
    "check_sh 'Direct experiment does not swap active PiP content source' \"grep -q 'Direct Resize will take effect the next time you reopen PiP' '$VC'\"",
    "check_sh 'Compatibility prompt reflects current engine' \"grep -q '兼容模式用于处理部分应用在标准模式下出现刷新节奏冲突' '$VC' && ! grep -q 'b站弹幕' '$VC' && ! grep -q '锁60hz' '$VC'\"",
    "check_sh 'Direct Resize is explicitly optional' \"grep -q '兼容模式本身已支持高度调节' '$APP/PiPViews.swift'\"",
])
new_direct_checks = "\n".join([
    "check_sh 'Manual Compatibility uses resizable VideoCall geometry' \"grep -q 'shouldUseCompatibilityVideoCallGeometry' '$VC' && grep -A12 'private var effectivePiPEngineRoute' '$VC' | grep -q 'if shouldUseCompatibilityVideoCallGeometry' && grep -A2 'if shouldUseCompatibilityVideoCallGeometry' '$VC' | grep -q 'return .videoCall'\"",
    "check_sh 'Auto fallback still retains legacy PlayerLayer recovery route' \"grep -q 'isLegacyPlayerLayerFallbackActive ? .playerLayerGenerated : .videoCall' '$VC'\"",
    "check_sh 'Compatibility geometry keeps 1pt integer policy independent of backend' \"grep -A2 'private var currentGeometryRoute' '$VC' | grep -q 'shouldUseCompatibilityRefreshPolicy ? .playerLayer : .videoCall' && grep -q 'minimumHintText: shouldUseCompatibilityRefreshPolicy' '$VC'\"",
    "check_sh 'Retired Direct Resize Lab dependency is gone' \"! grep -R -q 'directCompatibilityResizeEnabled\\|Compatibility Direct Resize\\|兼容模式 Direct Resize' '$APP' --include='*.swift' && grep -q 'removeObject(forKey: \\\"speed.lab.directCompatibilityResize\\\")' '$REFRESH'\"",
    "check_sh 'Compatibility prompt reflects production geometry path' \"grep -q '悬浮窗高度调节已直接内置在兼容模式中' '$VC' && ! grep -q 'b站弹幕' '$VC' && ! grep -q '锁60hz' '$VC'\"",
    "check_sh 'Compatibility minimum does not trigger Standard 44pt migration' \"grep -A2 'private func restoreMinimumRememberedHeightIfNeeded' '$VC' | grep -q '!shouldUseCompatibilityRefreshPolicy'\"",
    "check_sh 'Compatibility transient 1pt restores to 22pt after stop' \"grep -q 'restoreDirectCompatibilityDefaultHeightAfterStopIfNeeded' '$VC' && grep -A8 'restoreDirectCompatibilityDefaultHeightAfterStopIfNeeded' '$VC' | grep -q 'pipHeight = playerLayerDefaultPiPHeight'\"",
])
if old_direct_checks not in v:
    raise SystemExit('missing old direct verify block')
v = v.replace(old_direct_checks, new_direct_checks, 1)
verify.write_text(v)

print('Speed 2.6.2 Compatibility Geometry Core patch applied')
