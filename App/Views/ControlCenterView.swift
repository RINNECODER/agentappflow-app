import AppKit
import SwiftUI

private enum ControlCenterTab: String, CaseIterable, Identifiable {
    case dashboard
    case project
    case activity
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .project: "Project"
        case .activity: "Activity"
        case .settings: "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .project: "folder"
        case .activity: "clock.arrow.circlepath"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct ControlCenterView: View {
    @ObservedObject var store: AppRuntimeStore
    let projectDetail: ProjectDetail
    let presentSetup: () -> Void

    @State private var selectedTab: ControlCenterTab = .dashboard

    private var project: RegisteredProject { projectDetail.project }
    private var latestSession: SessionRecord? { projectDetail.latestSession }

    var body: some View {
        NavigationShell {
            ControlCenterSidebar(
                store: store,
                currentProjectID: project.id,
                selectedTab: $selectedTab,
                presentSetup: presentSetup
            )
        } mainContent: {
            ControlCenterHero(
                project: project,
                latestSession: latestSession
            )

            switch selectedTab {
            case .dashboard:
                DashboardTab(
                    project: project,
                    latestSession: latestSession,
                    startSession: startSession
                )
            case .project:
                ProjectTab(project: project)
            case .activity:
                ActivityTab(
                    project: project,
                    latestSession: latestSession,
                    startSession: startSession
                )
            case .settings:
                SettingsTab(
                    project: project,
                    runtimeHealth: store.runtimeHealth,
                    errorMessage: store.errorMessage,
                    presentSetup: presentSetup
                )
            }
        }
        .frame(
            minWidth: AppTheme.Layout.controlCenterMinSize.width,
            minHeight: AppTheme.Layout.controlCenterMinSize.height
        )
    }

    private func startSession() {
        Task {
            await store.startSession()
        }
    }
}

private struct ControlCenterSidebar: View {
    @ObservedObject var store: AppRuntimeStore
    let currentProjectID: String
    @Binding var selectedTab: ControlCenterTab
    let presentSetup: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("WORKSPACES")
                    .font(AppTheme.Typography.mono(12, weight: .black))
                    .foregroundStyle(AppTheme.Colors.foregroundSecondary(for: colorScheme))
                    .textCase(.uppercase)

                if store.isLoading && store.projects.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        ProjectSidebarSkeleton()
                    }
                } else if store.projects.isEmpty {
                    AppCard(padding: AppTheme.Spacing.lg, cornerRadius: AppTheme.Radius.md) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            Text("No workspaces yet")
                                .font(AppTheme.Typography.headline(16, weight: .black))
                            Text("Register the first repo to populate the control center.")
                                .font(AppTheme.Typography.body(13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ForEach(store.projects) { project in
                        ProjectSidebarCard(
                            project: project,
                            isSelected: project.id == currentProjectID
                        ) {
                            Task {
                                await store.selectProject(id: project.id)
                            }
                        }
                    }
                }
            }

            VStack(spacing: AppTheme.Spacing.xs + 2) {
                ForEach(ControlCenterTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: AppTheme.Spacing.sm + 2) {
                            AppIcon(systemName: tab.symbolName, size: 16)
                                .frame(width: 18)
                            Text(tab.title)
                                .font(AppTheme.Typography.headline(14, weight: .black))
                            Spacer()
                        }
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .frame(height: AppTheme.Layout.controlHeight)
                        .background(SidebarTabFill(isSelected: selectedTab == tab))
                        .foregroundStyle(
                            selectedTab == tab
                                ? AppTheme.Colors.primaryForeground(for: colorScheme)
                                : AppTheme.Colors.foregroundPrimary(for: colorScheme)
                        )
                    }
                    .buttonStyle(.plain)
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
}

struct ControlCenterEmptyStateView: View {
    let presentSetup: () -> Void

    var body: some View {
        ZStack {
            AppBackground()

            AppCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    AppBadge(status: .idle)
                    Text("No projects registered")
                        .font(AppTheme.Typography.display(34))
                    Text("The control center is ready, but it does not have a workspace yet. Run onboarding to register the first repository.")
                        .font(AppTheme.Typography.body(15, weight: .semibold))
                        .foregroundStyle(.secondary)
                    AppButton("Start Onboarding", variant: .primary, action: presentSetup)
                }
            }
            .frame(maxWidth: 620)
        }
    }
}

private struct SidebarProjectFill: View {
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
            .fill(
                isSelected
                    ? AppTheme.Colors.elevatedSurfaceTint(for: colorScheme)
                    : AppTheme.Colors.insetSurfaceTint(for: colorScheme)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(
                        isSelected ? AppTheme.Colors.primaryFill(for: colorScheme) : AppTheme.Colors.border(for: colorScheme),
                        lineWidth: isSelected ? 1.4 : 1
                    )
            )
    }
}

private struct ProjectSidebarCard: View {
    let project: RegisteredProject
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Text(project.projectName.uppercased())
                        .font(AppTheme.Typography.headline(14, weight: .black))
                        .lineLimit(1)
                    Spacer()
                    AppBadge(status: project.latestSessionStartedAt == nil ? .idle : .healthy)
                }

                Text(project.projectPath)
                    .font(AppTheme.Typography.mono(11, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.foregroundSecondary(for: colorScheme))
                    .lineLimit(1)

                Text(sessionCopy)
                    .font(AppTheme.Typography.body(12, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.foregroundSecondary(for: colorScheme))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm + 2)
            .background(SidebarProjectFill(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }

    private var sessionCopy: String {
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
            .frame(height: 88)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(AppTheme.Colors.border(for: colorScheme), lineWidth: 1)
            )
            .redacted(reason: .placeholder)
    }
}

private struct SidebarTabFill: View {
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.lg - 2, style: .continuous)
            .fill(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg - 2, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
    }

    private var backgroundColor: Color {
        if isSelected {
            return AppTheme.Colors.primaryFill(for: colorScheme)
        }
        return AppTheme.Colors.secondaryFill(for: colorScheme)
    }

    private var borderColor: Color {
        if isSelected {
            return AppTheme.Colors.primaryFill(for: colorScheme)
        }
        return AppTheme.Colors.border(for: colorScheme)
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

private struct ControlCenterHero: View {
    let project: RegisteredProject
    let latestSession: SessionRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .center, spacing: AppTheme.Spacing.sm) {
                Text(project.projectName)
                    .font(AppTheme.Typography.display())
                AppBadge(status: latestSession == nil ? .idle : .healthy)
            }

            Text(
                "\(project.projectType.displayName) • \(project.platforms.map(\.displayName).joined(separator: " • "))"
            )
            .font(AppTheme.Typography.headline(17, weight: .bold))
            .foregroundStyle(.secondary)

            if let latestSession {
                Text("Latest session: \(latestSession.title)")
                    .font(AppTheme.Typography.body(14, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DashboardTab: View {
    let project: RegisteredProject
    let latestSession: SessionRecord?
    let startSession: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            HStack(spacing: AppTheme.Spacing.lg) {
                MetricBlock(
                    title: "Created Files",
                    value: "\(project.createdItems.count)",
                    detail: "framework outputs"
                )
                MetricBlock(
                    title: "Active Agents",
                    value: "\(project.agentTools.count)",
                    detail: project.agentTools.map(\.displayName).joined(separator: " + ")
                )
                MetricBlock(
                    title: "Sessions",
                    value: "\(project.sessionCount)",
                    detail: latestSession?.status.capitalized ?? "No session yet"
                )
            }

            HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
                ProjectOverviewBlock(project: project, latestSession: latestSession)
                QuickActionsBlock(project: project, startSession: startSession)
            }

            ContractFilesBlock(project: project)
        }
    }
}

private struct ProjectTab: View {
    let project: RegisteredProject

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProjectOverviewBlock(project: project, latestSession: nil)
            ContractFilesBlock(project: project)
        }
    }
}

private struct ActivityTab: View {
    let project: RegisteredProject
    let latestSession: SessionRecord?
    let startSession: () -> Void

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Recent Activity")
                    .font(AppTheme.Typography.mono(12, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                ActivityRow(
                    title: "Project registered",
                    subtitle: project.registeredAt.formatted(date: .abbreviated, time: .shortened)
                )
                ActivityRow(
                    title: "Framework bootstrapped",
                    subtitle: project.lastBootstrappedAt.formatted(date: .abbreviated, time: .shortened)
                )

                if let latestSession {
                    ActivityRow(
                        title: latestSession.title,
                        subtitle: latestSession.startedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                } else {
                    AppButton("Start First Session", variant: .primary, action: startSession)
                }
            }
        }
    }
}

private struct SettingsTab: View {
    @EnvironmentObject private var themeController: ThemeController
    let project: RegisteredProject
    let runtimeHealth: RuntimeHealth?
    let errorMessage: String?
    let presentSetup: () -> Void

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                Text("Workspace")
                    .font(AppTheme.Typography.mono(12, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                Text(project.projectPath)
                    .font(AppTheme.Typography.mono(13, weight: .medium))

                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("Appearance")
                        .font(AppTheme.Typography.mono())
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    ThemeModePicker(selection: $themeController.selection)
                }

                if let runtimeHealth {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        AppBadge(status: runtimeHealth.status.lowercased() == "ok" ? .healthy : .idle)
                        Text("Runtime \(runtimeHealth.status) • v\(runtimeHealth.version)")
                            .font(AppTheme.Typography.body(13, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(AppTheme.Typography.body(13, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.destructive)
                }

                AppButton("Register Another Repo", variant: .primary, action: presentSetup)
            }
        }
    }
}

private struct MetricBlock: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text(title)
                    .font(AppTheme.Typography.mono(12, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(AppTheme.Typography.display(44))
                Text(detail)
                    .font(AppTheme.Typography.headline(14, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 188, alignment: .topLeading)
    }
}

private struct ProjectOverviewBlock: View {
    let project: RegisteredProject
    let latestSession: SessionRecord?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl - 2) {
                Text("Project Contract")
                    .font(AppTheme.Typography.mono(12, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: AppTheme.Spacing.md + 2) {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.xl - 2, style: .continuous)
                        .fill(AppTheme.Colors.primaryFill(for: colorScheme))
                        .frame(width: 120, height: 120)
                        .overlay(
                            AppIcon(
                                systemName: "folder.badge.gearshape",
                                size: 34,
                                weight: .bold,
                                color: Color(nsColor: .windowBackgroundColor)
                            )
                        )

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text(project.projectName)
                            .font(AppTheme.Typography.headline(28, weight: .black))
                        Text(project.projectPath)
                            .font(AppTheme.Typography.mono(13, weight: .medium))
                            .foregroundStyle(.secondary)

                        HStack(spacing: AppTheme.Spacing.xs + 2) {
                            DetailPill(text: project.projectType.displayName)
                            DetailPill(text: project.platforms.map(\.displayName).joined(separator: " + "))
                        }

                        Text(
                            latestSession != nil
                                ? "Latest session \(latestSession!.startedAt.formatted(date: .abbreviated, time: .shortened))"
                                : "No sessions started yet"
                        )
                        .font(AppTheme.Typography.body(13, weight: .bold))
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct QuickActionsBlock: View {
    let project: RegisteredProject
    let startSession: () -> Void

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                Text("Quick Actions")
                    .font(AppTheme.Typography.mono(12, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.sm + 2) {
                    QuickActionTile(title: "Start Session", symbolName: "play.circle", action: startSession)
                    QuickActionTile(title: "Open Repo", symbolName: "folder") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: project.projectPath))
                    }
                    QuickActionTile(title: "AGENTS", symbolName: "doc.text") {
                        NSWorkspace.shared.open(
                            URL(fileURLWithPath: project.projectPath).appendingPathComponent("AGENTS.md")
                        )
                    }
                    QuickActionTile(title: "YAML", symbolName: "gearshape.2") {
                        NSWorkspace.shared.open(
                            URL(fileURLWithPath: project.projectPath)
                                .appendingPathComponent(".agentappflow/project.yaml")
                        )
                    }
                }
            }
        }
        .frame(width: 320)
    }
}

private struct ContractFilesBlock: View {
    let project: RegisteredProject

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Contract Files")
                    .font(AppTheme.Typography.mono(12, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                ForEach(project.createdItems, id: \.self) { item in
                    HStack {
                        Text(item)
                            .font(AppTheme.Typography.mono(13, weight: .medium))
                        Spacer()
                        Text("created")
                            .font(AppTheme.Typography.mono(11, weight: .black))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, AppTheme.Spacing.xxs)
                }

                if !project.skippedItems.isEmpty {
                    AppDivider()
                    ForEach(project.skippedItems, id: \.self) { item in
                        HStack {
                            Text(item)
                                .font(AppTheme.Typography.mono(13, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("kept")
                                .font(AppTheme.Typography.mono(11, weight: .black))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

private struct QuickActionTile: View {
    let title: String
    let symbolName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppTheme.Spacing.sm + 2) {
                AppIcon(systemName: symbolName, size: 20, weight: .bold)
                Text(title)
                    .font(AppTheme.Typography.headline(13, weight: .black))
            }
            .frame(maxWidth: .infinity, minHeight: 118)
            .background(QuickActionFill())
        }
        .buttonStyle(.plain)
    }
}

private struct QuickActionFill: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
            .fill(.thinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(AppTheme.Colors.elevatedSurfaceTint(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(AppTheme.Colors.border(for: colorScheme), lineWidth: 1)
            )
    }
}

private struct DetailPill: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(AppTheme.Typography.mono(11, weight: .black))
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs + 1)
            .background(
                Capsule()
                    .fill(.thinMaterial)
                    .overlay(
                        Capsule()
                            .fill(AppTheme.Colors.elevatedSurfaceTint(for: colorScheme))
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(AppTheme.Colors.border(for: colorScheme), lineWidth: 1)
            )
    }
}

private struct ActivityRow: View {
    let title: String
    let subtitle: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm + 2) {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md - 2, style: .continuous)
                .fill(AppTheme.Colors.secondaryFill(for: colorScheme))
                .frame(width: 46, height: 46)
                .overlay(AppIcon(systemName: "clock.arrow.circlepath", size: 16))

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(title)
                    .font(AppTheme.Typography.headline(15, weight: .black))
                Text(subtitle)
                    .font(AppTheme.Typography.body(13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
