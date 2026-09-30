import AppKit
import Foundation

@MainActor
final class ActivityTracker {
    static let retentionDays: TimeInterval = 7 * 24 * 60 * 60

    private var observer: NSObjectProtocol?
    private weak var store: AppStore?
    private var currentInterval: ActivityRecord?
    private var checkpointBundleID: String?

    func configure(store: AppStore, checkpointBundleID: String?) {
        self.store = store
        self.checkpointBundleID = checkpointBundleID
    }

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else {
                return
            }

            let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown App"
            let bundleID = app.bundleIdentifier ?? "unknown"

            Task { @MainActor [weak self] in
                self?.handleActivation(appName: appName, bundleIdentifier: bundleID)
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        closeCurrentInterval()
    }

    func handleProjectChanged() {
        closeCurrentInterval()
        beginTrackingIfNeeded()
    }

    func handleTrackingToggle() {
        if store?.trackingEnabled == true {
            beginTrackingIfNeeded()
        } else {
            closeCurrentInterval()
        }
    }

    func handleAppTermination() {
        closeCurrentInterval()
    }

    private func handleActivation(appName: String, bundleIdentifier: String) {
        closeCurrentInterval()

        guard store?.trackingEnabled == true,
              store?.selectedProjectID != nil,
              bundleIdentifier != checkpointBundleID else {
            return
        }

        guard let projectID = store?.selectedProjectID else { return }

        currentInterval = ActivityRecord(
            projectID: projectID,
            appName: appName,
            bundleIdentifier: bundleIdentifier
        )
    }

    private func beginTrackingIfNeeded() {
        guard store?.trackingEnabled == true,
              store?.selectedProjectID != nil else { return }

        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.bundleIdentifier != checkpointBundleID {
            closeCurrentInterval()
            guard let projectID = store?.selectedProjectID else { return }
            currentInterval = ActivityRecord(
                projectID: projectID,
                appName: frontApp.localizedName ?? frontApp.bundleIdentifier ?? "Unknown App",
                bundleIdentifier: frontApp.bundleIdentifier ?? "unknown"
            )
        }
    }

    private func closeCurrentInterval() {
        guard var interval = currentInterval else { return }
        interval.endTime = Date()
        currentInterval = nil
        store?.appendActivity(interval)
    }

    static func pruneActivities(_ activities: [ActivityRecord]) -> [ActivityRecord] {
        let cutoff = Date().addingTimeInterval(-retentionDays)
        return activities.filter { $0.startTime >= cutoff }
    }

    static func recentActivitySummary(for projectID: UUID, activities: [ActivityRecord], limit: Int = 8) -> [ActivitySnapshot] {
        let projectActivities = activities
            .filter { $0.projectID == projectID && $0.endTime != nil }
            .sorted { ($0.endTime ?? $0.startTime) > ($1.endTime ?? $1.startTime) }

        var aggregated: [String: (name: String, bundle: String, duration: TimeInterval)] = [:]
        for record in projectActivities.prefix(50) {
            let key = record.bundleIdentifier
            var entry = aggregated[key] ?? (record.appName, record.bundleIdentifier, 0)
            entry.duration += record.duration
            aggregated[key] = entry
        }

        return aggregated.values
            .sorted { $0.duration > $1.duration }
            .prefix(limit)
            .map { ActivitySnapshot(appName: $0.name, bundleIdentifier: $0.bundle, durationSeconds: $0.duration) }
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        if totalMinutes < 1 { return "<1 min" }
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h \(minutes)m"
    }
}
