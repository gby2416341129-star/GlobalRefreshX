#!/usr/bin/env python3
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: speed26a2_patch.py <project-root>")

root = Path(sys.argv[1]).resolve()
refresh = root / "pip_swift/pip_swift/RefreshRateController.swift"
text = refresh.read_text()


def replace_once(haystack: str, old: str, new: str, label: str) -> str:
    if old not in haystack:
        raise SystemExit(f"missing patch pattern: {label}")
    return haystack.replace(old, new, 1)

# Keep the stable CADisplayLink cadence improvement from A1.
text = replace_once(
    text,
    """    private var configuredFrameRate: Float = 0
    private(set) var runtimeMode: RefreshRuntimeMode = .videoCall""",
    """    private var configuredFrameRate: Float = 0
    // 2.6 cadence guard: recover from a persistent scheduler downshift without
    // adding timers, logging, allocations, scene walks, or UI work to the hot path.
    private var lastDisplayTimestamp: CFTimeInterval = 0
    private var cadenceSlowStreak = 0
    private var lastCadenceRecoveryTimestamp: CFTimeInterval = 0
    private let cadenceSlowMultiplier: Double = 1.34
    private let cadenceRecoveryCooldown: CFTimeInterval = 0.75
    private(set) var runtimeMode: RefreshRuntimeMode = .videoCall""",
    "cadence state",
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
    "cadence reset",
)

text = replace_once(
    text,
    """    @objc private func step(_ link: CADisplayLink) {
        // Intentionally empty. Any main-thread work here steals from the 8.33 ms budget.
    }""",
    """    @objc private func step(_ link: CADisplayLink) {
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
    "cadence step",
)

# Crash-loop fix: never restore an experimental UIUpdateLink/Hybrid driver on cold launch.
# A previously persisted A1/2.5 value is actively removed before the app continues.
text = replace_once(
    text,
    """    private init() {
        let raw = UserDefaults.standard.string(forKey: driverModeKey)
        driverMode = raw.flatMap(RefreshDriverMode.init(rawValue:)) ?? .cadisplayLink
        NotificationCenter.default.addObserver(""",
    """    private init() {
        driverMode = .cadisplayLink
        UserDefaults.standard.removeObject(forKey: driverModeKey)
        NotificationCenter.default.addObserver(""",
    "cold-launch safe driver",
)

# Lab driver choices are session-only. They may be tested, but can no longer poison the next launch.
text = replace_once(
    text,
    """        driverMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: driverModeKey)
        reconcile()""",
    """        driverMode = mode
        UserDefaults.standard.removeObject(forKey: driverModeKey)
        reconcile()""",
    "ephemeral driver mode",
)

# Deliberately leave the original 2.5 UIUpdateLink(actionHandler:) construction untouched.
# A1's no-handler constructor is not carried into A2 until the device crash is understood.
refresh.write_text(text)

project = root / "pip_swift/pip_swift.xcodeproj/project.pbxproj"
p = project.read_text()
if "MARKETING_VERSION = 2.5.0;" not in p:
    raise SystemExit("missing 2.5 marketing version")
if "CURRENT_PROJECT_VERSION = 2026091002;" not in p:
    raise SystemExit("missing 2.5 build number")
p = p.replace("MARKETING_VERSION = 2.5.0;", "MARKETING_VERSION = 2.6.0;")
p = p.replace("CURRENT_PROJECT_VERSION = 2026091002;", "CURRENT_PROJECT_VERSION = 2026091004;")
project.write_text(p)

verify = root / "scripts/verify_project.sh"
v = verify.read_text()
v = v.replace(
    "check_sh 'Speed version 2.5.0' \"grep -q 'MARKETING_VERSION = 2.5.0' '$PROJECT'\"",
    "check_sh 'Speed version 2.6.0' \"grep -q 'MARKETING_VERSION = 2.6.0' '$PROJECT'\"",
)
v = v.replace(
    "check_sh 'Speed build 2026091002' \"grep -q 'CURRENT_PROJECT_VERSION = 2026091002' '$PROJECT'\"",
    "check_sh 'Speed build 2026091004' \"grep -q 'CURRENT_PROJECT_VERSION = 2026091004' '$PROJECT'\"",
)
old_check = "check_sh 'Standard display link callback stays empty' \"grep -q 'Any main-thread work here steals from the 8.33 ms budget' '$REFRESH'\""
new_checks = "\n".join([
    "check_sh '2.6 cadence guard is bounded' \"grep -q 'cadenceSlowStreak >= 2' '$REFRESH' && grep -q 'cadenceRecoveryCooldown' '$REFRESH'\"",
    "check_sh '2.6 cadence hot path avoids heavyweight calls' \"! sed -n '/@objc private func step/,/^    }/p' '$REFRESH' | grep -Eq 'AppDebugLogger\\.|UserDefaults\\.|connectedScenes|DispatchQueue\\.|Timer\\(' \"",
    "check_sh 'A2 cold launch forces stable CADisplayLink' \"grep -A4 'private init()' '$REFRESH' | grep -q 'driverMode = .cadisplayLink' && grep -A4 'private init()' '$REFRESH' | grep -q 'removeObject(forKey: driverModeKey)'\"",
    "check_sh 'A2 Lab driver is not persisted' \"sed -n '/func setDriverMode/,/^    }/p' '$REFRESH' | grep -q 'removeObject(forKey: driverModeKey)' && ! sed -n '/func setDriverMode/,/^    }/p' '$REFRESH' | grep -q 'UserDefaults.standard.set'\"",
    "check_sh 'A2 restores original UIUpdateLink action-handler construction' \"grep -q 'UIUpdateLink(view: anchorView, actionHandler:' '$REFRESH'\"",
])
if old_check not in v:
    raise SystemExit("missing legacy display-link verification")
v = v.replace(old_check, new_checks, 1)
verify.write_text(v)

print("Speed 2.6 A2 crash-loop recovery patch applied")
