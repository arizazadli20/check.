import SwiftUI

struct PlanTabView: View {
    @Bindable var store: AppStore
    @State private var newTaskTitle = ""
    @State private var pasteTasksText = ""
    @State private var showPasteSheet = false
    @State private var completedExpanded = false
    @State private var editingTask: TaskItem?

    private var activeTasks: [TaskItem] {
        store.currentTasks.filter { $0.status != .done }
    }

    private var doneTasks: [TaskItem] {
        store.currentTasks.filter { $0.status == .done }
    }

    var body: some View {
        ZStack {
            planContent

            if showPasteSheet {
                PanelOverlay(title: "Paste tasks", onClose: { showPasteSheet = false }) {
                    pasteContent
                }
            }

            if let task = editingTask {
                PanelOverlay(title: "Edit task", onClose: { editingTask = nil }) {
                    TaskEditorView(task: task, onClose: { editingTask = nil }) { updated in
                        store.updateTask(updated)
                        editingTask = nil
                    }
                }
            }
        }
    }

    private var planContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.selectedProject == nil {
                EmptyStateView(
                    icon: "folder.badge.plus",
                    title: "No project",
                    message: "Add a project folder to create a task plan."
                )
            } else {
                progressLine

                HStack(spacing: 8) {
                    TextField("Add a task…", text: $newTaskTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addTask() }
                    Button("Add") { addTask() }
                        .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Button("Paste multiple tasks…") {
                    showPasteSheet = true
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                if activeTasks.isEmpty && doneTasks.isEmpty {
                    EmptyStateView(
                        icon: "checklist",
                        title: "No tasks yet",
                        message: "Add tasks to plan your work for this project."
                    )
                } else {
                    ForEach(activeTasks) { task in
                        taskRow(task)
                    }

                    if !doneTasks.isEmpty {
                        DisclosureGroup(isExpanded: $completedExpanded) {
                            ForEach(doneTasks) { task in
                                taskRow(task)
                            }
                        } label: {
                            Text("Completed (\(doneTasks.count))")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }
            }
        }
    }

    private var progressLine: some View {
        let total = store.currentTasks.count
        let done = store.completedTaskCount
        return Text("\(done) of \(total) complete")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func taskRow(_ task: TaskItem) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Button {
                        store.toggleTaskComplete(task)
                    } label: {
                        Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.status == .done ? .green : .secondary)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(task.title)
                                .font(.subheadline.weight(.medium))
                                .strikethrough(task.status == .done)
                            if task.status == .inProgress {
                                Text("Current")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                            }
                        }
                        if !task.details.isEmpty {
                            Text(task.details)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    if task.status != .inProgress && task.status != .done {
                        Button("Set current") { store.setCurrentTask(task) }
                            .font(.caption)
                    }
                    Button("Edit") { editingTask = task }
                        .font(.caption)
                    Button("Up") { store.moveTask(task, direction: -1) }
                        .font(.caption)
                    Button("Down") { store.moveTask(task, direction: 1) }
                        .font(.caption)
                    Spacer()
                    Button("Delete", role: .destructive) { store.deleteTask(task) }
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var pasteContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("One task per line.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $pasteTasksText)
                .font(.body)
                .frame(minHeight: 140)
                .border(Color.secondary.opacity(0.2))
            HStack {
                Spacer()
                Button("Cancel") { showPasteSheet = false }
                Button("Add Tasks") {
                    store.addTasksFromPaste(pasteTasksText)
                    pasteTasksText = ""
                    showPasteSheet = false
                }
            }
        }
    }

    private func addTask() {
        store.addTask(title: newTaskTitle)
        newTaskTitle = ""
    }
}

struct TaskEditorView: View {
    @State var task: TaskItem
    let onClose: () -> Void
    let onSave: (TaskItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $task.title)
                .textFieldStyle(.roundedBorder)
            Text("Details")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $task.details)
                .font(.body)
                .frame(minHeight: 100)
                .border(Color.secondary.opacity(0.2))
            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                Button("Save") {
                    onSave(task)
                }
            }
        }
    }
}
