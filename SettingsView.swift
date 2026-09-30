import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var store: AppStore
    let onClose: () -> Void
    @State private var showClearActivityConfirm = false
    @State private var showRemoveProjectConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // MARK: - Export
            VStack(alignment: .leading, spacing: 8) {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            store.showExportPreview = true
                            onClose()
                        } label: {
                            HStack {
                                Image(systemName: "doc.on.clipboard")
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Copy for Cursor")
                                        .font(.callout.weight(.medium))
                                    Text("Export checkpoint context to clipboard")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.quaternary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // MARK: - Tracking
            VStack(alignment: .leading, spacing: 8) {
                Label("Tracking", systemImage: "eye")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: Binding(
                            get: { store.trackingEnabled },
                            set: { store.setTrackingEnabled($0) }
                        )) {
                            HStack(spacing: 8) {
                                Image(systemName: store.trackingEnabled ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                                    .foregroundStyle(store.trackingEnabled ? .green : .secondary)
                                Text("Activity tracking")
                                    .font(.callout)
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        
                        Text("Records foreground app names and active time. Does not capture keystrokes, screenshots, or clipboard data.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // MARK: - Danger Zone
            VStack(alignment: .leading, spacing: 8) {
                Label("Danger Zone", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red.opacity(0.8))
                
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            showClearActivityConfirm = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "trash")
                                    .foregroundStyle(.orange)
                                Text("Clear activity history")
                                    .font(.callout)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(store.activities.isEmpty)
                        
                        Divider()
                        
                        Button {
                            showRemoveProjectConfirm = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.badge.minus")
                                    .foregroundStyle(.red)
                                Text("Remove selected project")
                                    .font(.callout)
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(store.selectedProject == nil)
                    }
                }
            }

            if showClearActivityConfirm {
                InlineConfirmDialog(
                    title: "Clear activity history?",
                    message: "This removes recorded foreground app activity from Check.",
                    confirmTitle: "Clear",
                    onConfirm: {
                        store.clearActivityHistory()
                        showClearActivityConfirm = false
                    },
                    onCancel: { showClearActivityConfirm = false }
                )
            }

            if showRemoveProjectConfirm {
                InlineConfirmDialog(
                    title: "Remove project?",
                    message: "Removes this project's tasks, checkpoints, and activity from Check. Your project files are not deleted.",
                    confirmTitle: "Remove",
                    onConfirm: {
                        store.removeSelectedProject()
                        showRemoveProjectConfirm = false
                        onClose()
                    },
                    onCancel: { showRemoveProjectConfirm = false }
                )
            }

            Spacer(minLength: 0)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                    Text("Quit Check")
                }
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.red)
        }
    }
}
