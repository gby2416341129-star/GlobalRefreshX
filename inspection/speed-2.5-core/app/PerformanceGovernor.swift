import Foundation
import UIKit

struct PerformanceGovernorSnapshot: Equatable {
    let isLowPowerModeEnabled: Bool
    let thermalState: ProcessInfo.ThermalState
    let interactionActive: Bool
    let previewHz: Double
    let prefetchAhead: Int
    let prefetchBehind: Int
    let neutralPrefetchRadius: Int
    let permitsContinuousRefreshExperiment: Bool
    let permitsSpeculativePrefetch: Bool

    var thermalLabel: String {
        switch thermalState {
        case .nominal: return L10n.text("正常", "Nominal")
        case .fair: return L10n.text("偏热", "Fair")
        case .serious: return L10n.text("较热", "Serious")
        case .critical: return L10n.text("过热", "Critical")
        @unknown default: return L10n.text("未知", "Unknown")
        }
    }

    var policyLabel: String {
        if thermalState == .critical { return L10n.text("保护", "Protect") }
        if thermalState == .serious || isLowPowerModeEnabled { return L10n.text("节能", "Efficiency") }
        if interactionActive { return L10n.text("极速响应", "Burst") }
        return L10n.text("智能", "Smart")
    }
}

@MainActor
final class SmartPerformanceGovernor {
    static let shared = SmartPerformanceGovernor()
    static let didChangeNotification = Notification.Name("speed.performanceGovernorDidChange")

    private(set) var snapshot: PerformanceGovernorSnapshot
    private var interactionReleaseWorkItem: DispatchWorkItem?

    private init() {
        snapshot = Self.makeSnapshot(interactionActive: false)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePowerStateChanged),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func beginInteractiveBurst() {
        interactionReleaseWorkItem?.cancel()
        interactionReleaseWorkItem = nil
        publishIfChanged(Self.makeSnapshot(interactionActive: true))
    }

    func endInteractiveBurst(after delay: TimeInterval = 0.30) {
        interactionReleaseWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.interactionReleaseWorkItem = nil
            self.publishIfChanged(Self.makeSnapshot(interactionActive: false))
        }
        interactionReleaseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: work)
    }

    func refresh() {
        publishIfChanged(Self.makeSnapshot(interactionActive: snapshot.interactionActive))
    }

    @objc private func handlePowerStateChanged() {
        refresh()
    }

    @objc private func handleThermalStateChanged() {
        refresh()
    }

    private func publishIfChanged(_ next: PerformanceGovernorSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private static func makeSnapshot(interactionActive: Bool) -> PerformanceGovernorSnapshot {
        let processInfo = ProcessInfo.processInfo
        let lowPower = processInfo.isLowPowerModeEnabled
        let thermal = processInfo.thermalState

        switch thermal {
        case .critical:
            return PerformanceGovernorSnapshot(
                isLowPowerModeEnabled: lowPower,
                thermalState: thermal,
                interactionActive: interactionActive,
                previewHz: 30,
                prefetchAhead: 0,
                prefetchBehind: 0,
                neutralPrefetchRadius: 0,
                permitsContinuousRefreshExperiment: false,
                permitsSpeculativePrefetch: false
            )
        case .serious:
            return PerformanceGovernorSnapshot(
                isLowPowerModeEnabled: lowPower,
                thermalState: thermal,
                interactionActive: interactionActive,
                previewHz: 40,
                prefetchAhead: interactionActive ? 2 : 0,
                prefetchBehind: 1,
                neutralPrefetchRadius: 1,
                permitsContinuousRefreshExperiment: false,
                permitsSpeculativePrefetch: interactionActive
            )
        case .fair:
            return PerformanceGovernorSnapshot(
                isLowPowerModeEnabled: lowPower,
                thermalState: thermal,
                interactionActive: interactionActive,
                previewHz: lowPower ? 45 : 60,
                prefetchAhead: interactionActive ? (lowPower ? 4 : 8) : 2,
                prefetchBehind: lowPower ? 1 : 3,
                neutralPrefetchRadius: lowPower ? 2 : 4,
                permitsContinuousRefreshExperiment: !lowPower,
                permitsSpeculativePrefetch: true
            )
        case .nominal:
            return PerformanceGovernorSnapshot(
                isLowPowerModeEnabled: lowPower,
                thermalState: thermal,
                interactionActive: interactionActive,
                previewHz: lowPower ? 45 : 60,
                prefetchAhead: interactionActive ? (lowPower ? 5 : 12) : 3,
                prefetchBehind: lowPower ? 2 : 4,
                neutralPrefetchRadius: lowPower ? 3 : 6,
                permitsContinuousRefreshExperiment: !lowPower,
                permitsSpeculativePrefetch: true
            )
        @unknown default:
            return PerformanceGovernorSnapshot(
                isLowPowerModeEnabled: lowPower,
                thermalState: thermal,
                interactionActive: interactionActive,
                previewHz: lowPower ? 45 : 60,
                prefetchAhead: interactionActive ? 5 : 2,
                prefetchBehind: 2,
                neutralPrefetchRadius: 3,
                permitsContinuousRefreshExperiment: !lowPower,
                permitsSpeculativePrefetch: true
            )
        }
    }
}

struct HeightLearningSnapshot: Equatable {
    let preferredHeights: [Int]
}

enum SmartHeightLearningStore {
    private static let countsKey = "speed.smartHeightLearning.counts.v2"
    private static let maxLearnedEntries = 48

    static func record(height: CGFloat, isCompatibility: Bool) {
        let routePrefix = isCompatibility ? "c" : "s"
        let storedUnit: Int
        if isCompatibility {
            storedUnit = min(max(1, Int(height.rounded())), 220)
        } else {
            storedUnit = min(max(1, Int((height * 10).rounded())), 2_200)
        }
        let key = "\(routePrefix):\(storedUnit)"
        var counts = UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
        counts[key, default: 0] += 1

        if counts.count > maxLearnedEntries {
            let sorted = counts.sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            var trimmedCounts: [String: Int] = [:]
  for entry in sorted.prefix(maxLearnedEntries) {
      trimmedCounts[entry.key] = entry.value
  }
  counts = trimmedCounts
        }
        UserDefaults.standard.set(counts, forKey: countsKey)
    }

    static func preferredHeights(isCompatibility: Bool, limit: Int = 3) -> [CGFloat] {
        let routePrefix = isCompatibility ? "c:" : "s:"
        let counts = UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
        return counts
            .compactMap { key, count -> (unit: Int, count: Int)? in
                guard key.hasPrefix(routePrefix), let unit = Int(key.dropFirst(2)) else { return nil }
                return (unit, count)
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.unit < rhs.unit }
                return lhs.count > rhs.count
            }
            .prefix(max(0, limit))
            .map { isCompatibility ? CGFloat($0.unit) : CGFloat($0.unit) / 10 }
    }
}

enum HeightProfileStore {
    private static let compatibilityFavoritesKey = "speed.heightProfiles.compatibility.favorites"
    private static let standardFavoritesKey = "speed.heightProfiles.standard.favorites"
    private static let compatibilityDefaultKey = "speed.heightProfiles.compatibility.default"
    private static let standardDefaultKey = "speed.heightProfiles.standard.default"
    private static let maximumFavorites = 5

    static func favorites(isCompatibility: Bool) -> [CGFloat] {
        let key = isCompatibility ? compatibilityFavoritesKey : standardFavoritesKey
        let values = UserDefaults.standard.array(forKey: key) as? [Double] ?? []
        return values.map { CGFloat($0) }
    }

    @discardableResult
    static func toggleFavorite(height: CGFloat, isCompatibility: Bool) -> Bool {
        let key = isCompatibility ? compatibilityFavoritesKey : standardFavoritesKey
        let tolerance: CGFloat = isCompatibility ? 0.49 : 0.049
        var values = favorites(isCompatibility: isCompatibility)
        if let index = values.firstIndex(where: { abs($0 - height) <= tolerance }) {
            values.remove(at: index)
            UserDefaults.standard.set(values.map(Double.init), forKey: key)
            return false
        }
        values.insert(height, at: 0)
        if values.count > maximumFavorites { values.removeLast(values.count - maximumFavorites) }
        UserDefaults.standard.set(values.map(Double.init), forKey: key)
        return true
    }

    static func defaultHeight(isCompatibility: Bool, fallback: CGFloat) -> CGFloat {
        let key = isCompatibility ? compatibilityDefaultKey : standardDefaultKey
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return CGFloat(UserDefaults.standard.double(forKey: key))
    }

    static func setDefault(height: CGFloat, isCompatibility: Bool) {
        UserDefaults.standard.set(Double(height), forKey: isCompatibility ? compatibilityDefaultKey : standardDefaultKey)
    }
}
