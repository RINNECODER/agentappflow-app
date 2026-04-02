import AppKit
import SwiftUI

struct ControlCenterEmptyStateView: View {
    let presentSetup: () -> Void

    var body: some View {
        ZStack {
            AppBackground()

            AppCard(padding: AppTheme.Spacing.xxl, cornerRadius: AppTheme.Radius.xl, interactive: true) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    AppBadge(status: .idle)
                    Text("No projects registered")
                        .font(AppTheme.Typography.display(34))
                    Text("The control center is ready, but the sidebar has no workspaces yet. Register one repository to unlock session history, framework health, and proposal review.")
                        .font(AppTheme.Typography.body(15, weight: .semibold))
                        .foregroundStyle(.secondary)
                    AppButton("Start Onboarding", variant: .primary, action: presentSetup)
                }
            }
            .frame(maxWidth: 680)
        }
    }
}

struct ActiveSessionBanner: View {
    let session: SessionRecord

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    AppBadge(status: .healthy)
                    Text("Active session")
                        .font(AppTheme.Typography.mono(11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(elapsedText(referenceDate: context.date))
                            .font(AppTheme.Typography.mono(11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(session.title)
                    .font(AppTheme.Typography.headline(22, weight: .semibold))

                Text(session.currentTaskName ?? "Waiting on the next runtime step.")
                    .font(AppTheme.Typography.body(13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func elapsedText(referenceDate: Date) -> String {
        let seconds = max(Int(referenceDate.timeIntervalSince(session.startedAt)), 0)
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d elapsed", minutes, remainingSeconds)
    }
}

struct FrameworkHealthSection: View {
    let projectDetail: ProjectDetail

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SectionHeader(title: "Framework Health", subtitle: "Required AgentAppFlow paths and contract files")

                ForEach(projectDetail.frameworkHealth) { item in
                    HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                        AppBadge(status: item.status == .present ? .healthy : .warning)
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Text(item.path)
                                .font(AppTheme.Typography.mono(13, weight: .medium))
                            Text(item.detail)
                                .font(AppTheme.Typography.body(12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    if item.id != projectDetail.frameworkHealth.last?.id {
                        AppDivider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ProposalPanel: View {
    let projectDetail: ProjectDetail
    let supportsProposalResolution: Bool
    let approveProposal: (FrameworkProposal) -> Void
    let rejectProposal: (FrameworkProposal) -> Void

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SectionHeader(title: "Framework Proposals", subtitle: "Pending changes before they land in the repo")

                if !supportsProposalResolution {
                    Text("Proposal actions are read-only on the current runtime. Enable the stub runtime or wait for Phase 8 live wiring to approve or reject proposals here.")
                        .font(AppTheme.Typography.body(12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if projectDetail.pendingProposals.isEmpty {
                    Text("No pending proposals. The project detail is already aligned with the current framework contract.")
                        .font(AppTheme.Typography.body(13, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(projectDetail.pendingProposals) { proposal in
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            HStack {
                                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                    Text(proposal.title)
                                        .font(AppTheme.Typography.headline(16, weight: .black))
                                    Text(proposal.filePath)
                                        .font(AppTheme.Typography.mono(12, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                AppBadge(status: .warning)
                            }

                            Text(proposal.summary)
                                .font(AppTheme.Typography.body(13, weight: .semibold))
                                .foregroundStyle(.secondary)

                            ForEach(proposal.changeSummary, id: \.self) { item in
                                Label(item, systemImage: "arrow.turn.down.right")
                                    .font(AppTheme.Typography.body(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: AppTheme.Spacing.sm) {
                                AppButton("Approve", variant: .primary, isDisabled: !supportsProposalResolution) {
                                    approveProposal(proposal)
                                }
                                AppButton("Reject", variant: .secondary, isDisabled: !supportsProposalResolution) {
                                    rejectProposal(proposal)
                                }
                            }
                        }

                        if proposal.id != projectDetail.pendingProposals.last?.id {
                            AppDivider()
                        }
                    }
                }
            }
        }
        .frame(width: 420)
    }
}

struct SessionHistorySection: View {
    let sessions: [SessionRecord]
    @Binding var selectedSessionID: String?

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SectionHeader(title: "Session History", subtitle: "Recent runs, outcomes, and durations")

                if sessions.isEmpty {
                    Text("No sessions yet. Start a new run from the quick actions menu to populate activity.")
                        .font(AppTheme.Typography.body(13, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions) { session in
                        Button {
                            selectedSessionID = session.id
                        } label: {
                            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                                AppBadge(status: badgeStatus(for: session))

                                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                    Text(session.title)
                                        .font(AppTheme.Typography.headline(14, weight: .semibold))
                                        .lineLimit(1)
                                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(AppTheme.Typography.body(12, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: AppTheme.Spacing.xs) {
                                    Text(session.outcomeBadgeLabel)
                                        .font(AppTheme.Typography.mono(10, weight: .semibold))
                                    Text(durationLabel(for: session))
                                        .font(AppTheme.Typography.body(11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, AppTheme.Spacing.xs)
                            .padding(.horizontal, AppTheme.Spacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                .fill(selectedSessionID == session.id ? Color.primary.opacity(0.10) : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                        .strokeBorder(
                                            selectedSessionID == session.id ? Color.primary.opacity(0.25) : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                        )

                        if session.id != sessions.last?.id {
                            AppDivider()
                        }
                    }
                }
            }
        }
        .frame(width: 380)
    }

    private func badgeStatus(for session: SessionRecord) -> AppBadgeStatus {
        if session.isRunning {
            return .healthy
        }

        switch session.outcome {
        case .success:
            return .healthy
        case .partial:
            return .warning
        case .failed:
            return .error
        case .none:
            return .idle
        }
    }

    private func durationLabel(for session: SessionRecord) -> String {
        let minutes = max(session.resolvedDurationSeconds / 60, 1)
        return "\(minutes)m"
    }
}

struct SessionSummarySection: View {
    let session: SessionRecord?

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SectionHeader(title: "Session Summary", subtitle: "Outcome, files touched, and retrospective notes")

                if let session {
                    AppBadge(status: summaryBadge(for: session))
                    Text(session.outcomeBadgeLabel)
                        .font(AppTheme.Typography.headline(22, weight: .black))

                    HStack(spacing: AppTheme.Spacing.lg) {
                        SummaryMetric(title: "Tasks", value: "\(session.taskProgress.filter { $0.status == .completed }.count)")
                        SummaryMetric(title: "Files", value: "\(session.filesTouchedCount)")
                        SummaryMetric(title: "Duration", value: "\(max(session.resolvedDurationSeconds / 60, 1))m")
                    }

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        Text("Retro Notes")
                            .font(AppTheme.Typography.mono(12, weight: .black))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        if session.retroNotes.isEmpty {
                            Text("No retrospective notes attached.")
                                .font(AppTheme.Typography.body(12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(session.retroNotes, id: \.self) { note in
                                Label(note, systemImage: "chevron.right")
                                    .font(AppTheme.Typography.body(12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let retroURL = session.retroURL {
                        Text(retroURL)
                            .font(AppTheme.Typography.mono(11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Select a session to review its outcome, metrics, and retro notes.")
                        .font(AppTheme.Typography.body(13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 380)
    }

    private func summaryBadge(for session: SessionRecord) -> AppBadgeStatus {
        if session.isRunning {
            return .healthy
        }

        switch session.outcome {
        case .success:
            return .healthy
        case .partial:
            return .warning
        case .failed:
            return .error
        case .none:
            return .idle
        }
    }
}
