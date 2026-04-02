import AppKit
import SwiftUI

private enum ProjectListFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case needsAttention

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .active:
            "Active"
        case .needsAttention:
            "Needs Attention"
        }
    }
}

private enum ProjectSortOption: String, CaseIterable, Identifiable {
    case recent
    case alphabetical
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent:
            "Recent"
        case .alphabetical:
            "A-Z"
        case .status:
            "Status"
        }
    }
}

private enum ProjectConfirmationAction: Identifiable {
    case remove(RegisteredProject)
    case rebootstrap(RegisteredProject)

    var id: String {
        switch self {
        case .remove(let project):
            "remove-\(project.id)"
        case .rebootstrap(let project):
            "rebootstrap-\(project.id)"
        }
    }
}

struct ControlCenterView: View {
    @ObservedObject var store: AppRuntimeStore
    let presentSetup: () -> Void

    @State private var searchText = ""
    @State private var selectedFilter: ProjectListFilter = .all
    @State private var selectedSort: ProjectSortOption = .recent
    @State private var selectedSessionID: String?
    @State private var pendingConfirmationAction: ProjectConfirmationAction?
    @FocusState private var isSearchFocused: Bool

    private var projectDetail: ProjectDetail? {
        store.selectedProjectDetail
    }

    private var visibleProjects: [RegisteredProject] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = store.projects.filter { project in
            let matchesSearch: Bool
            if trimmedSearch.isEmpty {
                matchesSearch = true
            } else {
                matchesSearch = project.projectName.lowercased().contains(trimmedSearch)
                    || project.projectPath.lowercased().contains(trimmedSearch)
                    || project.projectType.displayName.lowercased().contains(trimmedSearch)
            }

            let matchesFilter: Bool
            switch selectedFilter {
            case .all:
                matchesFilter = true
            case .active:
                matchesFilter = isProjectActive(project)
            case .needsAttention:
                matchesFilter = projectNeedsAttention(project)
            }

            return matchesSearch && matchesFilter
        }

        switch selectedSort {
        case .recent:
            return filtered.sorted { lhs, rhs in
                lhs.lastActivityAt > rhs.lastActivityAt
            }
        case .alphabetical:
            return filtered.sorted { lhs, rhs in
                lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
            }
        case .status:
            return filtered.sorted { lhs, rhs in
                projectStatusRank(lhs) > projectStatusRank(rhs)
            }
        }
    }

    private var selectedSession: SessionRecord? {
        guard let projectDetail else { return nil }
        let sessions = projectDetail.sessions
        if let selectedSessionID,
           let matching = sessions.first(where: { $0.id == selectedSessionID }) {
            return matching
        }
        return projectDetail.activeSession ?? sessions.first
    }

    var body: some View {
        ZStack {
            AppBackground()

            HStack(spacing: AppTheme.Spacing.lg) {
                if !store.isSidebarCollapsed {
                    sidebar
                        .frame(width: AppTheme.Layout.controlCenterSidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                ScrollView {
                    mainContent
                    .padding(AppTheme.Spacing.xl)
                    .padding(.top, AppTheme.Spacing.xxxl + AppTheme.Spacing.sm)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.xl - 2)
            .padding(.top, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.xl - 2)
        }
        .frame(
            minWidth: AppTheme.Layout.controlCenterMinSize.width,
            minHeight: AppTheme.Layout.controlCenterMinSize.height
        )
        .onAppear {
            syncSelectedSession()
        }
        .onChange(of: projectDetail?.project.id) { _, _ in
            syncSelectedSession()
        }
        .onChange(of: projectDetail?.sessions.map(\.id) ?? []) { _, _ in
            syncSelectedSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentAppFlowFocusSearch)) { _ in
            isSearchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentAppFlowToggleSidebar)) { _ in
            store.toggleSidebar()
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingConfirmationAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingConfirmationAction = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if case .remove(let project) = pendingConfirmationAction {
                Button("Remove Project", role: .destructive) {
                    Task { await store.removeProject(id: project.id) }
                    pendingConfirmationAction = nil
                }
            }

            if case .rebootstrap(let project) = pendingConfirmationAction {
                Button("Re-bootstrap") {
                    Task { await store.rebootstrapSelectedProject() }
                    pendingConfirmationAction = nil
                }
                .disabled(project.id != store.selectedProjectID)
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            if let projectDetail {
                projectSections(projectDetail)
            }
        }
    }

    @ViewBuilder
    private func projectSections(_ projectDetail: ProjectDetail) -> some View {
        ProjectHeaderCard(
            projectDetail: projectDetail,
            canStartSession: store.capabilities.canStartSessions,
            startSession: {
                Task { await store.startSession() }
            },
            openRepository: {
                openURL(path: projectDetail.project.projectPath)
            }
        )

        if let activeSession = projectDetail.activeSession {
            ActiveSessionBanner(session: activeSession)
        }

        HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
            FrameworkHealthSection(projectDetail: projectDetail)
            ProposalPanel(
                projectDetail: projectDetail,
                supportsProposalResolution: store.capabilities.canResolveProposals,
                approveProposal: { proposal in
                    Task { await store.resolveProposal(proposal.id, approve: true) }
                },
                rejectProposal: { proposal in
                    Task { await store.resolveProposal(proposal.id, approve: false) }
                }
            )
        }

        HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
            SessionHistorySection(
                sessions: projectDetail.sessions,
                selectedSessionID: $selectedSessionID
            )
            SessionDetailDrawer(session: selectedSession)
        }

        HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
            ProjectSettingsPanel(
                settings: projectDetail.settings,
                supportsSaving: store.capabilities.canUpdateProjectSettings,
                save: { settings in
                    Task { await store.updateSelectedProjectSettings(settings) }
                }
            )
            SessionSummarySection(session: selectedSession)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("Control Center")
                        .font(AppTheme.Typography.display(26))
                    Text("Projects, sessions, health, and approvals.")
                        .font(AppTheme.Typography.body(12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                WindowTrafficDots()
            }

            AppCard(padding: AppTheme.Spacing.md, cornerRadius: AppTheme.Radius.md) {
                HStack(spacing: AppTheme.Spacing.md) {
                    SidebarMetaMetric(title: "Projects", value: "\(store.projects.count)")
                    SidebarMetaMetric(title: "Active", value: "\(store.projects.filter(isProjectActive).count)")
                    SidebarMetaMetric(title: "Flags", value: "\(store.projects.filter(projectNeedsAttention).count)")
                }
            }

            SearchField(text: $searchText, isFocused: $isSearchFocused)

            HStack(spacing: AppTheme.Spacing.sm) {
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(ProjectListFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                Menu {
                    Picker("Sort", selection: $selectedSort) {
                        ForEach(ProjectSortOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Label(selectedSort.title, systemImage: "arrow.up.arrow.down")
                        .font(AppTheme.Typography.body(13, weight: .bold))
                }
                .menuStyle(.borderlessButton)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Projects")
                    .font(AppTheme.Typography.mono(12, weight: .black))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                if store.isLoading && store.projects.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        ProjectSidebarSkeleton()
                    }
                } else if visibleProjects.isEmpty {
                    AppCard(padding: AppTheme.Spacing.lg, cornerRadius: AppTheme.Radius.md) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            Text(store.projects.isEmpty ? "No projects yet" : "No matching projects")
                                .font(AppTheme.Typography.headline(16, weight: .black))
                            Text(
                                store.projects.isEmpty
                                    ? "Run onboarding to register the first repository."
                                    : "Change the search, filter, or sort controls to reveal more workspaces."
                            )
                            .font(AppTheme.Typography.body(13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: AppTheme.Spacing.sm) {
                            ForEach(visibleProjects) { project in
                                ProjectSidebarRow(
                                    project: project,
                                    isSelected: project.id == store.selectedProjectID,
                                    status: badgeStatus(for: project),
                                    action: {
                                        Task { await store.selectProject(id: project.id) }
                                    },
                                    openRepository: {
                                        openURL(path: project.projectPath)
                                    },
                                    rebootstrap: {
                                        Task {
                                            guard store.capabilities.canRebootstrapProjects else { return }
                                            if project.id != store.selectedProjectID {
                                                await store.selectProject(id: project.id)
                                            }
                                            pendingConfirmationAction = .rebootstrap(project)
                                        }
                                    },
                                    remove: {
                                        guard store.capabilities.canRemoveProjects else { return }
                                        pendingConfirmationAction = .remove(project)
                                    },
                                    supportsRebootstrap: store.capabilities.canRebootstrapProjects,
                                    supportsRemove: store.capabilities.canRemoveProjects
                                )
                            }
                        }
                    }
                }
            }

            Spacer()

            AppButton("Add Another Repo", variant: .primary, action: presentSetup)
        }
        .padding(AppTheme.Spacing.xl)
        .background(ControlCenterSidebarFill())
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.shell, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.shell, style: .continuous)
                .strokeBorder(AppTheme.Colors.border(for: colorScheme), lineWidth: 1)
        )
    }

    @Environment(\.colorScheme) private var colorScheme

    private var confirmationTitle: String {
        switch pendingConfirmationAction {
        case .remove:
            "Remove project?"
        case .rebootstrap:
            "Re-bootstrap project?"
        case .none:
            ""
        }
    }

    private var confirmationMessage: String {
        switch pendingConfirmationAction {
        case .remove(let project):
            "This will remove \(project.projectName) from the local runtime index."
        case .rebootstrap(let project):
            "This will refresh framework-owned files and runtime checks for \(project.projectName)."
        case .none:
            ""
        }
    }

    private func syncSelectedSession() {
        selectedSessionID = projectDetail?.activeSession?.id ?? projectDetail?.sessions.first?.id
    }

    private func isProjectActive(_ project: RegisteredProject) -> Bool {
        if project.id == projectDetail?.activeSession?.projectID {
            return true
        }
        guard let latestSessionStartedAt = project.latestSessionStartedAt else {
            return false
        }
        return latestSessionStartedAt > Date().addingTimeInterval(-7_200)
    }

    private func projectNeedsAttention(_ project: RegisteredProject) -> Bool {
        project.skippedItems.isEmpty == false || project.createdItems.count < 5
    }

    private func projectStatusRank(_ project: RegisteredProject) -> Int {
        if isProjectActive(project) { return 3 }
        if projectNeedsAttention(project) { return 2 }
        if project.sessionCount > 0 { return 1 }
        return 0
    }

    private func badgeStatus(for project: RegisteredProject) -> AppBadgeStatus {
        if isProjectActive(project) {
            return .healthy
        }
        if projectNeedsAttention(project) {
            return .warning
        }
        if project.sessionCount == 0 {
            return .idle
        }
        return .healthy
    }

    private func openURL(path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

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

private struct SearchField: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            AppIcon(systemName: "magnifyingglass", size: 14)
            TextField("Search projects", text: $text)
                .textFieldStyle(.plain)
                .font(AppTheme.Typography.body(15, weight: .semibold))
                .focused(isFocused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.Colors.foregroundSecondary(for: colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(height: AppTheme.Layout.controlHeight)
        .background(AppInsetSurface(emphasized: false, cornerRadius: AppTheme.Radius.xl - 4))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl - 4, style: .continuous)
                .strokeBorder(AppTheme.Colors.chromeGlow(for: colorScheme).opacity(0.28), lineWidth: 1)
                .blur(radius: 12)
                .opacity(text.isEmpty ? 0 : 0.85)
        )
    }
}

private struct ProjectSidebarRow: View {
    let project: RegisteredProject
    let isSelected: Bool
    let status: AppBadgeStatus
    let action: () -> Void
    let openRepository: () -> Void
    let rebootstrap: () -> Void
    let remove: () -> Void
    let supportsRebootstrap: Bool
    let supportsRemove: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            Button(action: action) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Text(project.projectName)
                            .font(AppTheme.Typography.headline(14, weight: .bold))
                            .lineLimit(1)
                        Spacer()
                        AppBadge(status: status)
                    }

                    Text(project.projectPath)
                        .font(AppTheme.Typography.mono(11, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.foregroundSecondary(for: colorScheme))
                        .lineLimit(1)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            DetailPill(text: project.projectType.displayName)
                            ForEach(project.platforms, id: \.id) { platform in
                                DetailPill(text: platform.displayName)
                            }
                        }
                    }

                    Text(lastSessionCopy)
                        .font(AppTheme.Typography.body(12, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.foregroundSecondary(for: colorScheme))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.md)
                .background(SidebarProjectFill(isSelected: isSelected, isHovered: isHovered))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            Menu {
                Button("Open Repository", action: openRepository)
                Button("Re-bootstrap", action: rebootstrap)
                    .disabled(!supportsRebootstrap)
                Divider()
                Button("Remove", role: .destructive, action: remove)
                    .disabled(!supportsRemove)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: AppTheme.Layout.minimumTapTarget, height: AppTheme.Layout.minimumTapTarget)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                            .fill(AppTheme.Colors.secondaryFill(for: colorScheme).opacity(isHovered ? 0.9 : 0.65))
                    )
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var lastSessionCopy: String {
        if let latestSessionStartedAt = project.latestSessionStartedAt {
            return "Last session \(latestSessionStartedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return "No sessions started yet"
    }
}

private struct ProjectSidebarSkeleton: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
            .fill(AppTheme.Colors.insetSurfaceTint(for: colorScheme))
            .frame(height: 128)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(AppTheme.Colors.border(for: colorScheme), lineWidth: 1)
            )
            .redacted(reason: .placeholder)
    }
}

private struct SidebarProjectFill: View {
    let isSelected: Bool
    let isHovered: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
            .fill(
                isSelected
                    ? AppTheme.Colors.elevatedSurfaceTint(for: colorScheme)
                    : AppTheme.Colors.insetSurfaceTint(for: colorScheme).opacity(isHovered ? 0.92 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? AppTheme.Colors.primaryFill(for: colorScheme)
                            : (isHovered ? AppTheme.Colors.borderStrong(for: colorScheme) : AppTheme.Colors.border(for: colorScheme)),
                        lineWidth: isSelected ? 1.4 : 1
                    )
            )
            .shadow(
                color: AppTheme.Colors.chromeGlow(for: colorScheme).opacity(isSelected ? 0.26 : (isHovered ? 0.12 : 0)),
                radius: isSelected ? 18 : 10,
                x: 0,
                y: isSelected ? 10 : 4
            )
    }
}

private struct ControlCenterSidebarFill: View {
    var body: some View {
        AppGlassSurface(
            cornerRadius: AppTheme.Radius.shell,
            material: .thinMaterial,
            tintOpacityDark: 0.05,
            tintOpacityLight: 0.20
        )
    }
}

private struct ProjectHeaderCard: View {
    let projectDetail: ProjectDetail
    let canStartSession: Bool
    let startSession: () -> Void
    let openRepository: () -> Void

    var body: some View {
        AppCard(padding: AppTheme.Spacing.xxl, cornerRadius: AppTheme.Radius.xl, interactive: true) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        AppBadge(status: projectDetail.activeSession == nil ? .idle : .healthy)
                        Text(projectDetail.project.projectName)
                            .font(AppTheme.Typography.display(38))
                        Text(projectDetail.project.projectDescription)
                            .font(AppTheme.Typography.body(14, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(projectDetail.project.projectPath)
                            .font(AppTheme.Typography.mono(12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: AppTheme.Spacing.sm) {
                        DetailPill(text: "Approval: \(projectDetail.settings.approvalMode.displayName)")
                        DetailPill(text: "Memory: \(projectDetail.settings.memoryMode.displayName)")
                        DetailPill(text: projectDetail.activeSession == nil ? "Standby" : "Live Session")
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        DetailPill(text: projectDetail.project.projectType.displayName)
                        ForEach(projectDetail.project.platforms, id: \.id) { platform in
                            DetailPill(text: platform.displayName)
                        }
                        ForEach(projectDetail.project.agentTools, id: \.id) { tool in
                            DetailPill(text: tool.displayName)
                        }
                    }
                }

                HStack(spacing: AppTheme.Spacing.sm) {
                    AppButton(
                        "Start Session",
                        variant: .primary,
                        isDisabled: !canStartSession,
                        action: startSession
                    )
                    AppButton("Open Repo", variant: .secondary, action: openRepository)
                }

                HStack(spacing: AppTheme.Spacing.md) {
                    SummaryMetric(title: "Sessions", value: "\(projectDetail.project.sessionCount)")
                    SummaryMetric(title: "Framework", value: "\(projectDetail.frameworkHealth.filter { $0.status == .present }.count)/\(projectDetail.frameworkHealth.count)")
                    SummaryMetric(title: "Pending", value: "\(projectDetail.pendingProposals.count)")
                }

                if !canStartSession {
                    Text("Starting sessions is unavailable until the connected runtime supports Phase 3 session controls.")
                        .font(AppTheme.Typography.body(12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct FrameworkHealthSection: View {
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

private struct ProposalPanel: View {
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

private struct ActiveSessionBanner: View {
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

private struct SessionHistorySection: View {
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

private struct SessionDetailDrawer: View {
    let session: SessionRecord?

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SectionHeader(title: "Session Detail", subtitle: "Transcript summary, task roles, and live logs")

                if let session {
                    Text(session.transcriptSummary ?? "No transcript summary is available for this session yet.")
                        .font(AppTheme.Typography.body(14, weight: .semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("Task Progress")
                            .font(AppTheme.Typography.mono(12, weight: .black))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        if session.taskProgress.isEmpty {
                            Text("No task progress captured.")
                                .font(AppTheme.Typography.body(12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(session.taskProgress) { task in
                                HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                                    AppBadge(status: badgeStatus(for: task))
                                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                        Text(task.title)
                                            .font(AppTheme.Typography.body(13, weight: .bold))
                                        Text(task.agentRole.displayName)
                                            .font(AppTheme.Typography.mono(11, weight: .black))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }

                    SessionLogStreamView(entries: session.logEntries)
                } else {
                    Text("Choose a session to inspect its summary, task progress, and log output.")
                        .font(AppTheme.Typography.body(13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func badgeStatus(for task: SessionTaskProgress) -> AppBadgeStatus {
        switch task.status {
        case .completed:
            return .healthy
        case .running:
            return .warning
        case .blocked:
            return .error
        case .pending:
            return .idle
        }
    }
}

private struct SessionLogStreamView: View {
    let entries: [SessionLogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Log Stream")
                .font(AppTheme.Typography.mono(12, weight: .black))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if entries.isEmpty {
                Text("No log lines captured yet.")
                    .font(AppTheme.Typography.body(12, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            ForEach(entries) { entry in
                                Text("[\(entry.timestamp.formatted(date: .omitted, time: .standard))] \(entry.level.uppercased())  \(entry.message)")
                                    .font(AppTheme.Typography.mono(11, weight: .medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(entry.id)
                            }
                        }
                    }
                    .frame(minHeight: 180, maxHeight: 220)
                    .padding(AppTheme.Spacing.md)
                    .background(AppInsetSurface(emphasized: false, cornerRadius: AppTheme.Radius.md))
                    .onAppear {
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: entries.map(\.id)) { _, _ in
                        scrollToBottom(proxy: proxy)
                    }
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastID = entries.last?.id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }
}

private struct SessionSummarySection: View {
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

private struct ProjectSettingsPanel: View {
    let settings: ProjectSettingsSnapshot
    let supportsSaving: Bool
    let save: (ProjectSettingsSnapshot) -> Void

    @State private var approvalMode: ApprovalMode
    @State private var memoryMode: MemoryMode
    @State private var improvementMode: ImprovementMode

    init(settings: ProjectSettingsSnapshot, supportsSaving: Bool, save: @escaping (ProjectSettingsSnapshot) -> Void) {
        self.settings = settings
        self.supportsSaving = supportsSaving
        self.save = save
        _approvalMode = State(initialValue: settings.approvalMode)
        _memoryMode = State(initialValue: settings.memoryMode)
        _improvementMode = State(initialValue: settings.improvementMode)
    }

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                SectionHeader(title: "Project Settings", subtitle: "Approval, memory, and improvement defaults")

                Picker("Approval Mode", selection: $approvalMode) {
                    ForEach(ApprovalMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!supportsSaving)

                Picker("Memory Mode", selection: $memoryMode) {
                    ForEach(MemoryMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!supportsSaving)

                Picker("Improvement Mode", selection: $improvementMode) {
                    ForEach(ImprovementMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!supportsSaving)

                AppButton("Save Settings", variant: .primary, isDisabled: !supportsSaving) {
                    save(
                        ProjectSettingsSnapshot(
                            approvalMode: approvalMode,
                            memoryMode: memoryMode,
                            improvementMode: improvementMode
                        )
                    )
                }

                if !supportsSaving {
                    Text("Project settings are read-only on the current runtime. The live daemon does not support persisting these Phase 3 settings yet.")
                        .font(AppTheme.Typography.body(12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: settings) { _, newValue in
            approvalMode = newValue.approvalMode
            memoryMode = newValue.memoryMode
            improvementMode = newValue.improvementMode
        }
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(title)
                .font(AppTheme.Typography.mono(11, weight: .black))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(AppTheme.Typography.headline(20, weight: .black))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(title)
                .font(AppTheme.Typography.mono(12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(subtitle)
                .font(AppTheme.Typography.body(12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct DetailPill: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(AppTheme.Typography.mono(11, weight: .semibold))
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(
                Capsule()
                    .fill(AppTheme.Colors.secondaryFill(for: colorScheme).opacity(colorScheme == .dark ? 0.82 : 0.72))
            )
            .overlay(
                Capsule()
                    .strokeBorder(AppTheme.Colors.border(for: colorScheme), lineWidth: 1)
            )
    }
}

private struct SidebarMetaMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
            Text(title)
                .font(AppTheme.Typography.mono(10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(AppTheme.Typography.headline(18, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
