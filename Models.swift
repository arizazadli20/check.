import Foundation

enum TaskStatus: String, Codable, CaseIterable {
    case todo
    case inProgress
    case done
}

struct TaskItem: Codable, Identifiable, Equatable {
    var id: UUID
    var projectID: UUID
    var title: String
    var details: String
    var status: TaskStatus
    var order: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        projectID: UUID,
        title: String,
        details: String = "",
        status: TaskStatus = .todo,
        order: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.details = details
        self.status = status
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ProjectRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var bookmarkData: Data
    var folderPath: String?
    var dateAdded: Date
    var lastSelectedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        bookmarkData: Data,
        folderPath: String? = nil,
        dateAdded: Date = Date(),
        lastSelectedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.bookmarkData = bookmarkData
        self.folderPath = folderPath
        self.dateAdded = dateAdded
        self.lastSelectedAt = lastSelectedAt
    }
}

struct GitCommitSnapshot: Codable, Equatable {
    var shortHash: String
    var subject: String
}

struct GitSnapshot: Codable, Equatable {
    var gitAvailable: Bool
    var branch: String?
    var headHash: String?
    var recentCommits: [GitCommitSnapshot]
    var workingTreeStatus: String
    var changedFiles: [String]
    var diff: String
    var diffTruncated: Bool
    var errorMessage: String?
    var fileStats: [String: String]?

    static var unavailable: GitSnapshot {
        GitSnapshot(
            gitAvailable: false,
            branch: nil,
            headHash: nil,
            recentCommits: [],
            workingTreeStatus: "",
            changedFiles: [],
            diff: "",
            diffTruncated: false,
            errorMessage: "Git unavailable",
            fileStats: [:]
        )
    }
}

struct ActivitySnapshot: Codable, Equatable {
    var appName: String
    var bundleIdentifier: String
    var durationSeconds: TimeInterval
}

struct CheckpointRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var projectID: UUID
    var taskID: UUID?
    var taskTitleSnapshot: String?
    var timestamp: Date
    var workingOn: String
    var nextStep: String
    var blocker: String
    var gitSnapshot: GitSnapshot
    var recentActivity: [ActivitySnapshot]

    init(
        id: UUID = UUID(),
        projectID: UUID,
        taskID: UUID? = nil,
        taskTitleSnapshot: String? = nil,
        timestamp: Date = Date(),
        workingOn: String,
        nextStep: String,
        blocker: String = "",
        gitSnapshot: GitSnapshot,
        recentActivity: [ActivitySnapshot] = []
    ) {
        self.id = id
        self.projectID = projectID
        self.taskID = taskID
        self.taskTitleSnapshot = taskTitleSnapshot
        self.timestamp = timestamp
        self.workingOn = workingOn
        self.nextStep = nextStep
        self.blocker = blocker
        self.gitSnapshot = gitSnapshot
        self.recentActivity = recentActivity
    }
}

struct ActivityRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var projectID: UUID
    var appName: String
    var bundleIdentifier: String
    var startTime: Date
    var endTime: Date?

    init(
        id: UUID = UUID(),
        projectID: UUID,
        appName: String,
        bundleIdentifier: String,
        startTime: Date = Date(),
        endTime: Date? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.startTime = startTime
        self.endTime = endTime
    }

    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }
}

struct AppData: Codable {
    var projects: [ProjectRecord]
    var tasks: [TaskItem]
    var checkpoints: [CheckpointRecord]
    var activities: [ActivityRecord]
    var sessionSummaries: [SessionSummaryData]?
    var selectedProjectID: UUID?
    var trackingEnabled: Bool

    static var empty: AppData {
        AppData(
            projects: [],
            tasks: [],
            checkpoints: [],
            activities: [],
            sessionSummaries: [],
            selectedProjectID: nil,
            trackingEnabled: true
        )
    }
}

enum PanelTab: String, CaseIterable, Identifiable {
    case session = "Session"
    case resume = "Resume"
    case history = "History"

    var id: String { rawValue }
}

struct SessionTimerState: Codable, Equatable {
    var isActive: Bool
    var isPaused: Bool
    var timeRemaining: TimeInterval
    var totalDuration: TimeInterval
    var startCommitHash: String?
    var initialFileStats: [String: String]?
}

struct FileEditStat: Identifiable, Equatable, Codable {
    var id = UUID()
    var path: String
    var added: Int
    var removed: Int
    var totalEdits: Int { added + removed }
    var bugHeat: Double {
        if totalEdits == 0 { return 0 }
        let churnRatio = Double(min(added, removed)) / Double(max(added, removed))
        return Double(totalEdits) * (1.0 + churnRatio)
    }
}

struct SessionSummaryData: Identifiable, Equatable, Codable {
    var id = UUID()
    var timestamp = Date()
    var totalLinesAdded: Int
    var totalLinesRemoved: Int
    var filesModifiedCount: Int
    var fileEditStats: [FileEditStat]
}

struct LiveGitInfo: Equatable {
    var snapshot: GitSnapshot
    var isLoading: Bool
    var lastRefreshed: Date?
}

enum ProjectAccessState: Equatable {
    case unknown
    case accessible(URL)
    case missing
    case inaccessible(String)
}
// test comment
