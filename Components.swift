import Charts
import SwiftUI

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct GitBadge: View {
    let branch: String?
    let available: Bool
    var changeCount: Int = 0

    var body: some View {
        if available, let branch {
            Label(branch, systemImage: "arrow.triangle.branch")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        } else if changeCount > 0 {
            Label("\(changeCount) file changes", systemImage: "doc.badge.ellipsis")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        } else {
            Label("No Git repo", systemImage: "folder")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
    }
}

struct TrackingIndicator: View {
    let enabled: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(enabled ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(enabled ? "Tracking on" : "Tracking paused")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel(enabled ? "Tracking on" : "Tracking paused")
    }
}

struct StatusBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.white)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// In-panel overlay. Avoids `.sheet()` inside menu bar popovers, which crashes on macOS.
struct PanelOverlay<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider()

                ScrollView {
                    content
                        .padding(14)
                }
            }
            .frame(width: 360)
            .frame(maxHeight: 440)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(radius: 12)
        }
    }
}

struct InlineConfirmDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button(confirmTitle, role: .destructive, action: onConfirm)
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}
import SwiftUI

struct SessionTabView: View {
    @Bindable var store: AppStore
    
    @State private var hours: Int = 1
    @State private var minutes: Int = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.sessionState.isActive {
                // Active session card
                VStack(spacing: 0) {
                    // Timer display
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(store.sessionState.isPaused ? Color.orange : Color.green)
                                .frame(width: 8, height: 8)
                            Text(store.sessionState.isPaused ? "Paused" : "Recording")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(store.sessionState.isPaused ? .orange : .green)
                        }
                        
                        let tr = Int(store.sessionState.timeRemaining)
                        let h = tr / 3600
                        let m = (tr % 3600) / 60
                        let s = tr % 60
                        Text(String(format: "%02d:%02d:%02d", h, m, s))
                            .font(.system(size: 36, weight: .light, design: .monospaced))
                            .foregroundStyle(.primary)
                        
                        // Progress bar
                        let progress = 1.0 - (store.sessionState.timeRemaining / max(store.sessionState.totalDuration, 1))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(.quaternary)
                                    .frame(height: 4)
                                Capsule()
                                    .fill(store.sessionState.isPaused ? Color.orange : Color.accentColor)
                                    .frame(width: geo.size.width * progress, height: 4)
                            }
                        }
                        .frame(height: 4)
                        .padding(.top, 4)
                    }
                    .padding(16)
                    
                    Divider()
                    
                    // Controls
                    HStack(spacing: 8) {
                        if store.sessionState.isPaused {
                            Button {
                                store.resumeSession()
                            } label: {
                                Label("Resume", systemImage: "play.fill")
                                    .font(.caption.weight(.medium))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 8)
                            .background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.green)
                        } else {
                            Button {
                                store.pauseSession()
                            } label: {
                                Label("Pause", systemImage: "pause.fill")
                                    .font(.caption.weight(.medium))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 8)
                            .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.orange)
                        }
                        
                        Button {
                            store.handleSessionExpiration()
                        } label: {
                            Label("End Session", systemImage: "stop.fill")
                                .font(.caption.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 8)
                        .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.red)
                    }
                    .padding(12)
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                // Timer setup
                VStack(spacing: 16) {
                    HStack(spacing: 0) {
                        Image(systemName: "timer")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Session Timer")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chart.bar.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Duration picker
                    HStack(spacing: 12) {
                        VStack(spacing: 4) {
                            Text("\(hours)")
                                .font(.system(size: 28, weight: .medium, design: .rounded))
                            Text("hours")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            HStack {
                                Button { if hours > 0 { hours -= 1 } } label: {
                                    Image(systemName: "minus")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 8)
                                Spacer()
                                Button { if hours < 72 { hours += 1 } } label: {
                                    Image(systemName: "plus")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 8)
                            }
                        }
                        
                        Text(":")
                            .font(.title2.weight(.light))
                            .foregroundStyle(.secondary)
                        
                        VStack(spacing: 4) {
                            Text(String(format: "%02d", minutes))
                                .font(.system(size: 28, weight: .medium, design: .rounded))
                            Text("min")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            HStack {
                                Button { if minutes >= 5 { minutes -= 5 } } label: {
                                    Image(systemName: "minus")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 8)
                                Spacer()
                                Button { if minutes < 55 { minutes += 5 } } label: {
                                    Image(systemName: "plus")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 8)
                            }
                        }
                    }
                    
                    Button {
                        let duration = TimeInterval(hours * 3600 + minutes * 60)
                        store.startSession(duration: max(duration, 60))
                    } label: {
                        Label("Start Session", systemImage: "play.fill")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                    .disabled(hours == 0 && minutes == 0)
                    .opacity(hours == 0 && minutes == 0 ? 0.5 : 1)
                }
                .padding(14)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}
import SwiftUI
import Charts

struct SessionSummaryView: View {
    @Bindable var store: AppStore
    let onClose: () -> Void

    var body: some View {
        if let summary = store.currentSessionSummary {
            VStack(alignment: .leading, spacing: 20) {
                
                HStack {
                    MetricView(title: "Added", value: "\(summary.totalLinesAdded)", color: .green)
                    Divider()
                    MetricView(title: "Removed", value: "\(summary.totalLinesRemoved)", color: .red)
                    Divider()
                    MetricView(title: "Files", value: "\(summary.filesModifiedCount)", color: .blue)
                }
                .padding()
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                
                if !summary.fileEditStats.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Top Edits")
                            .font(.headline)
                        
                        Chart {
                            ForEach(summary.fileEditStats.prefix(5)) { stat in
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
                        .frame(height: 120)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bug Heatmap (High Churn)")
                            .font(.headline)
                        
                        Chart {
                            ForEach(summary.fileEditStats.sorted { $0.bugHeat > $1.bugHeat }.prefix(5)) { stat in
                                SectorMark(
                                    angle: .value("Heat", stat.bugHeat),
                                    innerRadius: .ratio(0.5),
                                    angularInset: 1.5
                                )
                                .cornerRadius(4)
                                .foregroundStyle(by: .value("File", (stat.path as NSString).lastPathComponent))
                            }
                        }
                        .frame(height: 150)
                    }
                } else {
                    Text("No file changes detected during this session.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Button("Done", action: onClose)
                    .buttonStyle(PrimaryButtonStyle())
            }
        } else {
            Text("No summary available.")
        }
    }
}

struct MetricView: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
