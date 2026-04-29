import SwiftUI

@main
struct AgentAppFlowApp: App {
    @StateObject private var themeController = ThemeController()
    @StateObject private var runtimeStore = AppRuntimeStore()
    @StateObject private var preferencesStore = AppPreferencesStore()

    var body: some Scene {
        WindowGroup {
            ContentView(runtimeStore: runtimeStore)
                .environmentObject(themeController)
                .environmentObject(preferencesStore)
                .preferredColorScheme(themeController.selection.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(
            width: AppTheme.Layout.defaultWindowSize.width,
            height: AppTheme.Layout.defaultWindowSize.height
        )
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            AgentAppFlowCommands()
        }

        Settings {
            AppPreferencesView()
                .environmentObject(themeController)
                .environmentObject(preferencesStore)
                .preferredColorScheme(themeController.selection.colorScheme)
        }

        MenuBarExtra {
            RuntimeMenuBarContent(runtimeStore: runtimeStore)
                .environmentObject(themeController)
                .environmentObject(preferencesStore)
                .preferredColorScheme(themeController.selection.colorScheme)
        } label: {
            RuntimeStatusLabel(runtimeHealth: runtimeStore.runtimeHealth)
                .help(runtimeHealthTooltip)
        }
        .menuBarExtraStyle(.window)
    }

    private var runtimeHealthTooltip: String {
        guard let runtimeHealth = runtimeStore.runtimeHealth else {
            return "Runtime status unavailable"
        }
        return "Runtime \(runtimeHealth.status) • v\(runtimeHealth.version)"
    }
}

private struct RuntimeMenuBarContent: View {
    @ObservedObject var runtimeStore: AppRuntimeStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.sm) {
                RuntimeStatusDot(runtimeHealth: runtimeStore.runtimeHealth)
                Text(runtimeLabel)
                    .font(AppTheme.Typography.headline(14, weight: .black))
            }

            if let runtimeHealth = runtimeStore.runtimeHealth {
                Text("Version \(runtimeHealth.version)")
                    .font(AppTheme.Typography.body(13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("New Project") {
                NotificationCenter.default.post(name: .agentAppFlowPresentSetup, object: nil)
            }

            Button("Reload Runtime") {
                Task {
                    await runtimeStore.loadProjects(select: runtimeStore.selectedProjectID)
                }
            }

            SettingsLink {
                Text("Preferences…")
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(minWidth: 220, alignment: .leading)
    }

    private var runtimeLabel: String {
        guard let runtimeHealth = runtimeStore.runtimeHealth else {
            return "Runtime unavailable"
        }
        return "Runtime \(runtimeHealth.status.capitalized)"
    }
}

private struct RuntimeStatusLabel: View {
    let runtimeHealth: RuntimeHealth?

    var body: some View {
        RuntimeStatusDot(runtimeHealth: runtimeHealth)
    }
}

struct RuntimeStatusDot: View {
    let runtimeHealth: RuntimeHealth?

    private var color: Color {
        guard let status = runtimeHealth?.status.lowercased() else {
            return AppTheme.Colors.warning
        }
        switch status {
        case "ok":
            return AppTheme.Colors.healthy
        case "degraded", "warning":
            return AppTheme.Colors.warning
        default:
            return AppTheme.Colors.destructive
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1)
            )
    }
}

private struct AgentAppFlowCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project") {
                NotificationCenter.default.post(name: .agentAppFlowPresentSetup, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("AgentAppFlow") {
            Button("Focus Search") {
                NotificationCenter.default.post(name: .agentAppFlowFocusSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Toggle Sidebar") {
                NotificationCenter.default.post(name: .agentAppFlowToggleSidebar, object: nil)
            }
            .keyboardShortcut("S", modifiers: [.command, .shift])
        }
    }
}

extension Notification.Name {
    static let agentAppFlowPresentSetup = Notification.Name("agentAppFlowPresentSetup")
    static let agentAppFlowFocusSearch = Notification.Name("agentAppFlowFocusSearch")
    static let agentAppFlowToggleSidebar = Notification.Name("agentAppFlowToggleSidebar")
}
