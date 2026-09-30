import SwiftUI
import Charts

struct HistoryTabView: View {
    @Bindable var store: AppStore
    @State private var detailCheckpoint: CheckpointRecord?
    @State private var deleteCandidate: CheckpointRecord?

    @State private var historyMode: Int = 0 // 0 = Checkpoints, 1 = Sessions

    var body: some View {
        ZStack {
            VStack {
                Picker("", selection: $historyMode) {
                    Text("Checkpoints").tag(0)
                    Text("Sessions").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 8)
                
                if historyMode == 0 {
                    historyContent
                } else {
                    sessionHistoryContent
                }
            }

            if let checkpoint = detailCheckpoint {
                PanelOverlay(title: "Checkpoint details", onClose: { detailCheckpoint = nil }) {
                    CheckpointDetailView(
                        store: store,
                        checkpoint: checkpoint,
                        onClose: { detailCheckpoint = nil }
                    )
                }
            }
        }
    }

    private var sessionHistoryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.sessionSummaries.isEmpty {
                EmptyStateView(
                    icon: "chart.bar",
                    title: "No sessions",
                    message: "Completed sessions will appear here."
                )
            } else {
                ForEach(store.sessionSummaries.sorted(by: { $0.timestamp > $1.timestamp })) { summary in
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(formattedDate(summary.timestamp))
                                .font(.subheadline.weight(.medium))
                            
                            HStack {
                                MetricView(title: "Added", value: "\(summary.totalLinesAdded)", color: .green)
                                Divider()
                                MetricView(title: "Removed", value: "\(summary.totalLinesRemoved)", color: .red)
                                Divider()
                                MetricView(title: "Files", value: "\(summary.filesModifiedCount)", color: .blue)
                            }
                            
                            if !summary.fileEditStats.isEmpty {
                                Text("Top Edits")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                
                                Chart {
                                    ForEach(summary.fileEditStats.prefix(3)) { stat in
                                        BarMark(
                                            x: .value("Added", stat.added),
                                            y: .value("File", (stat.path as NSString).lastPathComponent)
                                        )
                                        .foregroundStyle(.green)
                                        
                                        BarMark(
                                            x: .value("Removed", stat.removed),
                                            y: .value("File", (stat.path as NSString).lastPathComponent)
                                        )
                                        .foregroundStyle(.red)
                                    }
                                }
                                .chartXAxis { AxisMarks { AxisValueLabel() } }
                                .frame(height: 80)
                            }
                        }
                    }
                }
            }
        }
    }

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.selectedProject == nil {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "No project",
                    message: "Select a project to view checkpoint history."
                )
            } else if store.currentCheckpoints.isEmpty {
                EmptyStateView(
                    icon: "clock",
                    title: "No history",
                    message: "Saved checkpoints will appear here newest first."
                )
            } else {
                Text("Viewing an old checkpoint does not restore code.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ForEach(store.currentCheckpoints) { checkpoint in
                    checkpointRow(checkpoint)
                }
            }

            if let checkpoint = deleteCandidate {
                InlineConfirmDialog(
                    title: "Delete checkpoint?",
                    message: "This removes the saved checkpoint from Check only.",
                    confirmTitle: "Delete",
                    onConfirm: {
                        store.deleteCheckpoint(checkpoint)
                        deleteCandidate = nil
                    },
                    onCancel: { deleteCandidate = nil }
                )
            }
        }
    }

    private func checkpointRow(_ checkpoint: CheckpointRecord) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(formattedDate(checkpoint.timestamp))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if checkpoint.gitSnapshot.gitAvailable, let branch = checkpoint.gitSnapshot.branch {
                        Text(branch)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }

                if let title = checkpoint.taskTitleSnapshot, !title.isEmpty {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(checkpoint.workingOn.isEmpty ? checkpoint.nextStep : checkpoint.workingOn)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Details") {
                        store.selectedCheckpointID = checkpoint.id
                        detailCheckpoint = checkpoint
                    }
                    .font(.caption)
                    Button("Copy") {
                        store.selectedCheckpointID = checkpoint.id
                        store.copyExportToPasteboard()
                    }
                    .font(.caption)
                    Spacer()
                    Button("Delete", role: .destructive) {
                        deleteCandidate = checkpoint
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct CheckpointDetailView: View {
    @Bindable var store: AppStore
    let checkpoint: CheckpointRecord
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This is a saved snapshot. It does not restore code or undo repository changes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            detailSection("Saved", formattedDate(checkpoint.timestamp))
            if let title = checkpoint.taskTitleSnapshot {
                detailSection("Task", title)
            }
            detailSection("Working on", checkpoint.workingOn)
            detailSection("Next step", checkpoint.nextStep)
            if !checkpoint.blocker.isEmpty {
                detailSection("Blocker / tried", checkpoint.blocker)
            }

            if checkpoint.gitSnapshot.gitAvailable {
                detailSection("Branch", checkpoint.gitSnapshot.branch ?? "—")
                detailSection("Status", checkpoint.gitSnapshot.workingTreeStatus)
                if !checkpoint.gitSnapshot.changedFiles.isEmpty {
                    detailSection("Changed files", checkpoint.gitSnapshot.changedFiles.joined(separator: "\n"))
                }
                if !checkpoint.gitSnapshot.recentCommits.isEmpty {
                    let commits = checkpoint.gitSnapshot.recentCommits
                        .map { "`\($0.shortHash)` \($0.subject)" }
                        .joined(separator: "\n")
                    detailSection("Recent commits", commits)
                }
            } else {
                detailSection("Git", checkpoint.gitSnapshot.errorMessage ?? "Unavailable")
            }

            HStack {
                Button("Copy context") {
                    store.selectedCheckpointID = checkpoint.id
                    store.copyExportToPasteboard()
                }
                Spacer()
                Button("Close", action: onClose)
            }
        }
    }

    private func detailSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(body.isEmpty ? "—" : body)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
