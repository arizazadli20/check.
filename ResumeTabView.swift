import SwiftUI

struct ResumeTabView: View {
    @Bindable var store: AppStore

    private var checkpoint: CheckpointRecord? {
        store.currentCheckpoints.first { $0.id == store.selectedCheckpointID } ?? store.latestCheckpoint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.selectedProject == nil {
                EmptyStateView(
                    icon: "arrow.uturn.forward.circle",
                    title: "Nothing to resume",
                    message: "Select a project and save a checkpoint first."
                )
            } else if checkpoint == nil {
                EmptyStateView(
                    icon: "bookmark",
                    title: "No checkpoints yet",
                    message: "Save a checkpoint when you pause work to resume later."
                )
            } else if let checkpoint {
                resumeContent(checkpoint)
            }
        }
    }

    @ViewBuilder
    private func resumeContent(_ checkpoint: CheckpointRecord) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(
                    title: "Latest checkpoint",
                    subtitle: formattedDate(checkpoint.timestamp)
                )

                if let task = checkpoint.taskTitleSnapshot, !task.isEmpty {
                    Label(task, systemImage: "target")
                        .font(.subheadline)
                } else if let current = store.currentTask {
                    Label("Current task: \(current.title)", systemImage: "target")
                        .font(.subheadline)
                } else {
                    Text("No current task")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        Card {
            VStack(alignment: .leading, spacing: 8) {
                labeledText("Working on", checkpoint.workingOn)
                labeledText("Next step", checkpoint.nextStep)
                if !checkpoint.blocker.isEmpty {
                    labeledText("Blocker / tried", checkpoint.blocker)
                }
            }
        }

        gitComparisonCard(checkpoint)

        if !checkpoint.recentActivity.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Foreground app activity")
                        .font(.subheadline.weight(.medium))
                    Text("Approximate active-app time while tracking was on.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(checkpoint.recentActivity.indices, id: \.self) { index in
                        let item = checkpoint.recentActivity[index]
                        HStack {
                            Text(item.appName)
                            Spacer()
                            Text(ActivityTracker.formatDuration(item.durationSeconds))
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
        }

        recentLiveActivity

        Button("Resume work") {
            store.resumeInCursor()
        }
        .buttonStyle(PrimaryButtonStyle())

        Text("Opens the project in Cursor when available, otherwise Finder. Does not run commands or change your repository.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var recentLiveActivity: some View {
        let summary = store.selectedProjectID.map {
            ActivityTracker.recentActivitySummary(for: $0, activities: store.activities)
        } ?? []

        return Group {
            if !summary.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recent foreground activity")
                            .font(.subheadline.weight(.medium))
                        ForEach(summary.indices, id: \.self) { index in
                            let item = summary[index]
                            HStack {
                                Text(item.appName)
                                Spacer()
                                Text(ActivityTracker.formatDuration(item.durationSeconds))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func gitComparisonCard(_ checkpoint: CheckpointRecord) -> some View {
        let live = store.liveGit.snapshot
        let differs = ContextExporter.gitDiffersFromCheckpoint(live: live, checkpoint: checkpoint.gitSnapshot)

        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Git snapshot")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button("Refresh") {
                        Task { await store.refreshLiveGit(includeDiff: false) }
                    }
                    .font(.caption)
                    .disabled(store.liveGit.isLoading)
                }

                if store.liveGit.isLoading {
                    ProgressView("Refreshing Git…")
                        .font(.caption)
                }

                Group {
                    Text("At checkpoint")
                        .font(.caption.weight(.semibold))
                    checkpointGitLines(checkpoint.gitSnapshot)

                    Divider()

                    Text("Live now")
                        .font(.caption.weight(.semibold))
                    if live.gitAvailable {
                        if let branch = live.branch {
                            Text("Branch: \(branch)").font(.caption)
                        }
                        Text(live.workingTreeStatus).font(.caption)
                        if !live.changedFiles.isEmpty {
                            Text("\(live.changedFiles.count) changed file(s)").font(.caption)
                        }
                    } else {
                        Text(live.errorMessage ?? "Git unavailable").font(.caption).foregroundStyle(.secondary)
                    }
                }

                if differs {
                    Label("Live Git state differs from checkpoint", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if live.gitAvailable && checkpoint.gitSnapshot.gitAvailable {
                    Label("Live Git matches checkpoint metadata", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Check snapshots are frozen. Live data reflects the repository now.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func checkpointGitLines(_ git: GitSnapshot) -> some View {
        if git.gitAvailable {
            if let branch = git.branch {
                Text("Branch: \(branch)").font(.caption)
            }
            Text(git.workingTreeStatus).font(.caption)
            if !git.changedFiles.isEmpty {
                Text("Changed: \(git.changedFiles.prefix(5).joined(separator: ", "))\(git.changedFiles.count > 5 ? "…" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(git.errorMessage ?? "Git unavailable").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func labeledText(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value)
                .font(.subheadline)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
