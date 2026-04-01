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
        case .dashboard:
            "Dashboard"
        case .project:
            "Project"
        case .activity:
            "Activity"
        case .settings:
            "Settings"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard:
            "square.grid.2x2"
        case .project:
            "folder"
        case .activity:
            "clock.arrow.circlepath"
        case .settings:
            "slider.horizontal.3"
        }
    }
}

struct ControlCenterView: View {
    let snapshot: WorkspaceSnapshot
    let resetInitialSetup: () -> Void

    @State private var selectedTab: ControlCenterTab = .dashboard

    var body: some View {
        ZStack {
            AgentAppFlowBackdrop()

            HStack(spacing: 16) {
                ControlCenterSidebar(
                    snapshot: snapshot,
                    selectedTab: $selectedTab,
                    resetInitialSetup: resetInitialSetup
                )
                .frame(width: 270)

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ControlCenterHero(snapshot: snapshot)

                            switch selectedTab {
                            case .dashboard:
                                DashboardTab(snapshot: snapshot)
                            case .project:
                                ProjectTab(snapshot: snapshot)
                            case .activity:
                                ActivityTab(snapshot: snapshot)
                            case .settings:
                                SettingsTab(
                                    snapshot: snapshot,
                                    resetInitialSetup: resetInitialSetup
                                )
                            }
                        }
                        .padding(24)
                        .padding(.top, 40)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .frame(minWidth: 1200, minHeight: 820)
    }
}

private struct ControlCenterSidebar: View {
    let snapshot: WorkspaceSnapshot
    @Binding var selectedTab: ControlCenterTab
    let resetInitialSetup: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("WORKSPACE")
                    .font(Font.brutalMeta(12, weight: .black))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(snapshot.projectName.uppercased())
                    .font(Font.brutalTitle(18, weight: .black))
                Text(snapshot.projectType.displayName)
                    .font(Font.brutalBody(13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(ControlCenterTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: tab.symbolName)
                                .frame(width: 18)
                            Text(tab.title)
                                .font(Font.brutalTitle(14, weight: .black))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 54)
                        .background(SidebarTabFill(isSelected: selectedTab == tab))
                        .foregroundStyle(selectedTab == tab ? selectedForeground : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Button("Set Up Another Repo", action: resetInitialSetup)
                .buttonStyle(BrutalButtonStyle(inverted: true))
        }
        .padding(22)
        .background(ControlCenterSidebarFill())
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var selectedForeground: Color {
        colorScheme == .dark ? .black : .white
    }
}

private struct SidebarTabFill: View {
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
    }

    private var backgroundColor: Color {
        if isSelected {
            return colorScheme == .dark ? .white : .black
        }
        return colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.42)
    }

    private var borderColor: Color {
        if isSelected {
            return colorScheme == .dark ? .white : .black
        }
        return colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }
}


private struct ControlCenterSidebarFill: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GlassSurface(
            cornerRadius: 0,
            material: .thinMaterial,
            tintOpacityDark: 0.05,
            tintOpacityLight: 0.20
        )
    }
}

private struct ControlCenterHero: View {
    let snapshot: WorkspaceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(snapshot.projectName)
                .font(Font.brutalHero(54))

            Text("\(snapshot.projectType.displayName) • \(snapshot.platforms.map(\.displayName).joined(separator: " • "))")
                .font(Font.brutalTitle(17, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct DashboardTab: View {
    let snapshot: WorkspaceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                MetricBlock(title: "Created Files", value: "\(snapshot.createdItems.count)", detail: "framework outputs")
                MetricBlock(title: "Active Agents", value: "\(snapshot.agentTools.count)", detail: snapshot.agentTools.map(\.displayName).joined(separator: " + "))
                MetricBlock(title: "Approval", value: snapshot.approvalMode.displayName, detail: snapshot.improvementMode.displayName)
            }

            HStack(alignment: .top, spacing: 18) {
                ProjectOverviewBlock(snapshot: snapshot)
                QuickActionsBlock(snapshot: snapshot)
            }

            ContractFilesBlock(snapshot: snapshot)
        }
    }
}

private struct ProjectTab: View {
    let snapshot: WorkspaceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProjectOverviewBlock(snapshot: snapshot)
            ContractFilesBlock(snapshot: snapshot)
        }
    }
}

private struct ActivityTab: View {
    let snapshot: WorkspaceSnapshot

    var body: some View {
        BrutalPanel {
            VStack(alignment: .leading, spacing: 16) {
                Text("Recent Activity")
                    .font(Font.brutalMeta(12, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                ActivityRow(title: "Workspace initialized", subtitle: snapshot.initializedAt.formatted(date: .abbreviated, time: .shortened))
                ActivityRow(title: "Created \(snapshot.createdItems.count) files", subtitle: snapshot.createdItems.prefix(3).joined(separator: " • "))
                ActivityRow(title: "Agent adapters ready", subtitle: snapshot.agentTools.map(\.displayName).joined(separator: " + "))
            }
        }
    }
}

private struct SettingsTab: View {
    let snapshot: WorkspaceSnapshot
    let resetInitialSetup: () -> Void

    var body: some View {
        BrutalPanel {
            VStack(alignment: .leading, spacing: 18) {
                Text("Workspace")
                    .font(Font.brutalMeta(12, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(snapshot.projectPath)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                Button("Reset Onboarding", action: resetInitialSetup)
                    .buttonStyle(BrutalButtonStyle(inverted: true))
            }
        }
    }
}

private struct MetricBlock: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        BrutalPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(Font.brutalMeta(12, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(Font.brutalHero(44))
                Text(detail)
                    .font(Font.brutalTitle(14, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 188, alignment: .topLeading)
    }
}

private struct ProjectOverviewBlock: View {
    let snapshot: WorkspaceSnapshot

    var body: some View {
        BrutalPanel {
            VStack(alignment: .leading, spacing: 20) {
                Text("Project Contract")
                    .font(Font.brutalMeta(12, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 16) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.primary)
                        .frame(width: 120, height: 120)
                        .overlay(
                            Image(systemName: "folder.badge.gearshape")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                        )

                    VStack(alignment: .leading, spacing: 10) {
                        Text(snapshot.projectName)
                            .font(Font.brutalTitle(28, weight: .black))
                        Text(snapshot.projectPath)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            DetailPill(text: snapshot.projectType.displayName)
                            DetailPill(text: snapshot.platforms.map(\.displayName).joined(separator: " + "))
                        }

                        Text("Initialized \(snapshot.initializedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(Font.brutalBody(13, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct QuickActionsBlock: View {
    let snapshot: WorkspaceSnapshot

    var body: some View {
        BrutalPanel {
            VStack(alignment: .leading, spacing: 18) {
                Text("Quick Actions")
                    .font(Font.brutalMeta(12, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    QuickActionTile(title: "Open Repo", symbolName: "folder") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: snapshot.projectPath))
                    }
                    QuickActionTile(title: "AGENTS", symbolName: "doc.text") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: snapshot.projectPath).appendingPathComponent("AGENTS.md"))
                    }
                    QuickActionTile(title: "CLAUDE", symbolName: "text.bubble") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: snapshot.projectPath).appendingPathComponent("CLAUDE.md"))
                    }
                    QuickActionTile(title: "YAML", symbolName: "gearshape.2") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: snapshot.projectPath).appendingPathComponent(".agentappflow/project.yaml"))
                    }
                }
            }
        }
        .frame(width: 320)
    }
}

private struct ContractFilesBlock: View {
    let snapshot: WorkspaceSnapshot

    var body: some View {
        BrutalPanel {
            VStack(alignment: .leading, spacing: 16) {
                Text("Contract Files")
                    .font(Font.brutalMeta(12, weight: .black))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                ForEach(snapshot.createdItems, id: \.self) { item in
                    HStack {
                        Text(item)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                        Spacer()
                        Text("created")
                            .font(Font.brutalMeta(11, weight: .black))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if !snapshot.skippedItems.isEmpty {
                    Divider()
                    ForEach(snapshot.skippedItems, id: \.self) { item in
                        HStack {
                            Text(item)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("kept")
                                .font(Font.brutalMeta(11, weight: .black))
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
            VStack(spacing: 12) {
                Image(systemName: symbolName)
                    .font(.system(size: 20, weight: .bold))
                Text(title)
                    .font(Font.brutalTitle(13, weight: .black))
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
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.thinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.24))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct DetailPill: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(Font.brutalMeta(11, weight: .black))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(.thinMaterial)
                    .overlay(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.26))
                    )
            )
    }
}

private struct ActivityRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 46, height: 46)
                .overlay(Image(systemName: "clock.arrow.circlepath"))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Font.brutalTitle(15, weight: .black))
                Text(subtitle)
                    .font(Font.brutalBody(13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct BrutalPanel<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.18))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}
