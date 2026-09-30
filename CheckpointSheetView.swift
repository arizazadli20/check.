import SwiftUI

struct CheckpointSheetView: View {
    @Bindable var store: AppStore
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let task = store.currentTask {
                Text("Linked to current task: \(task.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No current task selected. Notes will still be saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            labeledField("What were you working on?", text: $store.checkpointDraft.workingOn)
            labeledField("Next step", text: $store.checkpointDraft.nextStep)
            labeledField("Blocker / what you already tried", text: $store.checkpointDraft.blocker, axis: true)

            if store.isSavingCheckpoint {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Collecting Git context…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = store.saveCheckpointError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("Checkpoints capture notes and a Git snapshot. They do not commit, stash, or modify your repository.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel", action: onClose)
                Spacer()
                Button("Save") {
                    Task { await store.saveCheckpoint() }
                }
                .disabled(store.isSavingCheckpoint)
            }
        }
    }

    private func labeledField(_ title: String, text: Binding<String>, axis: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if axis {
                TextEditor(text: text)
                    .font(.body)
                    .frame(minHeight: 72)
                    .border(Color.secondary.opacity(0.2))
            } else {
                TextField(title, text: text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}
