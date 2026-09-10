#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
pass=0
check_sh() {
  local name="$1" expression="$2"
  if bash -c "$expression"; then
    echo "PASS: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name" >&2
    exit 1
  fi
}

PROJECT="pip_swift/pip_swift.xcodeproj/project.pbxproj"
APP="pip_swift/pip_swift"
VC="$APP/ViewController.swift"
REFRESH="$APP/RefreshRateController.swift"
GOVERNOR="$APP/PerformanceGovernor.swift"
LAB="$APP/PerformanceLab.swift"
INTENTS="$APP/SpeedAppIntents.swift"
CONTROLS="pip_swift/SpeedControls/SpeedControls.swift"
CACHE="$APP/DiagnosticsResetManager.swift"

check_sh 'Speed version 2.5.0' "grep -q 'MARKETING_VERSION = 2.5.0' '$PROJECT'"
check_sh 'Speed build 2026091002' "grep -q 'CURRENT_PROJECT_VERSION = 2026091002' '$PROJECT'"
check_sh 'iOS 26 deployment target' "grep -q 'IPHONEOS_DEPLOYMENT_TARGET = 26.0' '$PROJECT'"
check_sh 'Speed identity retained' "grep -q 'PRODUCT_BUNDLE_IDENTIFIER = com.isil.speed' '$PROJECT' && grep -q 'PRODUCT_NAME = Speed' '$PROJECT'"
check_sh 'Release is whole-module optimized' "grep -q 'SWIFT_COMPILATION_MODE = wholemodule' '$PROJECT' && grep -q 'SWIFT_OPTIMIZATION_LEVEL = \"-O\"' '$PROJECT'"
check_sh 'No iOS below 26 availability branches' "! grep -REq '#available\\(iOS (1[0-9]|2[0-5])|@available\\(iOS (1[0-9]|2[0-5])' '$APP' --include='*.swift'"
check_sh 'No UserDefaults synchronize calls' "! grep -R -q '\\.synchronize()' '$APP' --include='*.swift'"

check_sh 'No SnapKit source use' "! grep -R -q 'SnapKit\\|\\.snp\\.' '$APP' --include='*.swift'"
check_sh 'No CocoaPods project integration' "! grep -q 'Pods_pip_swift\\|Pods-pip_swift\\|\\[CP\\]' '$PROJECT'"
check_sh 'No vendored Pods or Podfile' "! test -e pip_swift/Pods && ! test -e pip_swift/Podfile && ! test -e pip_swift/podfile && ! test -e pip_swift/Podfile.lock"
check_sh 'Build script uses xcodeproj directly' "grep -q -- '-project pip_swift.xcodeproj' scripts/build_unsigned_ipa.sh && ! grep -q -- '-workspace' scripts/build_unsigned_ipa.sh"
check_sh 'Unused Main storyboard removed' "! test -e '$APP/Base.lproj/Main.storyboard' && ! grep -q 'Main.storyboard' '$PROJECT'"
check_sh 'Unused AppDesignSystem removed' "! test -e '$APP/AppDesignSystem.swift' && ! grep -q 'AppDesignSystem.swift' '$PROJECT'"

check_sh 'Standard production path retains CADisplayLink driver' "grep -q 'CADisplayLink(target:' '$REFRESH'"
check_sh 'Standard hard-max rate remains pinned' "grep -q 'minimum: requested, maximum: requested, preferred: requested' '$REFRESH'"
check_sh 'Standard display link callback stays empty' "grep -q 'Any main-thread work here steals from the 8.33 ms budget' '$REFRESH'"
check_sh 'Compatibility route releases foreground refresh driver' "grep -q 'runtimeMode == .videoCall' '$REFRESH'"
check_sh 'UIUpdateLink driver is selectable' "grep -q 'enum RefreshDriverMode' '$REFRESH' && grep -q 'case uiUpdateLink' '$REFRESH' && grep -q 'case hybrid' '$REFRESH'"
check_sh 'UIUpdateLink uses fixed target preference' "grep -q 'UIUpdateLink(view: anchorView' '$REFRESH' && grep -q 'preferredFrameRateRange = CAFrameRateRange' '$REFRESH'"
check_sh 'Governor can suppress continuous refresh experiments' "grep -q 'permitsContinuousRefreshExperiment' '$REFRESH' && grep -q 'effectiveMode = .cadisplayLink' '$REFRESH'"
check_sh 'Pencil low-latency remains laboratory-only' "grep -q 'wantsLowLatencyEventDispatch' '$REFRESH' && grep -q 'Laboratory / latency experiments' '$REFRESH'"

check_sh 'Smart performance governor exists' "grep -q 'final class SmartPerformanceGovernor' '$GOVERNOR'"
check_sh 'Governor observes low-power changes' "grep -q 'NSProcessInfoPowerStateDidChange' '$GOVERNOR' && grep -q 'isLowPowerModeEnabled' '$GOVERNOR'"
check_sh 'Governor observes thermal changes' "grep -q 'thermalStateDidChangeNotification' '$GOVERNOR' && grep -q 'case .critical' '$GOVERNOR'"
check_sh 'Governor scales compatibility preview cadence' "grep -q 'snapshot.previewHz' '$VC' && grep -q 'previewHz: 30' '$GOVERNOR' && grep -q 'previewHz: lowPower ? 45 : 60' '$GOVERNOR'"
check_sh 'Governor scales predictive prefetch' "grep -q 'prefetchAhead' '$GOVERNOR' && grep -q 'prefetchBehind' '$GOVERNOR' && grep -q 'permitsSpeculativePrefetch' '$VC'"
check_sh 'Interactive bursts are wired into PiP controls' "grep -q 'beginInteractiveBurst()' '$VC' && grep -q 'endInteractiveBurst' '$VC'"

check_sh 'Auto engine route exists' "grep -q 'case auto' '$VC' && grep -q 'isLegacyPlayerLayerFallbackActive ? .playerLayerGenerated : .videoCall' '$VC'"
check_sh 'Auto falls back after Standard failure' "grep -q 'activateAutoCompatibilityFallbackIfNeeded' '$VC' && grep -q 'Auto engine falling back to PlayerLayer' '$VC'"
check_sh 'Auto fallback retries are bounded' "grep -q 'attempt <= 12' '$VC'"
check_sh 'Direct Compatibility experiment is wired' "grep -q 'directCompatibilityResizeEnabled' '$VC' && grep -q 'shouldUseDirectCompatibilityVideoCall' '$VC'"
check_sh 'Direct experiment does not swap active PiP content source' "grep -q 'Direct Resize will take effect the next time you reopen PiP' '$VC'"

check_sh 'Compatibility preview is governor-throttled, not debounced' "grep -q 'playerLayerPreviewSubmissionInterval: CFTimeInterval' '$VC' && grep -q 'This is a throttle, not a debounce' '$VC'"
check_sh 'Compatibility uses directional predictive prefetch' "grep -q 'prefetchPlayerLayerBackingVideos' '$VC' && grep -q 'policy.prefetchAhead' '$VC'"
check_sh 'No 220-height bulk prewarm loop' "! grep -q 'for height in 1...220' '$VC'"
check_sh 'Prefetch work is coalesced to one worker' "grep -q 'pendingPrefetchHeights' '$VC' && grep -q 'isPrefetchWorkerScheduled' '$VC'"
check_sh 'Interactive compact media lane is serial user-initiated' "grep -A4 'interactiveGenerationQueue = DispatchQueue' '$VC' | grep -q 'qos: .userInitiated' && ! grep -A5 'interactiveGenerationQueue = DispatchQueue' '$VC' | grep -q 'attributes: .concurrent'"
check_sh 'Only newest compatibility generation may apply' "grep -q 'generation == self.playerLayerMediaRequestGeneration' '$VC' && grep -q 'abs(self.clampedPiPHeight - requestedHeight)' '$VC'"
check_sh 'Same-height materialization is coalesced' "grep -q 'inFlightMaterializations' '$VC' && grep -q 'DispatchGroup' '$VC'"
check_sh 'Compact decode avoids Data subdata copy' "grep -q 'sourceBase.advanced(by: 4)' '$VC' && ! sed -n '/materializeCompressedBundledPlayerLayerBackingVideoIfAvailable/,/static func cachedAsset/p' '$VC' | grep -q 'subdata'"
check_sh 'Compact write avoids nested Data atomic write' "! sed -n '/materializeCompressedBundledPlayerLayerBackingVideoIfAvailable/,/static func cachedAsset/p' '$VC' | grep -q 'write(to: temporaryURL, options: .atomic)'"
check_sh 'AVURLAsset reuse cache enabled' "grep -q 'playerLayerAssetCache' '$VC' && grep -q 'cachedAsset(for url: URL)' '$VC'"
check_sh 'Display context caches registered UIWindowScene' "grep -q 'private static weak var registeredWindowScene' '$REFRESH'"
check_sh 'SceneDelegate registers display context' "grep -q 'AppDisplayContext.register(windowScene)' '$APP/SceneDelegate.swift'"
check_sh 'Local compatibility player disables startup waiting' "grep -q 'automaticallyWaitsToMinimizeStalling = false' '$VC'"
check_sh 'Release cannot enter 1800-frame compatibility fallback' "sed -n '/static func makePlayerLayerBackingVideoIfNeeded/,/static func makeBackingVideo/p' '$VC' | grep -q '#if DEBUG' && sed -n '/static func makePlayerLayerBackingVideoIfNeeded/,/static func makeBackingVideo/p' '$VC' | grep -q 'throw GenerationError.invalidBundledMedia'"

check_sh 'PiP self-healing is instrumented' "grep -q 'rebuildCurrentPlayerLayerItemForSelfHealing' '$VC' && grep -q 'recordSelfHealingAttempt' '$VC'"
check_sh 'Escalated self-healing is bounded' "grep -q 'recentPlayerLayerRecoveryCount >= 3' '$VC' && grep -q 'lastPlayerLayerRecoveryBurstStartedAt' '$VC'"
check_sh 'Performance Lab collects resize latency' "grep -q 'recordResizeRequest' '$LAB' && grep -q 'p95ApplyMilliseconds' '$LAB' && grep -q 'CACurrentMediaTime' '$LAB'"
check_sh 'Performance Lab uses signposts' "grep -q 'OSSignposter' '$LAB' && grep -q 'CompatibilityResizeApplied' '$LAB'"
check_sh 'Performance Lab remains bounded in memory' "grep -q 'count > 120' '$LAB' && grep -q 'count > 64' '$LAB'"

check_sh 'Smart height learning exists' "grep -q 'SmartHeightLearningStore' '$GOVERNOR' && grep -q 'counts.v2' '$GOVERNOR'"
check_sh 'Height learning is route-specific' "grep -q 'routePrefix = isCompatibility' '$GOVERNOR' && grep -q 'CGFloat(\$0.unit) / 10' '$GOVERNOR'"
check_sh 'Favorite height profiles exist' "grep -q 'enum HeightProfileStore' '$GOVERNOR' && grep -q 'toggleFavorite' '$GOVERNOR' && grep -q 'setDefault' '$GOVERNOR'"
check_sh 'Height editor exposes favorites and custom default' "grep -q '收藏当前尺寸' '$VC' && grep -q 'handlePresetLongPress' '$VC' && grep -q 'HeightProfileStore.defaultHeight' '$VC'"

check_sh 'Control Center extension target exists' "grep -q 'SpeedControls.appex' '$PROJECT' && grep -q 'productType = \"com.apple.product-type.app-extension\"' '$PROJECT'"
check_sh 'Control extension has matching bundle prefix' "grep -q 'PRODUCT_BUNDLE_IDENTIFIER = com.isil.speed.controls' '$PROJECT'"
check_sh 'Control extension is embedded by app' "grep -q 'SpeedControls.appex in Embed App Extensions' '$PROJECT' && grep -q 'PBXTargetDependency' '$PROJECT'"
check_sh 'Shared OpenIntent has dual target membership' "grep -q 'SpeedAppIntents.swift' '$PROJECT' && grep -q 'struct SpeedLaunchIntent: OpenIntent' '$APP/SpeedAppIntents.swift' && grep -q 'func perform() async throws' '$APP/SpeedAppIntents.swift'"
check_sh 'Three system controls exist' "grep -q 'OpenSpeedControl' '$CONTROLS' && grep -q 'StartSpeedControl' '$CONTROLS' && grep -q 'StartAndHideSpeedControl' '$CONTROLS'"
check_sh 'OpenIntent router handles system launch intent' "grep -q 'SpeedLaunchActionRouter.didSubmitNotification' '$APP/SceneDelegate.swift' && grep -q 'restorePending(target)' '$APP/SceneDelegate.swift' && ! grep -q 'UISceneAppIntent\|AppIntentSceneDelegate' '$APP/SceneDelegate.swift'"

check_sh 'Generated media cache uses memory access order' "grep -q 'lastAccessByPath' '$CACHE' && grep -q 'accessSequence' '$CACHE'"
check_sh 'Cache hits do not write modification dates' "! grep -q 'setAttributes.*modificationDate\\|modificationDate.*setAttributes' '$CACHE'"
check_sh 'Generated cache bounded to 32 files / 24 MiB' "grep -q 'maximumFileCount = 32' '$CACHE' && grep -q 'maximumTotalBytes = 24 \* 1024 \* 1024' '$CACHE'"
check_sh 'Launch cache maintenance is serialized' "grep -A30 'static func cleanOnLaunch' '$CACHE' | grep -q 'GeneratedPiPVideoCache.prepareForLaunch()' && ! grep -q 'GeneratedPiPVideoCache.prepareForLaunch()' '$APP/AppDelegate.swift'"

check_sh 'SwiftUI home uses Observation' "grep -q '^import Observation' '$APP/PiPViews.swift' && grep -q '@Observable' '$APP/PiPViews.swift' && ! grep -q 'ObservableObjectPublisher\\|objectWillChange' '$APP/PiPViews.swift'"
check_sh 'Liquid Glass has no pre-iOS26 fallback' "grep -q 'UIGlassEffect' '$VC' && ! grep -REq '#available\\(iOS (1[0-9]|2[0-5])' '$APP/PiPViews.swift' '$APP/AdaptiveSheetPresentation.swift' '$VC'"
check_sh 'No network polling' "! grep -R -q -E 'URLSession|NWPathMonitor|NetworkTrafficSample' '$APP' --include='*.swift'"
check_sh 'No forced Core Animation flush' "! grep -R -q 'CATransaction.flush' '$APP' --include='*.swift'"
check_sh 'Idle timer never forced on' "! grep -R -q 'isIdleTimerDisabled = true' '$APP' --include='*.swift'"
check_sh 'Compatibility media bank complete' "find '$APP/CompatibilityMedia' -type f -name 'h*.mov' | grep -c . | grep -qx '3' && find '$APP/CompatibilityMedia' -type f -name 'h*.spm' | grep -c . | grep -qx '217'"
check_sh 'Three hot compatibility MOVs retained' "test -f '$APP/CompatibilityMedia/h001.mov' && test -f '$APP/CompatibilityMedia/h022.mov' && test -f '$APP/CompatibilityMedia/h120.mov'"
check_sh 'Compatibility compact decoder remains off-main' "grep -q 'COMPRESSION_ZLIB' '$VC' && grep -q 'generationQueue.async' '$VC' && grep -q 'interactiveGenerationQueue.async' '$VC'"
check_sh 'Player KVO is reused across item swaps' "grep -q 'if playerLayerTimeControlObserver == nil' '$VC'"
check_sh 'PiP source geometry uses native NSLayoutConstraint' "grep -q 'installCenteredPiPSourceConstraints' '$VC' && grep -q 'pipSourceWidthConstraint.constant' '$VC'"
check_sh 'Project file parses' "plutil -lint '$PROJECT' >/dev/null"

printf 'Verification passed: %d checks\n' "$pass"
