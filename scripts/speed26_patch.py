#!/usr/bin/env python3
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: speed26_patch.py <project-root>")

root = Path(sys.argv[1]).resolve()
refresh = root / "pip_swift/pip_swift/RefreshRateController.swift"
text = refresh.read_text()


def replace_once(haystack: str, old: str, new: str, label: str) -> str:
    if old not in haystack:
        raise SystemExit(f"missing patch pattern: {label}")
    return haystack.replace(old, new, 1)


text = replace_once(
    text,
    """    private var configuredFrameRate: Float = 0
    private(set) var runtimeMode: RefreshRuntimeMode = .videoCall""",
    """    private var configuredFrameRate: Float = 0
    // 2.6 cadence guard: keep the production clock nearly empty, but detect a
    // persistent scheduler downshift and re-assert the already requested range.
    // A two-sample streak rejects isolated hitches; the cooldown prevents a
    // system policy clamp from turning this into a reconfiguration loop.
    private var lastDisplayTimestamp: CFTimeInterval = 0
    private var cadenceSlowStreak = 0
    private var lastCadenceRecoveryTimestamp: CFTimeInterval = 0
    private let cadenceSlowMultiplier: Double = 1.34
    private let cadenceRecoveryCooldown: CFTimeInterval = 0.75
    private(set) var runtimeMode: RefreshRuntimeMode = .videoCall""",
    "refresh state",
)

text = replace_once(
    text,
    """    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        configuredFrameRate = 0
    }""",
    """    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        configuredFrameRate = 0
        lastDisplayTimestamp = 0
        cadenceSlowStreak = 0
        lastCadenceRecoveryTimestamp = 0
    }""",
    "display-link reset",
)

text = replace_once(
    text,
    """        let link = UIUpdateLink(view: anchorView, actionHandler: { _, _ in
            // Deliberately empty: the link expresses a refresh preference without adding per-frame work.
        })""",
    """        // Preference-only link: no empty Swift closure is dispatched every frame.
        let link = UIUpdateLink(view: anchorView)""",
    "production update link",
)

text = replace_once(
    text,
    """    @objc private func step(_ link: CADisplayLink) {
        // Intentionally empty. Any main-thread work here steals from the 8.33 ms budget.
    }""",
    """    @objc private func step(_ link: CADisplayLink) {
        // Keep the hot path tiny: timestamps only, no allocations, logs, scene walks,
        // timers, UserDefaults, or UI mutation. Recover only from a persistent downshift.
        let timestamp = link.timestamp
        defer { lastDisplayTimestamp = timestamp }

        let target = Double(configuredFrameRate)
        guard target >= 100, lastDisplayTimestamp > 0 else { return }

        let expectedInterval = 1.0 / target
        let observedInterval = timestamp - lastDisplayTimestamp
        if observedInterval > expectedInterval * cadenceSlowMultiplier {
            cadenceSlowStreak += 1
        } else {
            cadenceSlowStreak = 0
            return
        }

        guard cadenceSlowStreak >= 2,
              timestamp - lastCadenceRecoveryTimestamp >= cadenceRecoveryCooldown
        else { return }

        configure(link, requested: configuredFrameRate)
        cadenceSlowStreak = 0
        lastCadenceRecoveryTimestamp = timestamp
    }""",
    "display-link cadence guard",
)

text = replace_once(
    text,
    """            let link = UIUpdateLink(view: anchorView, actionHandler: { _, _ in
                // Intentionally empty. The continuous link itself is the experiment.
                // Speed's existing stable CADisplayLink remains responsible for the 120 Hz preference.
            })""",
    """            // Preference-only link: continuous scheduling without an empty callback.
            let link = UIUpdateLink(view: anchorView)""",
    "laboratory update link",
)
refresh.write_text(text)

project = root / "pip_swift/pip_swift.xcodeproj/project.pbxproj"
p = project.read_text()
if "MARKETING_VERSION = 2.5.0;" not in p:
    raise SystemExit("missing 2.5 marketing version")
if "CURRENT_PROJECT_VERSION = 2026091002;" not in p:
    raise SystemExit("missing 2.5 build number")
p = p.replace("MARKETING_VERSION = 2.5.0;", "MARKETING_VERSION = 2.6.0;")
p = p.replace("CURRENT_PROJECT_VERSION = 2026091002;", "CURRENT_PROJECT_VERSION = 2026091003;")
project.write_text(p)

verify = root / "scripts/verify_project.sh"
v = verify.read_text()
v = v.replace(
    "check_sh 'Speed version 2.5.0' \"grep -q 'MARKETING_VERSION = 2.5.0' '$PROJECT'\"",
    "check_sh 'Speed version 2.6.0' \"grep -q 'MARKETING_VERSION = 2.6.0' '$PROJECT'\"",
)
v = v.replace(
    "check_sh 'Speed build 2026091002' \"grep -q 'CURRENT_PROJECT_VERSION = 2026091002' '$PROJECT'\"",
    "check_sh 'Speed build 2026091003' \"grep -q 'CURRENT_PROJECT_VERSION = 2026091003' '$PROJECT'\"",
)
old_check = "check_sh 'Standard display link callback stays empty' \"grep -q 'Any main-thread work here steals from the 8.33 ms budget' '$REFRESH'\""
new_checks = "\n".join([
    "check_sh '2.6 cadence guard is bounded' \"grep -q 'cadenceSlowStreak >= 2' '$REFRESH' && grep -q 'cadenceRecoveryCooldown' '$REFRESH'\"",
    "check_sh '2.6 cadence hot path avoids heavyweight work' \"! sed -n '/@objc private func step/,/^    }/p' '$REFRESH' | grep -Eq 'AppDebugLogger|UserDefaults|connectedScenes|DispatchQueue|Timer'\"",
    "check_sh '2.6 UIUpdateLink avoids empty action callbacks' \"grep -q 'let link = UIUpdateLink(view: anchorView)' '$REFRESH' && ! grep -q 'UIUpdateLink(view: anchorView, actionHandler:' '$REFRESH'\"",
])
if old_check not in v:
    raise SystemExit("missing legacy display-link verification")
v = v.replace(old_check, new_checks, 1)
verify.write_text(v)

print("Speed 2.6 Smoothness Core A1 patch applied")
