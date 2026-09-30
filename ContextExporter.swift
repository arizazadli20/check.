import Foundation

struct ExportOptions {
    var includeDiff: Bool
    var selectedCheckpoint: CheckpointRecord?
}

enum ContextExporter {
    static func generateMarkdown(
        project: ProjectRecord,
        tasks: [TaskItem],
        liveGit: GitSnapshot?,
        checkpoint: CheckpointRecord?,
        options: ExportOptions
    ) -> String {
        let exportDate = ISO8601DateFormatter().string(from: Date())
        var lines: [String] = []

        lines.append("# Check Context")
        lines.append("")
        lines.append("## Project")
        lines.append("- **Name:** \(project.name)")
        lines.append("- **Exported:** \(exportDate)")
        lines.append("")

        lines.append("## Live Git State")
        if let liveGit {
            if liveGit.gitAvailable {
                lines.append("- **Available:** Yes")
                if let branch = liveGit.branch { lines.append("- **Branch:** \(branch)") }
                if let head = liveGit.headHash { lines.append("- **HEAD:** \(head.prefix(12))") }
                lines.append("- **Status:** \(liveGit.workingTreeStatus.isEmpty ? "Unknown" : liveGit.workingTreeStatus)")
            } else {
                lines.append("- **Available:** No")
                if let error = liveGit.errorMessage { lines.append("- **Note:** \(error)") }
            }
        } else {
            lines.append("- **Available:** Not loaded")
        }
        lines.append("")

        let currentTask = tasks.first { $0.status == .inProgress }
        lines.append("## Current Task")
        if let currentTask {
            lines.append("- **Title:** \(currentTask.title)")
            if !currentTask.details.isEmpty {
                lines.append("- **Details:** \(currentTask.details)")
            }
        } else {
            lines.append("- No task marked in progress.")
        }
        lines.append("")

        let outstanding = tasks
            .filter { $0.status != .done }
            .sorted { $0.order < $1.order }

        lines.append("## Outstanding Tasks")
        if outstanding.isEmpty {
            lines.append("- None")
        } else {
            for (index, task) in outstanding.enumerated() {
                let marker = task.status == .inProgress ? " (in progress)" : ""
                lines.append("\(index + 1). \(task.title)\(marker)")
                if !task.details.isEmpty {
                    lines.append("   - \(task.details)")
                }
            }
        }
        lines.append("")

        if let checkpoint {
            lines.append("## Saved Checkpoint")
            lines.append("- **Saved at:** \(formattedDate(checkpoint.timestamp))")
            if let title = checkpoint.taskTitleSnapshot, !title.isEmpty {
                lines.append("- **Task:** \(title)")
            }
            lines.append("")
            lines.append("### Working On")
            lines.append(checkpoint.workingOn.isEmpty ? "_No note provided._" : checkpoint.workingOn)
            lines.append("")
            lines.append("### Next Step")
            lines.append(checkpoint.nextStep.isEmpty ? "_No next step provided._" : checkpoint.nextStep)
            lines.append("")
            if !checkpoint.blocker.isEmpty {
                lines.append("### Blockers / Attempted Approaches")
                lines.append(checkpoint.blocker)
                lines.append("")
            }

            lines.append("### Checkpoint Git Snapshot")
            let git = checkpoint.gitSnapshot
            if git.gitAvailable {
                if let branch = git.branch { lines.append("- **Branch:** \(branch)") }
                if let head = git.headHash { lines.append("- **HEAD:** \(head.prefix(12))") }
                lines.append("- **Status:** \(git.workingTreeStatus)")
                if !git.recentCommits.isEmpty {
                    lines.append("- **Recent commits:**")
                    for commit in git.recentCommits {
                        lines.append("  - `\(commit.shortHash)` \(commit.subject)")
                    }
                }
                if !git.changedFiles.isEmpty {
                    lines.append("- **Changed files at checkpoint:**")
                    for file in git.changedFiles.prefix(30) {
                        lines.append("  - \(file)")
                    }
                    if git.changedFiles.count > 30 {
                        lines.append("  - … and \(git.changedFiles.count - 30) more")
                    }
                }
            } else {
                lines.append("- Git was unavailable when this checkpoint was saved.")
                if let error = git.errorMessage { lines.append("- \(error)") }
            }
            lines.append("")

            if options.includeDiff, git.gitAvailable, !git.diff.isEmpty {
                lines.append("### Checkpoint Diff (reference only)")
                if git.diffTruncated {
                    lines.append("_Diff was truncated when saved._")
                }
                lines.append("```diff")
                lines.append(git.diff)
                lines.append("```")
                lines.append("")
            }

            if !checkpoint.recentActivity.isEmpty {
                lines.append("### Foreground App Activity (at checkpoint)")
                for item in checkpoint.recentActivity {
                    let duration = ActivityTracker.formatDuration(item.durationSeconds)
                    lines.append("- \(item.appName) (~\(duration))")
                }
                lines.append("")
            }
        } else {
            lines.append("## Saved Checkpoint")
            lines.append("- No checkpoint selected.")
            lines.append("")
        }

        lines.append("---")
        lines.append("")
        lines.append(
            "Inspect the current repository before editing. Use this checkpoint as context, not proof that a task is complete. Continue with the stated next step and preserve unrelated changes."
        )

        return lines.joined(separator: "\n")
    }

    static func gitDiffersFromCheckpoint(live: GitSnapshot, checkpoint: GitSnapshot) -> Bool {
        guard live.gitAvailable, checkpoint.gitAvailable else { return false }
        if live.branch != checkpoint.branch { return true }
        if live.headHash != checkpoint.headHash { return true }
        if Set(live.changedFiles) != Set(checkpoint.changedFiles) { return true }
        return false
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
