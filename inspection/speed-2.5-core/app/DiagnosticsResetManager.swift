//
//  DiagnosticsResetManager.swift
//  pip_swift
//

import Foundation

enum DiagnosticsResetManager {
    private static let storedBuildKey = "pip.diagnostics.lastBuild"

    static func resetDiagnosticsIfBuildChanged() {
        let defaults = UserDefaults.standard
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let previousBuild = defaults.string(forKey: storedBuildKey)
        guard previousBuild != currentBuild else { return }

        AppDebugLogger.isDebugModeEnabled = false
        DiagnosticsRuntimeState.stopAppStateTracking()
        MetricKitLogger.shared.stop()
        DebugDiagnosticsMonitor.stop()
        AppDebugLogger.resetLogs()
        KeepAliveLogger.resetLogs()
        MetricKitLogger.shared.resetLogs()
        PowerUsageLogger.resetStatistics()
        defaults.set(currentBuild, forKey: storedBuildKey)
    }

    static func clearDiagnosticsIfDebugModeDisabled() {
        guard !AppDebugLogger.isDebugModeEnabled else { return }

        DiagnosticsRuntimeState.stopAppStateTracking()
        MetricKitLogger.shared.stop()
        DebugDiagnosticsMonitor.setEnabled(false)
        AppDebugLogger.resetLogs()
        KeepAliveLogger.resetLogs()
        MetricKitLogger.shared.resetLogs()
        PowerUsageLogger.resetStatistics()
    }
}

struct CacheCleanupReport {
    let removedItems: Int
    let freedBytes: Int64
    let failedItems: Int

    var hasChanges: Bool {
        removedItems > 0 || freedBytes > 0
    }
}

enum CacheCleanupManager {
    static let willResetAllAppDataNotification = Notification.Name("pip.cacheCleanup.willResetAllAppData")
    static let didResetAllAppDataNotification = Notification.Name("pip.cacheCleanup.didResetAllAppData")

    private static let cleanupQueue = DispatchQueue(
        label: "com.isil.speed.cache-cleanup",
        qos: .utility
    )
    private static let firstLaunchKey = "pip.cache.cleanup.firstLaunchCompleted"
    private static let lastBuildKey = "pip.cache.cleanup.lastBuild"
    private static let cleanupRevisionKey = "pip.cache.cleanup.revision"
    private static let cleanupRevision = "cache-cleanup-v1"
    private static let managedVideoDirectoryName = "pip-generated-video-cache"
    private static let generatedTemporaryPrefixes = [
        "pip-static-h264-clear-",
        "pip-playerlayer-long-h264-",
        "pip-playerlayer-status-"
    ]

    static func cleanOnLaunch() {
        let defaults = UserDefaults.standard
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let isFirstLaunch = defaults.object(forKey: firstLaunchKey) == nil
        let isBuildChanged = defaults.string(forKey: lastBuildKey) != currentBuild
        let isRuleChanged = defaults.string(forKey: cleanupRevisionKey) != cleanupRevision
        let fullCleanup = isFirstLaunch || isBuildChanged || isRuleChanged
        let reason = isFirstLaunch ? "首次安装" : (isBuildChanged ? "覆盖更新" : (isRuleChanged ? "清理规则更新" : "日常启动"))
        // Generated PiP videos are versioned by filename and remain valid across ordinary
        // app-build updates. Purging them on every TestFlight/sideload build forced needless
        // H.264 regeneration right after launch. Only a cleanup-rule migration may invalidate
        // the managed cache automatically; manual cleanup still purges it explicitly.
        let purgeManagedVideos = isRuleChanged

        cleanupQueue.async {
            let report = performCleanup(fullCleanup: fullCleanup, purgeManagedVideos: purgeManagedVideos)
            defaults.set(true, forKey: firstLaunchKey)
            defaults.set(currentBuild, forKey: lastBuildKey)
            defaults.set(cleanupRevision, forKey: cleanupRevisionKey)
            GeneratedPiPVideoCache.prepareForLaunch()
            AppDebugLogger.log(
                "缓存自动清理完成：原因=\(reason)，删除=\(report.removedItems)项，释放=\(formatBytes(report.freedBytes))，失败=\(report.failedItems)项"
            )
        }
    }

    static func clearManually(completion: @escaping (CacheCleanupReport) -> Void) {
        cleanupQueue.async {
            let report = performCleanup(fullCleanup: true, purgeManagedVideos: true)
            AppDebugLogger.log(
                "缓存手动清理完成：删除=\(report.removedItems)项，释放=\(formatBytes(report.freedBytes))，失败=\(report.failedItems)项"
            )
            DispatchQueue.main.async {
                completion(report)
            }
        }
    }

    static func resetAllAppData() {
        NotificationCenter.default.post(name: willResetAllAppDataNotification, object: nil)
        AppDebugLogger.isDebugModeEnabled = false
        DiagnosticsRuntimeState.stopAppStateTracking()
        MetricKitLogger.shared.stop()
        DebugDiagnosticsMonitor.stop()
        KeepAliveNotificationTester.cancelBackgroundProbeNotifications(reason: "清空全部数据")
        KeepAliveNotificationTester.cancelPiPStoppedNotifications(reason: "清空全部数据")

        cleanupQueue.async {
            let fileManager = FileManager.default
            var report = CacheCleanupReport(removedItems: 0, freedBytes: 0, failedItems: 0)
            let appDirectories = [
                fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
                fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
                fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ].compactMap { $0 }

            for directory in appDirectories {
                report = removeItem(directory, fileManager: fileManager, report: report)
                try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            let temporaryEntries = (try? fileManager.contentsOfDirectory(
                at: fileManager.temporaryDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: []
            )) ?? []
            for entry in temporaryEntries {
                report = removeItem(entry, fileManager: fileManager, report: report)
            }
            URLCache.shared.removeAllCachedResponses()
            if let bundleIdentifier = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: didResetAllAppDataNotification, object: report)
            }
        }
    }

    private static func performCleanup(
        fullCleanup: Bool,
        purgeManagedVideos: Bool
    ) -> CacheCleanupReport {
        let fileManager = FileManager.default
        var report = CacheCleanupReport(removedItems: 0, freedBytes: 0, failedItems: 0)

        if let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let entries = (try? fileManager.contentsOfDirectory(
                at: cachesDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for entry in entries where entry.lastPathComponent != managedVideoDirectoryName {
                if fullCleanup || isOlderThanOneWeek(entry) {
                    report = removeItem(entry, fileManager: fileManager, report: report)
                }
            }
            let managedDirectory = cachesDirectory.appendingPathComponent(managedVideoDirectoryName, isDirectory: true)
            let managedEntries = (try? fileManager.contentsOfDirectory(at: managedDirectory, includingPropertiesForKeys: nil)) ?? []
            for entry in managedEntries {
                let isAbandonedGeneration = entry.lastPathComponent.hasPrefix(".") && entry.pathExtension == "mov"
                if purgeManagedVideos || isAbandonedGeneration {
                    report = removeItem(entry, fileManager: fileManager, report: report)
                }
            }
        }

        let temporaryEntries = (try? fileManager.contentsOfDirectory(at: fileManager.temporaryDirectory, includingPropertiesForKeys: nil)) ?? []
        for entry in temporaryEntries where isGeneratedTemporaryFile(entry) {
            report = removeItem(entry, fileManager: fileManager, report: report)
        }
        if fullCleanup {
            URLCache.shared.removeAllCachedResponses()
        }
        return report
    }

    private static func isGeneratedTemporaryFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return generatedTemporaryPrefixes.contains(where: name.hasPrefix)
            || (name.hasPrefix(".") && name.hasSuffix(".mov"))
    }

    private static func isOlderThanOneWeek(_ url: URL) -> Bool {
        guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return true
        }
        return Date().timeIntervalSince(date) > 7 * 24 * 60 * 60
    }

    private static func removeItem(
        _ url: URL,
        fileManager: FileManager,
        report: CacheCleanupReport
    ) -> CacheCleanupReport {
        let metrics = fileMetrics(at: url, fileManager: fileManager)
        do {
            try fileManager.removeItem(at: url)
            return CacheCleanupReport(
                removedItems: report.removedItems + metrics.items,
                freedBytes: report.freedBytes + metrics.bytes,
                failedItems: report.failedItems
            )
        } catch {
            return CacheCleanupReport(
                removedItems: report.removedItems,
                freedBytes: report.freedBytes,
                failedItems: report.failedItems + 1
            )
        }
    }

    private static func fileMetrics(at url: URL, fileManager: FileManager) -> (items: Int, bytes: Int64) {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]), values.isDirectory == true else {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return (1, Int64(size))
        }
        var items = 0
        var bytes: Int64 = 0
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) {
            for case let childURL as URL in enumerator {
                guard let child = try? childURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), child.isRegularFile == true else { continue }
                items += 1
                bytes += Int64(child.fileSize ?? 0)
            }
        }
        return (items, bytes)
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

/// Runtime cache used by generated PiP backing videos.
///
/// This keeps the 1.0.9fix behavior isolated from the stable VideoCall and
/// PlayerLayer routes: generated media is stored in Library/Caches, legacy
/// temporary files are removed, and old entries are evicted by count/size.
enum GeneratedPiPVideoCache {
    private static let directoryName = "pip-generated-video-cache"

    // Compatibility media is tiny (roughly tens of KB per materialized height). Keeping a
    // modest neighborhood resident prevents repeated zlib decode + file creation while the
    // user scrubs back and forth, yet remains far below the old 220-height bulk warmup.
    private static let maximumFileCount = 32
    private static let maximumTotalBytes = 24 * 1024 * 1024
    private static let maintenanceQueue = DispatchQueue(
        label: "com.isil.speed.generated-video-cache",
        qos: .utility
    )
    private static let accessLock = NSLock()
    private static var accessSequence: UInt64 = 0
    private static var lastAccessByPath: [String: UInt64] = [:]
    private static let managedDirectoryURL: URL? = {
        let fileManager = FileManager.default
        guard let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = cachesDirectory.appendingPathComponent(directoryName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            return nil
        }
    }()

    private struct Entry {
        let url: URL
        let modifiedAt: Date
        let bytes: Int
        let accessSequence: UInt64
    }

    static func prepareForLaunch() {
        // CacheCleanupManager already removes abandoned/legacy temporary files. Run only
        // the bounded LRU pass here, and do it after that cleanup rather than racing it.
        trim(excluding: [])
    }

    static func videoURL(named filename: String) -> URL {
        let url: URL
        if let directory = managedDirectoryURL {
            url = directory.appendingPathComponent(filename)
        } else {
            url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        }
        recordAccess(to: url)
        return url
    }

    static func trim(excluding protectedURLs: [URL]) {
        maintenanceQueue.async {
            performTrim(excluding: protectedURLs)
        }
    }

    private static func recordAccess(to url: URL) {
        let path = url.standardizedFileURL.path
        accessLock.lock()
        accessSequence &+= 1
        lastAccessByPath[path] = accessSequence
        accessLock.unlock()
    }

    private static func accessSnapshot() -> [String: UInt64] {
        accessLock.lock()
        let snapshot = lastAccessByPath
        accessLock.unlock()
        return snapshot
    }

    private static func forgetAccess(to url: URL) {
        let path = url.standardizedFileURL.path
        accessLock.lock()
        lastAccessByPath.removeValue(forKey: path)
        accessLock.unlock()
    }

    private static func performTrim(excluding protectedURLs: [URL]) {
        guard let directory = managedDirectoryURL else { return }
        let fileManager = FileManager.default
        let protectedPaths = Set(protectedURLs.map { $0.standardizedFileURL.path })
        let access = accessSnapshot()
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        let entries = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ))?.compactMap { url -> Entry? in
            guard url.pathExtension == "mov" else { return nil }
            let values = try? url.resourceValues(forKeys: resourceKeys)
            return Entry(
                url: url,
                modifiedAt: values?.contentModificationDate ?? .distantPast,
                bytes: values?.fileSize ?? 0,
                accessSequence: access[url.standardizedFileURL.path] ?? 0
            )
        }.sorted { lhs, rhs in
            if lhs.accessSequence != rhs.accessSequence {
                return lhs.accessSequence < rhs.accessSequence
            }
            return lhs.modifiedAt < rhs.modifiedAt
        } ?? []

        var retainedCount = entries.count
        var retainedBytes = entries.reduce(0) { $0 + $1.bytes }
        for entry in entries {
            guard retainedCount > maximumFileCount || retainedBytes > maximumTotalBytes else { break }
            guard !protectedPaths.contains(entry.url.standardizedFileURL.path) else { continue }
            do {
                try fileManager.removeItem(at: entry.url)
                forgetAccess(to: entry.url)
                retainedCount -= 1
                retainedBytes -= entry.bytes
            } catch {
                continue
            }
        }
    }
}
