#!/usr/bin/env python3
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit('usage: speed261_patch.py <project-root>')

root = Path(sys.argv[1]).resolve()
vc = root / 'pip_swift/pip_swift/ViewController.swift'
views = root / 'pip_swift/pip_swift/PiPViews.swift'
project = root / 'pip_swift/pip_swift.xcodeproj/project.pbxproj'
verify = root / 'scripts/verify_project.sh'


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'missing patch pattern: {label}')
    return text.replace(old, new, 1)

# --- ViewController.swift ---
text = vc.read_text()

# Compatibility live-resize state. This restores monotonic preview progress without
# bringing back the old 220-full-MOV bundle; current compact media remains 3 MOV + 217 SPM.
text = replace_once(
    text,
    '    private var playerLayerMediaRequestGeneration: UInt = 0\n    private var pendingPlayerLayerPreviewHeight: CGFloat?',
    '    private var playerLayerMediaRequestGeneration: UInt = 0\n    private var lastAppliedPlayerLayerMediaRequestGeneration: UInt = 0\n    private var pendingPlayerLayerPreviewHeight: CGFloat?',
    'last applied compatibility generation',
)

# Bound live compatibility preview to 45 Hz. This is only the height editor path;
# it does not cap Speed's 120 Hz refresh preference. The compact media lane remains
# responsive while avoiding a 60 Hz burst of decode / file-I/O during slider drags.
text = replace_once(
    text,
    '''    private var playerLayerPreviewSubmissionInterval: CFTimeInterval {\n        1.0 / max(30.0, SmartPerformanceGovernor.shared.snapshot.previewHz)\n    }''',
    '''    private var playerLayerPreviewSubmissionInterval: CFTimeInterval {\n        let requested = SmartPerformanceGovernor.shared.snapshot.previewHz\n        let bounded = min(45.0, max(30.0, requested))\n        return 1.0 / bounded\n    }''',
    'bounded compatibility preview cadence',
)

# Rewrite the outdated Compatibility prompt so it describes the current architecture.
text = replace_once(
    text,
    '''        let message = L10n.text(\n            "请确认默认方案解锁120后会导致你日常的b站弹幕以及锁60hz的游戏一顿一顿，可以通过切换新方案解决，但是无法完全隐藏悬浮窗，没有这两个需求就使用默认方案即可",\n            "Please confirm that the default route causes your usual Bilibili danmaku or games locked to 60 Hz to stutter after unlocking 120 Hz. Switching to the new route may solve this, but it cannot fully hide the floating window. If you do not need these fixes, keep using the default route."\n        )\n        let alert = UIAlertController(\n            title: L10n.text("确认切换新方案", "Confirm New Route"),\n            message: message,\n            preferredStyle: .alert\n        )\n        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))\n        alert.addAction(UIAlertAction(title: L10n.text("确认切换", "Switch"), style: .default) { _ in''',
    '''        let message = L10n.text(\n            "兼容模式用于处理部分应用在标准模式下出现刷新节奏冲突、滚动或动画不稳定、固定刷新率内容表现异常等情况。开启后 Speed 会改用兼容媒体节奏驱动，并避免与标准模式的应用级刷新请求同时竞争。兼容模式本身即可正常调节悬浮窗高度；实验室中的 Direct Resize 只是可选实验路径，并不是高度调节的前置条件。",\n            "Compatibility mode is for apps that show refresh-cadence conflicts, unstable scrolling or animation, or issues with fixed-refresh content under Standard mode. Speed switches to the compatibility media-cadence path and avoids competing with the Standard app-level refresh request. Floating-window height adjustment works in Compatibility mode itself; Lab Direct Resize is optional and is not required for resizing."\n        )\n        let alert = UIAlertController(\n            title: L10n.text("切换到兼容模式", "Switch to Compatibility Mode"),\n            message: message,\n            preferredStyle: .alert\n        )\n        alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel))\n        alert.addAction(UIAlertAction(title: L10n.text("切换到兼容模式", "Switch to Compatibility"), style: .default) { _ in''',
    'compatibility confirmation copy',
)

# Remove the visible PiP text completely. Keep the black surface itself because it is
# part of the existing VideoCall PiP presentation and does not add per-frame work.
text = replace_once(
    text,
    '''    private var originalPiPText: String {\n        L10n.text("120Hz 已启动", "120 Hz started")\n    }\n''',
    '',
    'remove legacy PiP text property',
)
text = replace_once(
    text,
    '        textView.text = originalPiPText',
    '        textView.text = ""',
    'blank visible PiP text',
)
text = replace_once(
    text,
    '        let videoText = shouldRenderClockMode ? "" : L10n.text("120Hz 已启动", "120 Hz started")',
    '        let videoText = ""',
    'blank generated backing video text',
)

# Restore live Compatibility resizing. The 2.5 newest-only apply rule can starve a
# continuously moving slider because each compact-media completion becomes stale before
# it reaches AVPlayer. During a drag we accept completed generations in monotonically newer
# order; final commit still converges only to the exact selected height.
text = replace_once(
    text,
    '''        if let targetURL = PlaceholderVideoFactory.resolvedPlayerLayerBackingVideoURL(forPointHeight: requestedHeight),\n           let currentURL = (player.currentItem?.asset as? AVURLAsset)?.url,\n           currentURL == targetURL {\n            if !isPreviewingPiPHeight, !targetURL.path.contains("/CompatibilityMedia/") {\n                GeneratedPiPVideoCache.trim(excluding: [targetURL])\n            }\n            return\n        }''',
    '''        if let targetURL = PlaceholderVideoFactory.resolvedPlayerLayerBackingVideoURL(forPointHeight: requestedHeight),\n           let currentURL = (player.currentItem?.asset as? AVURLAsset)?.url,\n           currentURL == targetURL {\n            lastAppliedPlayerLayerMediaRequestGeneration = generation\n            if !isPreviewingPiPHeight, !targetURL.path.contains("/CompatibilityMedia/") {\n                GeneratedPiPVideoCache.trim(excluding: [targetURL])\n            }\n            return\n        }''',
    'same-height generation progress',
)
text = replace_once(
    text,
    '''                // Never make the system PiP chase obsolete slider positions. Older decode\n                // work may finish and populate cache, but only the latest request whose height\n                // still matches the UI is allowed to touch AVPlayer.\n                guard generation == self.playerLayerMediaRequestGeneration else {\n                    SpeedPerformanceLab.recordStaleDrop()\n                    return\n                }\n                guard abs(self.clampedPiPHeight - requestedHeight) < 0.01 else {\n                    SpeedPerformanceLab.recordStaleDrop()\n                    return\n                }\n\n                let item = AVPlayerItem(asset: PlaceholderVideoFactory.cachedAsset(for: url))''',
    '''                // During a continuous drag, accepting only the exact newest request can\n                // starve AVPlayer: a later slider event often arrives before the tiny compact\n                // media decode completes. Let completed previews advance monotonically so the\n                // PiP visibly follows the slider, while the final commit still converges exactly.\n                let isLatestRequest = generation == self.playerLayerMediaRequestGeneration\n                if !isLatestRequest {\n                    guard self.isPreviewingPiPHeight,\n                          generation > self.lastAppliedPlayerLayerMediaRequestGeneration else {\n                        SpeedPerformanceLab.recordStaleDrop()\n                        return\n                    }\n                } else if !self.isPreviewingPiPHeight {\n                    guard abs(self.clampedPiPHeight - requestedHeight) < 0.01 else {\n                        SpeedPerformanceLab.recordStaleDrop()\n                        return\n                    }\n                }\n\n                self.lastAppliedPlayerLayerMediaRequestGeneration = generation\n                let item = AVPlayerItem(asset: PlaceholderVideoFactory.cachedAsset(for: url))''',
    'monotonic compatibility preview apply',
)

# The serial user-initiated lane is intentionally retained. Do not discard queued compact
# requests before their tiny decode: completion-side monotonic filtering is what bounds stale
# application. Expensive DEBUG H.264 fallback remains cancellation-aware.
text = replace_once(
    text,
    '''        interactiveGenerationQueue.async {\n            // Drop superseded work before it touches mapped data or disk. If a tiny decode\n            // has already started, materialization itself completes atomically and becomes\n            // useful cache for a later reversal.\n            guard isInteractiveGenerationCurrent(requestGeneration) else { return }\n            do {\n                if let compactURL = try materializeCompressedBundledPlayerLayerBackingVideoIfAvailable(\n                    forPointHeight: height,\n                    shouldContinue: { true }\n                ) {\n                    _ = cachedAsset(for: compactURL)\n                    guard isInteractiveGenerationCurrent(requestGeneration) else { return }\n                    completion(compactURL)\n                    return\n                }\n            } catch {''',
    '''        interactiveGenerationQueue.async {\n            // Compact resources are tiny and this queue is serial. Finish each already-throttled\n            // compact request, then let the caller apply only monotonically newer previews. This\n            // avoids the newest-only starvation bug without spawning concurrent decode bursts.\n            do {\n                if let compactURL = try materializeCompressedBundledPlayerLayerBackingVideoIfAvailable(\n                    forPointHeight: height,\n                    shouldContinue: { true }\n                ) {\n                    _ = cachedAsset(for: compactURL)\n                    completion(compactURL)\n                    return\n                }\n            } catch {''',
    'do not pre-drop compact interactive requests',
)

vc.write_text(text)

# --- PiPViews.swift ---
ui = views.read_text()
ui = replace_once(
    ui,
    'subtitle: L10n.text("实验性使用 VideoCall geometry 直接调整尺寸；关闭时继续使用稳定媒体驱动兼容模式", "Experimentally use direct VideoCall geometry resizing; off keeps the stable media-driven compatibility path"),',
    'subtitle: L10n.text("兼容模式本身已支持高度调节；此开关仅实验性改用 VideoCall geometry，非必需", "Compatibility mode already supports height adjustment; this optional experiment only switches resizing to VideoCall geometry"),',
    'Direct Resize optional copy',
)
views.write_text(ui)

# --- Version ---
p = project.read_text()
if 'MARKETING_VERSION = 2.6.0;' not in p:
    raise SystemExit('missing 2.6.0 marketing version')
if 'CURRENT_PROJECT_VERSION = 2026091004;' not in p:
    raise SystemExit('missing A2 build number')
p = p.replace('MARKETING_VERSION = 2.6.0;', 'MARKETING_VERSION = 2.6.1;')
p = p.replace('CURRENT_PROJECT_VERSION = 2026091004;', 'CURRENT_PROJECT_VERSION = 2026091005;')
project.write_text(p)

# --- Verification ---
v = verify.read_text()
v = v.replace(
    "check_sh 'Speed version 2.6.0' \"grep -q 'MARKETING_VERSION = 2.6.0' '$PROJECT'\"",
    "check_sh 'Speed version 2.6.1' \"grep -q 'MARKETING_VERSION = 2.6.1' '$PROJECT'\"",
)
v = v.replace(
    "check_sh 'Speed build 2026091004' \"grep -q 'CURRENT_PROJECT_VERSION = 2026091004' '$PROJECT'\"",
    "check_sh 'Speed build 2026091005' \"grep -q 'CURRENT_PROJECT_VERSION = 2026091005' '$PROJECT'\"",
)
v = v.replace(
    "check_sh 'Only newest compatibility generation may apply' \"grep -q 'generation == self.playerLayerMediaRequestGeneration' '$VC' && grep -q 'abs(self.clampedPiPHeight - requestedHeight)' '$VC'\"",
    "check_sh 'Compatibility live resize advances completed previews monotonically' \"grep -q 'lastAppliedPlayerLayerMediaRequestGeneration' '$VC' && grep -q 'generation > self.lastAppliedPlayerLayerMediaRequestGeneration' '$VC' && grep -q 'let isLatestRequest = generation == self.playerLayerMediaRequestGeneration' '$VC'\"\ncheck_sh 'Compatibility final commit still converges exactly' \"grep -A22 'let isLatestRequest = generation == self.playerLayerMediaRequestGeneration' '$VC' | grep -q 'abs(self.clampedPiPHeight - requestedHeight)'\"\ncheck_sh 'Compatibility slider decode lane remains serial and bounded' \"grep -A4 'interactiveGenerationQueue = DispatchQueue' '$VC' | grep -q 'qos: .userInitiated' && ! grep -A5 'interactiveGenerationQueue = DispatchQueue' '$VC' | grep -q 'attributes: .concurrent' && grep -q 'let bounded = min(45.0, max(30.0, requested))' '$VC'\"",
)
insert_after = "check_sh 'Direct experiment does not swap active PiP content source' \"grep -q 'Direct Resize will take effect the next time you reopen PiP' '$VC'\""
extra = "\n".join([
    "check_sh 'Compatibility prompt reflects current engine' \"grep -q '兼容模式用于处理部分应用在标准模式下出现刷新节奏冲突' '$VC' && ! grep -q 'b站弹幕' '$VC' && ! grep -q '锁60hz' '$VC'\"",
    "check_sh 'Direct Resize is explicitly optional' \"grep -q '兼容模式本身已支持高度调节' '$APP/PiPViews.swift'\"",
    "check_sh 'Visible PiP legacy 120Hz text removed' \"! grep -q '120Hz 已启动' '$VC' && grep -q 'textView.text = \\\"\\\"' '$VC' && grep -q 'let videoText = \\\"\\\"' '$VC'\"",
])
if extra.split('\n')[0] not in v:
    if insert_after not in v:
        raise SystemExit('missing direct experiment verification insertion point')
    v = v.replace(insert_after, insert_after + '\n' + extra, 1)
verify.write_text(v)

print('Speed 2.6.1 Compatibility Refinement patch applied')
