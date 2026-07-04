import SwiftUI
import TeststripCore

struct ActivityView: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let pauseNotice = model.backgroundWorkPauseNotice {
                Text(pauseNotice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            let activities = model.visibleWorkActivities
            if !activities.isEmpty {
                ForEach(Array(activities.prefix(4).enumerated()), id: \.element.id) { index, activity in
                    activityRow(activity, showsControls: index == 0)
                }
                if activities.count > 4 {
                    Text("\(activities.count - 4) more queued")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No active work")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private func activityRow(_ activity: AppWorkActivity, showsControls: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if activity.status == .running {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(activity.title)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text(label(for: activity.status))
                    .font(.caption2)
                    .foregroundStyle(color(for: activity.status))
                if model.canToggleWorkSessionStarred(activity) {
                    Button {
                        toggleStarred(activity)
                    } label: {
                        Image(systemName: activity.starred ? "star.fill" : "star")
                    }
                    .buttonStyle(.plain)
                    .help(activity.starred ? "Unstar work" : "Star work")
                }
                if showsControls, model.activeWork?.id == activity.id && activity.status == .running {
                    Button {
                        model.cancelActiveWork()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Cancel work")
                } else if showsControls {
                    if model.canPauseBackgroundWork {
                        Button {
                            model.pauseBackgroundWork()
                        } label: {
                            Image(systemName: "pause.circle")
                        }
                        .buttonStyle(.plain)
                        .help("Pause background work")
                    }
                    if model.canResumeBackgroundWork {
                        Button {
                            model.resumeBackgroundWork()
                        } label: {
                            Image(systemName: "play.circle")
                        }
                        .buttonStyle(.plain)
                        .help("Resume background work")
                    }
                    if model.canCancelBackgroundWork {
                        Button {
                            model.cancelBackgroundWork()
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.plain)
                        .help("Cancel background work")
                    }
                }
            }
            Text(activity.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if activity.showsProgress, let total = activity.totalUnitCount {
                ProgressView(value: Double(activity.completedUnitCount), total: Double(max(total, 1)))
                    .controlSize(.small)
            }
        }
    }

    private func label(for status: WorkSessionStatus) -> String {
        switch status {
        case .queued: "Queued"
        case .running: "Running"
        case .paused: "Paused"
        case .completed: "Done"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    private func color(for status: WorkSessionStatus) -> Color {
        switch status {
        case .queued, .running, .paused:
            .secondary
        case .completed:
            .green
        case .failed, .cancelled:
            .red
        }
    }

    private func toggleStarred(_ activity: AppWorkActivity) {
        do {
            try model.toggleWorkSessionStarred(id: WorkSessionID(rawValue: activity.id))
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}
