import AppKit
import SwiftUI

struct PanelView: View {
    @Bindable var store: AppStore
        //check 123smmamdsmsnsdsamsm
    // salam menim adim Arizdi.
    //gordun ne deyisikler etdim??? ?salam /salam
    var body: some View {
        ZStack {
            mainPanel

            if store.showSettings {
                PanelOverlay(title: "Settings", onClose: { store.showSettings = false }) {
                    SettingsView(store: store, onClose: { store.showSettings = false })
                }
            }

            if store.showCheckpointSheet {
                PanelOverlay(title: "Save checkpoint", onClose: { store.showCheckpointSheet = false }) {
                    CheckpointSheetView(store: store, onClose: { store.showCheckpointSheet = false })
                }
            }
        


            if store.showExportPreview {
                PanelOverlay(title: "Copy for Cursor", onClose: { store.showExportPreview = false }) {
                    ExportPreviewView(store: store, onClose: { store.showExportPreview = false })
                }
            }

            if store.showSessionSummary {
                PanelOverlay(title: "Session Summary", onClose: { store.showSessionSummary = false }) {
                    SessionSummaryView(store: store, onClose: { store.showSessionSummary = false })
                }
            }
        }
        .frame(width: 390)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            header
            Divider()
            projectSection
            Divider()
            tabPicker
            tabContent
            Divider()
            bottomActions
        }
    }

    private var header: some View {
        HStack {
            Label("Check", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                store.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if store.projects.isEmpty {
                    Text("No project selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Project", selection: projectSelectionBinding) {
                        ForEach(store.projects.sorted { $0.lastSelectedAt > $1.lastSelectedAt }) { project in
                            Text(project.name).tag(project.id)
                        }
                    }
                    .labelsHidden()
                }

                Button {
                    openProjectPicker()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add project")
            }

            if let project = store.selectedProject {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name)
                            .font(.subheadline.weight(.medium))
                        projectAccessLine
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        GitBadge(
                            branch: store.liveGit.snapshot.branch,
                            available: store.liveGit.snapshot.gitAvailable,
                            changeCount: store.liveGit.snapshot.changedFiles.count
                        )
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(store.liveGit.snapshot.workingTreeStatus)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            if !store.liveGit.snapshot.changedFiles.isEmpty {
                                let files = store.liveGit.snapshot.changedFiles
                                let stats = store.liveGit.snapshot.fileStats ?? [:]
                                
                                ScrollView {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        ForEach(files, id: \.self) { file in
                                            HStack(spacing: 4) {
                                                Text(file)
                                                    .truncationMode(.middle)
                                                    .lineLimit(1)
                                                
                                                if let stat = stats[file] {
                                                    Text(stat)
                                                        .fixedSize(horizontal: true, vertical: false)
                                                } else {
                                                    Text("(new)")
                                                        .fixedSize(horizontal: true, vertical: false)
                                                }
                                            }
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .frame(maxHeight: 80)
                            }
                        }
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 180, alignment: .trailing)
                        .help(store.liveGit.snapshot.changedFiles.map { file in
                            if let stat = store.liveGit.snapshot.fileStats?[file] {
                                return "\(file) \(stat)"
                            } else {
                                return "\(file) (new)"
                            }
                        }.joined(separator: "\n"))
                        if store.liveGit.snapshot.errorMessage != nil {
                            Button("Locate folder again…") { relocateProject() }
                                .font(.caption2)
                        }
                    }
                }
            }

            HStack {
                TrackingIndicator(enabled: store.trackingEnabled)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { store.trackingEnabled },
                    set: { store.setTrackingEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            if let message = store.statusMessage {
                StatusBanner(message: message)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var projectSelectionBinding: Binding<UUID> {
        Binding(
            get: {
                if let id = store.selectedProjectID,
                   store.projects.contains(where: { $0.id == id }) {
                    return id
                }
                return store.projects.first?.id ?? UUID()
            },
            set: { store.selectProject($0) }
        )
    }

    @ViewBuilder
    private var projectAccessLine: some View {
        switch store.projectAccess {
        case .unknown:
            Text("Add a local project folder to begin.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .accessible:
            EmptyView()
        case .missing:
            HStack(spacing: 8) {
                Text("Folder missing or moved.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Locate…") { relocateProject() }
                    .font(.caption)
            }
        case .inaccessible(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                if let path = store.selectedProject?.folderPath {
                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button("Locate folder again…") { relocateProject() }
                    .font(.caption)
            }
        }
    }

    private var tabPicker: some View {
        Picker("", selection: $store.selectedTab) {
            ForEach(PanelTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var tabContent: some View {
        ScrollView {
            Group {
                switch store.selectedTab {
                case .resume:
                    ResumeTabView(store: store)
                case .history:
                    HistoryTabView(store: store)
                case .session:
                    SessionTabView(store: store)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: 360)
    }

    private var bottomActions: some View {
        HStack(spacing: 10) {
            Button("Save checkpoint") {
                store.prepareCheckpointSheet()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(store.selectedProject == nil)
        }
        .padding(16)
    }

    private func openProjectPicker() {
        store.onClosePopover?()

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a local project folder"
        panel.prompt = "Add Project"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try store.addProject(from: url)
            } catch {
                store.statusMessage = error.localizedDescription
            }
        }
    }

    private func relocateProject() {
        store.onClosePopover?()

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Locate the project folder"
        panel.prompt = "Select Folder"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try store.relocateSelectedProject(to: url)
            } catch {
                store.statusMessage = error.localizedDescription
            }
        }
    }
}
