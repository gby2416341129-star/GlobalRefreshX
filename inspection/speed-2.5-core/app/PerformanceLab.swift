import Foundation
import QuartzCore
import os

struct PerformanceLabSnapshot: Equatable {
    let resizeRequests: Int
    let mediaApplies: Int
    let staleRequestsDropped: Int
    let cacheHits: Int
    let cacheMisses: Int
    let p50ApplyMilliseconds: Double
    let p95ApplyMilliseconds: Double
    let lastApplyMilliseconds: Double
    let selfHealingAttempts: Int

    var cacheHitRatePercent: Double {
        let total = cacheHits + cacheMisses
        guard total > 0 else { return 0 }
        return Double(cacheHits) / Double(total) * 100
    }
}

enum SpeedPerformanceLab {
    private static let lock = NSLock()
    private static let signposter = OSSignposter(subsystem: "com.isil.speed", category: "Performance")
    private static var resizeRequests = 0
    private static var mediaApplies = 0
    private static var staleRequestsDropped = 0
    private static var cacheHits = 0
    private static var cacheMisses = 0
    private static var applyDurationsMilliseconds: [Double] = []
    private static var selfHealingAttempts = 0
    private static var requestStartedAt: [UInt: CFTimeInterval] = [:]

    static func recordResizeRequest(generation: UInt) {
        lock.lock()
        resizeRequests += 1
        requestStartedAt[generation] = CACurrentMediaTime()
        if requestStartedAt.count > 64 {
            let threshold = generation > 64 ? generation - 64 : 0
            requestStartedAt = requestStartedAt.filter { $0.key >= threshold }
        }
        lock.unlock()
        signposter.emitEvent("CompatibilityResizeRequest")
    }

    static func recordMediaApply(generation: UInt) {
        let now = CACurrentMediaTime()
        lock.lock()
        mediaApplies += 1
        let started = requestStartedAt.removeValue(forKey: generation)
        if let started {
            applyDurationsMilliseconds.append(max(0, (now - started) * 1_000))
            if applyDurationsMilliseconds.count > 120 {
                applyDurationsMilliseconds.removeFirst(applyDurationsMilliseconds.count - 120)
            }
        }
        lock.unlock()
        signposter.emitEvent("CompatibilityResizeApplied")
    }

    static func recordStaleDrop() {
        lock.lock()
        staleRequestsDropped += 1
        lock.unlock()
    }

    static func recordCacheHit() {
        lock.lock(); cacheHits += 1; lock.unlock()
    }

    static func recordCacheMiss() {
        lock.lock(); cacheMisses += 1; lock.unlock()
    }

    static func recordSelfHealingAttempt() {
        lock.lock(); selfHealingAttempts += 1; lock.unlock()
        signposter.emitEvent("PiPSelfHealing")
    }

    static func snapshot() -> PerformanceLabSnapshot {
        lock.lock()
        let samples = applyDurationsMilliseconds.sorted()
        let resizeRequests = resizeRequests
        let mediaApplies = mediaApplies
        let stale = staleRequestsDropped
        let hits = cacheHits
        let misses = cacheMisses
        let healing = selfHealingAttempts
        lock.unlock()

        func percentile(_ p: Double) -> Double {
            guard !samples.isEmpty else { return 0 }
            let index = min(samples.count - 1, max(0, Int((Double(samples.count - 1) * p).rounded())))
            return samples[index]
        }

        return PerformanceLabSnapshot(
            resizeRequests: resizeRequests,
            mediaApplies: mediaApplies,
            staleRequestsDropped: stale,
            cacheHits: hits,
            cacheMisses: misses,
            p50ApplyMilliseconds: percentile(0.50),
            p95ApplyMilliseconds: percentile(0.95),
            lastApplyMilliseconds: samples.last ?? 0,
            selfHealingAttempts: healing
        )
    }
}
