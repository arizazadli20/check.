import AppKit
import Foundation
import SwiftUI

@MainActor
@Observable
final class AppStore {
    var projects: [ProjectRecord] = []
    var tasks: [TaskItem] = []
    var checkpoints: [CheckpointRecord] = []
    var activities: [ActivityRecord] = []
    var selectedProjectID: UUID?
    var trackingEnabled: Bool = true

    var selectedTab: PanelTab = .session
    var showSettings = false
    var showCheckpointSheet = false
    var showExportPreview = false
    
    var sessionState = SessionTimerState(isActive: false, isPaused: false, timeRemaining: 3600, totalDuration: 3600)
    var showSessionSummary = false
    var currentSessionSummary: SessionSummaryData?
    var sessionSummaries: [SessionSummaryData] = []
    var sessionCheckTimer: Timer?
    var liveGitCheckTimer: Timer?

    var liveGit = LiveGitInfo(snapshot: .unavailable, isLoading: false, lastRefreshed: nil)
    var projectAccess: ProjectAccessState = .unknown
    var selectedCheckpointID: UUID?

    var isSavingCheckpoint = false
    var checkpointDraft = CheckpointDraft()
    var saveCheckpointError: String?
    var copiedFeedback = false
    var statusMessage: String?
    var exportIncludeDiff = true

    private var saveTask: Task<Void, Never>?
    private let activityTracker = ActivityTracker()
    private let projectWatcher = ProjectWatcher()
    private var baselineManifests: [UUID: [String: FileFingerprint]] = [:]
    var onClosePopover: (() -> Void)?

    struct CheckpointDraft {
        var workingOn: String = ""
        var nextStep: String = ""
        var blocker: String = ""
    }

    var selectedProject: ProjectRecord? {
        guard let selectedProjectID else { return nil }
        return projects.first { $0.id == selectedProjectID }
    }

    var currentTasks: [TaskItem] {
        guard let selectedProjectID else { return [] }
        return tasks.filter { $0.projectID == selectedProjectID }.sorted { $0.order < $1.order }
    }

    var currentCheckpoints: [CheckpointRecord] {
        guard let selectedProjectID else { return [] }
        return checkpoints
            .filter { $0.projectID == selectedProjectID }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var latestCheckpoint: CheckpointRecord? {
        currentCheckpoints.first
    }

    var currentTask: TaskItem? {
        currentTasks.first { $0.status == .inProgress }
    }

    var completedTaskCount: Int {
        currentTasks.filter { $0.status == .done }.count
    }

    func bootstrap(checkpointBundleID: String?) async {
        let data = await PersistenceService.shared.load()
        projects = data.projects
        tasks = data.tasks
        checkpoints = data.checkpoints
        activities = ActivityTracker.pruneActivities(data.activities)
        sessionSummaries = data.sessionSummaries ?? []
        selectedProjectID = data.selectedProjectID
        trackingEnabled = data.trackingEnabled

        if let id = selectedProjectID, !projects.contains(where: { $0.id == id }) {
            selectedProjectID = projects.sorted { $0.lastSelectedAt > $1.lastSelectedAt }.first?.id
        }

        activityTracker.configure(store: self, checkpointBundleID: checkpointBundleID)
        activityTracker.start()

        projectWatcher.onChange = { [weak self] in
            Task { @MainActor in
                await self?.refreshLiveGit(includeDiff: false)
            }
        }
        
        liveGitCheckTimer?.invalidate()
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if self == nil { break }
                await MainActor.run {
                    Task {
                        await self?.refreshLiveGit(includeDiff: false)
                    }
                }
            }
        }

        await refreshProjectAccess()
        await establishBaselineAndWatcher()
        await refreshLiveGit(includeDiff: false)
        activityTracker.handleProjectChanged()
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await persist()
        }
    }

    func persist() async {
        let data = AppData(
            projects: projects,
            tasks: tasks,
            checkpoints: checkpoints,
            activities: activities,
            sessionSummaries: sessionSummaries,
            selectedProjectID: selectedProjectID,
            trackingEnabled: trackingEnabled
        )
        await PersistenceService.shared.save(data)
    }

    // MARK: - Projects

    func addProject(from url: URL) throws {
        let bookmark = try BookmarkManager.shared.createBookmarkFromOpenPanel(url)
        let name = url.lastPathComponent
        let project = ProjectRecord(name: name, bookmarkData: bookmark, folderPath: url.path)
        projects.append(project)
        selectProject(project.id)
        scheduleSave()
    }

    func selectProject(_ id: UUID) {
        if let previous = selectedProjectID {
            BookmarkManager.shared.stopAccessing(projectID: previous)
        }

        selectedProjectID = id
        if let index = projects.firstIndex(where: { $0.id == id }) {
            projects[index].lastSelectedAt = Date()
        }

        selectedCheckpointID = latestCheckpoint?.id
        scheduleSave()

        Task {
            await refreshProjectAccess()
            await establishBaselineAndWatcher()
            await refreshLiveGit(includeDiff: false)
            activityTracker.handleProjectChanged()
        }
    }

    func removeSelectedProject() {
        guard let id = selectedProjectID else { return }
        projectWatcher.stop()
        baselineManifests.removeValue(forKey: id)
        BookmarkManager.shared.stopAccessing(projectID: id)
        projects.removeAll { $0.id == id }
        tasks.removeAll { $0.projectID == id }
        checkpoints.removeAll { $0.projectID == id }
        activities.removeAll { $0.projectID == id }
        selectedProjectID = projects.sorted { $0.lastSelectedAt > $1.lastSelectedAt }.first?.id
        selectedCheckpointID = latestCheckpoint?.id
        scheduleSave()

        Task {
            await refreshProjectAccess()
            await establishBaselineAndWatcher()
            await refreshLiveGit(includeDiff: false)
            activityTracker.handleProjectChanged()
        }
    }

    func relocateSelectedProject(to url: URL) throws {
        guard let id = selectedProjectID,
              let index = projects.firstIndex(where: { $0.id == id }) else { return }

        BookmarkManager.shared.stopAccessing(projectID: id)
        let bookmark = try BookmarkManager.shared.createBookmarkFromOpenPanel(url)
        projects[index].bookmarkData = bookmark
        projects[index].name = url.lastPathComponent
        projects[index].folderPath = url.path
        scheduleSave()

        Task {
            await refreshProjectAccess()
            await establishBaselineAndWatcher()
            await refreshLiveGit(includeDiff: false)
        }
    }

    func refreshProjectAccess() async {
        guard let project = selectedProject else {
            projectAccess = .unknown
            return
        }

        do {
            let url = try BookmarkManager.shared.startAccessing(projectID: project.id, bookmarkData: project.bookmarkData)
            if BookmarkManager.shared.folderExists(at: url) {
                projectAccess = .accessible(url)
            } else {
                projectAccess = .missing
            }
        } catch let error as BookmarkError {
            switch error {
            case .stale, .resolutionFailed:
                projectAccess = .missing
            default:
                projectAccess = .inaccessible(error.localizedDescription)
            }
        } catch {
            projectAccess = .inaccessible(error.localizedDescription)
        }
    }

    func projectURL() -> URL? {
        if case .accessible(let url) = projectAccess { return url }
        return nil
    }

    // MARK: - Tasks

    func addTask(title: String, details: String = "") {
        guard let projectID = selectedProjectID else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let nextOrder = (currentTasks.map(\.order).max() ?? -1) + 1
        let task = TaskItem(projectID: projectID, title: trimmed, details: details, order: nextOrder)
        tasks.append(task)
        scheduleSave()
    }

    func addTasksFromPaste(_ text: String) {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for line in lines {
            addTask(title: line)
        }
    }

    func updateTask(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var updated = task
        updated.updatedAt = Date()
        tasks[index] = updated
        scheduleSave()
    }

    func deleteTask(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
        scheduleSave()
    }

    func setCurrentTask(_ task: TaskItem) {
        guard let projectID = selectedProjectID else { return }
        for index in tasks.indices where tasks[index].projectID == projectID {
            if tasks[index].status == .inProgress && tasks[index].id != task.id {
                tasks[index].status = .todo
                tasks[index].updatedAt = Date()
            }
        }
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].status = .inProgress
            tasks[index].updatedAt = Date()
        }
        scheduleSave()
    }

    func toggleTaskComplete(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        switch tasks[index].status {
        case .done:
            tasks[index].status = .todo
        case .inProgress, .todo:
            tasks[index].status = .done
        }
        tasks[index].updatedAt = Date()
        scheduleSave()
    }

    func moveTask(_ task: TaskItem, direction: Int) {
        var ordered = currentTasks
        guard let index = ordered.firstIndex(where: { $0.id == task.id }) else { return }
        let newIndex = index + direction
        guard ordered.indices.contains(newIndex) else { return }
        ordered.swapAt(index, newIndex)
        for (order, item) in ordered.enumerated() {
            if let taskIndex = tasks.firstIndex(where: { $0.id == item.id }) {
                tasks[taskIndex].order = order
            }
        }
        scheduleSave()
    }

    // MARK: - Git & file tracking

    private func establishBaselineAndWatcher() async {
        guard let projectID = selectedProjectID, let url = projectURL() else {
            projectWatcher.stop()
            return
        }

        if baselineManifests[projectID] == nil {
            baselineManifests[projectID] = FileChangeScanner.buildManifest(at: url)
        }

        projectWatcher.watch(url: url)
    }

    private func baselineManifest(for projectID: UUID) -> [String: FileFingerprint]? {
        baselineManifests[projectID]
    }

    private func resetBaseline(for projectID: UUID, at url: URL) {
        baselineManifests[projectID] = FileChangeScanner.buildManifest(at: url)
    }

    func refreshLiveGit(includeDiff: Bool = false) async {
        guard !liveGit.isLoading else { return }
        liveGit.isLoading = true
        
        await refreshProjectAccess()

        guard let url = projectURL() else {
            projectWatcher.stop()
            liveGit = LiveGitInfo(
                snapshot: GitSnapshot(
                    gitAvailable: false,
                    branch: nil,
                    headHash: nil,
                    recentCommits: [],
                    workingTreeStatus: "",
                    changedFiles: [],
                    diff: "",
                    diffTruncated: false,
                    errorMessage: "Project folder is not accessible. Try locating it again."
                ),
                isLoading: false,
                lastRefreshed: Date()
            )
            return
        }
        let manifest = selectedProjectID.flatMap { baselineManifest(for: $0) }
        let snapshot = ProjectScanner.scan(
            at: url,
            referenceManifest: manifest,
            includeDiff: includeDiff
        )
        liveGit = LiveGitInfo(snapshot: snapshot, isLoading: false, lastRefreshed: Date())
    }

    // MARK: - Checkpoints

    func prepareCheckpointSheet() {
        checkpointDraft = CheckpointDraft()
        if let currentTask {
            if checkpointDraft.workingOn.isEmpty {
                checkpointDraft.workingOn = currentTask.title
            }
        }
        saveCheckpointError = nil
        showCheckpointSheet = true
    }

    func saveCheckpoint() async {
        guard !isSavingCheckpoint else { return }
        guard let projectID = selectedProjectID else { return }

        isSavingCheckpoint = true
        saveCheckpointError = nil

        let draft = checkpointDraft
        let url = projectURL()
        var gitSnapshot = GitSnapshot.unavailable

        if let url {
            let manifest = baselineManifest(for: projectID)
            gitSnapshot = ProjectScanner.scan(
                at: url,
                referenceManifest: manifest,
                includeDiff: true
            )
            resetBaseline(for: projectID, at: url)
        }

        let activitySummary: [ActivitySnapshot]
        if let projectID = selectedProjectID {
            activitySummary = ActivityTracker.recentActivitySummary(for: projectID, activities: activities)
        } else {
            activitySummary = []
        }

        let checkpoint = CheckpointRecord(
            projectID: projectID,
            taskID: currentTask?.id,
            taskTitleSnapshot: currentTask?.title,
            workingOn: draft.workingOn.trimmingCharacters(in: .whitespacesAndNewlines),
            nextStep: draft.nextStep.trimmingCharacters(in: .whitespacesAndNewlines),
            blocker: draft.blocker.trimmingCharacters(in: .whitespacesAndNewlines),
            gitSnapshot: gitSnapshot,
            recentActivity: activitySummary
        )

        checkpoints.append(checkpoint)
        selectedCheckpointID = checkpoint.id
        isSavingCheckpoint = false
        showCheckpointSheet = false
        checkpointDraft = CheckpointDraft()
        scheduleSave()
        statusMessage = "Checkpoint saved"
    }

    func deleteCheckpoint(_ checkpoint: CheckpointRecord) {
        checkpoints.removeAll { $0.id == checkpoint.id }
        if selectedCheckpointID == checkpoint.id {
            selectedCheckpointID = latestCheckpoint?.id
        }
        scheduleSave()
    }

    // MARK: - Export

    func exportMarkdown(includeDiff: Bool? = nil) -> String {
        guard let project = selectedProject else { return "" }
        let checkpoint = currentCheckpoints.first { $0.id == selectedCheckpointID } ?? latestCheckpoint
        let options = ExportOptions(
            includeDiff: includeDiff ?? exportIncludeDiff,
            selectedCheckpoint: checkpoint
        )
        return ContextExporter.generateMarkdown(
            project: project,
            tasks: currentTasks,
            liveGit: liveGit.snapshot,
            checkpoint: checkpoint,
            options: options
        )
    }

    func copyExportToPasteboard(includeDiff: Bool? = nil) {
        let markdown = exportMarkdown(includeDiff: includeDiff)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        copiedFeedback = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedFeedback = false
        }
    }

    // MARK: - Activity

    func appendActivity(_ record: ActivityRecord) {
        activities.append(record)
        activities = ActivityTracker.pruneActivities(activities)
        scheduleSave()
    }

    func clearActivityHistory() {
        activities.removeAll()
        scheduleSave()
    }

    func setTrackingEnabled(_ enabled: Bool) {
        trackingEnabled = enabled
        scheduleSave()
        activityTracker.handleTrackingToggle()
    }

    func handleAppTermination() {
        activityTracker.handleAppTermination()
        Task { await persist() }
    }

    // MARK: - Session Analytics
    
    func startSession(duration: TimeInterval) {
        sessionState.totalDuration = duration
        sessionState.timeRemaining = duration
        sessionState.isActive = true
        sessionState.isPaused = false
        sessionState.startCommitHash = nil
        sessionState.initialFileStats = liveGit.snapshot.fileStats
        
        startTimer()
        
        if let url = projectURL() {
            Task {
                let hash = await GitService.shared.createWorkingTreeSnapshot(at: url)
                await MainActor.run {
                    self.sessionState.startCommitHash = hash
                }
            }
        }
    }
    
    func pauseSession() {
        sessionState.isPaused = true
    }
    
    func resumeSession() {
        sessionState.isPaused = false
    }
    
    func stopSession() {
        sessionState.isActive = false
        sessionCheckTimer?.invalidate()
        sessionCheckTimer = nil
    }
    
    private func startTimer() {
        sessionCheckTimer?.invalidate()
        sessionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickSession()
            }
        }
    }
    
    private func tickSession() {
        guard sessionState.isActive, !sessionState.isPaused else { return }
        sessionState.timeRemaining -= 1
        if sessionState.timeRemaining <= 0 {
            handleSessionExpiration()
        }
    }
    
    func handleSessionExpiration() {
        stopSession()
        
        let startCommit = sessionState.startCommitHash
        let initialStats = sessionState.initialFileStats ?? [:]
        let url = projectURL()
        
        Task {
            var stats: [String: String] = [:]
            
            // If we have a project URL and a start commit, get the full diff from the start commit
            if let url = url, let commit = startCommit {
                if let fullStats = await GitService.shared.getSessionStats(at: url, sinceCommit: commit) {
                    stats = fullStats
                }
            }
            
            // Include brand new untracked files created during the session
            if let url = url {
                let currentStats = liveGit.snapshot.fileStats ?? [:]
                for (file, statStr) in currentStats {
                    if statStr == "(new)", initialStats[file] == nil, stats[file] == nil {
                        let fileURL = url.appendingPathComponent(file)
                        if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                            let lineCount = content.split(whereSeparator: { $0.isNewline }).count
                            stats[file] = "+\(lineCount) -0"
                        } else {
                            stats[file] = "+1 -0"
                        }
                    }
                }
            }
            
            var fileEdits: [FileEditStat] = []
            var totalAdded = 0
            var totalRemoved = 0
            
            for (file, statStr) in stats {
                var added = 0
                var removed = 0
                let stripped = statStr.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
                let parts = stripped.split(separator: " ")
                if parts.count == 2 {
                    let addPart = parts[0].replacingOccurrences(of: "+", with: "")
                    let remPart = parts[1].replacingOccurrences(of: "-", with: "")
                    added = Int(addPart) ?? 0
                    removed = Int(remPart) ?? 0
                }
                totalAdded += added
                totalRemoved += removed
                fileEdits.append(FileEditStat(path: file, added: added, removed: removed))
            }
            
            fileEdits.sort { $0.totalEdits > $1.totalEdits }
            
            let summary = SessionSummaryData(
                totalLinesAdded: totalAdded,
                totalLinesRemoved: totalRemoved,
                filesModifiedCount: fileEdits.count,
                fileEditStats: fileEdits
            )
            
            await MainActor.run {
                currentSessionSummary = summary
                sessionSummaries.append(summary)
                scheduleSave()
                showSessionSummary = true
            }
        }
    }

    // MARK: - Resume

    func resumeInCursor() {
        guard let url = projectURL() else {
            statusMessage = "Project folder is not accessible."
            return
        }

        let cursorBundleIDs = [
            "com.todesktop.230313mzl4w4u92",
            "com.cursor.Cursor"
        ]

        for bundleID in cursorBundleIDs {
            if let cursorURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open([url], withApplicationAt: cursorURL, configuration: config) { _, error in
                    Task { @MainActor in
                        if let error {
                            self.statusMessage = "Could not open Cursor: \(error.localizedDescription)"
                        }
                    }
                }
                return
            }
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
        statusMessage = "Cursor not found. Opened project folder in Finder."
    }
}
