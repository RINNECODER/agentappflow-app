import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var runtimeStore: AppRuntimeStore
    @EnvironmentObject private var preferencesStore: AppPreferencesStore
    @State private var isPresentingSetup = false
    @State private var hasCompletedInitialLoad = false

    var body: some View {
        currentScene
            .background(WindowConfigurator(minimumSize: minimumWindowSize))
            .toolbar { toolbarContent }
            .overlay(alignment: .topTrailing) {
                if let toast = runtimeStore.presentation.activeToast {
                    ToastBannerView(toast: toast) {
                        runtimeStore.dismissToast()
                    }
                    .padding(.top, AppTheme.Spacing.xxxl)
                    .padding(.trailing, AppTheme.Spacing.xl)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .overlay {
                if let progressHUD = runtimeStore.presentation.progressHUD {
                    ProgressHUDView(progressHUD: progressHUD)
                }
            }
            .task {
                await runtimeStore.loadProjects()
                hasCompletedInitialLoad = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .agentAppFlowPresentSetup)) { _ in
                presentSetup()
            }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button {
                presentSetup()
            } label: {
                Label("New Project", systemImage: "plus")
            }

            SettingsLink {
                Label("Preferences", systemImage: "slider.horizontal.3")
            }

            RuntimeHealthToolbarItem(runtimeHealth: runtimeStore.runtimeHealth)
        }
    }

    @ViewBuilder
    private var currentScene: some View {
        if shouldPresentSetup {
            FirstRunSetupView(
                runtimeService: runtimeStore.runtimeService,
                defaultApprovalMode: preferencesStore.defaultApprovalMode,
                pythonFrameworkOverride: preferencesStore.pythonFrameworkOverride,
                completeInitialSetup: completeInitialSetup
            )
        } else if runtimeStore.isLoading {
            RuntimeLoadingView()
        } else if shouldPresentRuntimeError {
            RuntimeErrorView(
                message: runtimeStore.presentation.errorMessage ?? "Unknown runtime error.",
                retryLoad: retryLoad,
                presentSetup: presentSetup
            )
        } else if runtimeStore.selectedProjectDetail != nil {
            ControlCenterView(
                store: runtimeStore,
                presentSetup: presentSetup
            )
        } else if hasCompletedInitialLoad && !runtimeStore.isLoading && runtimeStore.presentation.errorMessage == nil {
            ControlCenterEmptyStateView(presentSetup: presentSetup)
        } else {
            RuntimeLoadingView()
        }
    }

    private var shouldPresentSetup: Bool {
        isPresentingSetup
    }

    private func completeInitialSetup(projectID: String) {
        isPresentingSetup = false
        Task {
            await runtimeStore.loadProjects(select: projectID)
            hasCompletedInitialLoad = true
        }
    }

    private func presentSetup() {
        isPresentingSetup = true
    }

    private var shouldPresentRuntimeError: Bool {
        hasCompletedInitialLoad
            && !isPresentingSetup
            && !runtimeStore.isLoading
            && runtimeStore.presentation.errorMessage != nil
            && runtimeStore.selectedProjectDetail == nil
            && runtimeStore.projects.isEmpty
    }

    private func retryLoad() {
        Task {
            await runtimeStore.loadProjects()
            hasCompletedInitialLoad = true
        }
    }

    private var minimumWindowSize: CGSize {
        if shouldPresentSetup {
            return AppTheme.Layout.setupMinSize
        }

        if runtimeStore.selectedProjectDetail != nil {
            return AppTheme.Layout.controlCenterMinSize
        }

        return AppTheme.Layout.minWindowSize
    }
}

private struct RuntimeHealthToolbarItem: View {
    let runtimeHealth: RuntimeHealth?

    var body: some View {
        Label {
            Text(title)
                .font(AppTheme.Typography.body(13, weight: .bold))
        } icon: {
            RuntimeStatusDot(runtimeHealth: runtimeHealth)
        }
        .help(helpText)
    }

    private var title: String {
        guard let runtimeHealth else {
            return "Runtime unknown"
        }
        if runtimeHealth.hasDegradedSubsystems {
            return "Runtime Degraded"
        }
        return "Runtime \(runtimeHealth.status.capitalized)"
    }

    private var helpText: String {
        guard let runtimeHealth else {
            return "Runtime health has not been loaded yet."
        }
        let subsystemSummary = runtimeHealth.subsystems
            .map { "\($0.name): \($0.status)" }
            .joined(separator: " • ")
        return subsystemSummary.isEmpty
            ? "Runtime \(runtimeHealth.status) • v\(runtimeHealth.version)"
            : "Runtime \(runtimeHealth.status) • v\(runtimeHealth.version) • \(subsystemSummary)"
    }
}

private struct ToastBannerView: View {
    let toast: AppToastMessage
    let dismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var accentColor: Color {
        switch toast.style {
        case .success:
            AppTheme.Colors.healthy
        case .warning:
            AppTheme.Colors.warning
        case .error:
            AppTheme.Colors.destructive
        }
    }

    var body: some View {
        AppCard(padding: AppTheme.Spacing.lg, cornerRadius: AppTheme.Radius.md, interactive: true) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(accentColor.opacity(colorScheme == .dark ? 0.22 : 0.14))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: iconName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(accentColor)
                    }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(toast.title)
                        .font(AppTheme.Typography.headline(15, weight: .bold))
                    Text(toast.message)
                        .font(AppTheme.Typography.body(13, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.foregroundSecondary(for: colorScheme))
                }

                Spacer(minLength: AppTheme.Spacing.lg)

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss notification")
            }
        }
        .frame(maxWidth: 420)
    }

    private var iconName: String {
        switch toast.style {
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .error:
            "xmark.octagon.fill"
        }
    }
}

private struct ProgressHUDView: View {
    let progressHUD: ProgressHUDState

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.18))
                .ignoresSafeArea()

            AppCard(padding: AppTheme.Spacing.xxl, interactive: true) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    AppBadge(status: .healthy)
                    ProgressView()
                        .controlSize(.large)
                    Text(progressHUD.title)
                        .font(AppTheme.Typography.display(26))
                    Text(progressHUD.message)
                        .font(AppTheme.Typography.body(13, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.foregroundSecondary(for: .dark))
                }
            }
            .frame(maxWidth: 420)
        }
    }
}

private struct RuntimeLoadingView: View {
    var body: some View {
        ZStack {
            AppBackground()

            AppCard(padding: AppTheme.Spacing.xxl, interactive: true) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    AppBadge(status: .idle)
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading local runtime")
                        .font(AppTheme.Typography.display(28))
                    Text("Reading registered projects and runtime health from the local AgentAppFlow daemon.")
                        .font(AppTheme.Typography.body(14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("The shell is preparing projects, sessions, and workspace state.")
                        .font(AppTheme.Typography.mono(12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 560)
        }
    }
}

private struct RuntimeErrorView: View {
    let message: String
    let retryLoad: () -> Void
    let presentSetup: () -> Void

    var body: some View {
        ZStack {
            AppBackground()

            AppCard(padding: AppTheme.Spacing.xxl, interactive: true) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    AppBadge(status: .error)
                    Text("Local runtime unavailable")
                        .font(AppTheme.Typography.display(30))
                    Text(message)
                        .font(AppTheme.Typography.body())
                        .foregroundStyle(.secondary)
                    HStack(spacing: AppTheme.Spacing.sm) {
                        AppButton("Retry", variant: .secondary, action: retryLoad)
                        AppButton("Open Setup", variant: .primary, action: presentSetup)
                    }
                }
            }
            .frame(maxWidth: 620)
        }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    let minimumSize: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindowIfNeeded(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindowIfNeeded(for: nsView)
        }
    }

    private func configureWindowIfNeeded(for view: NSView) {
        guard let window = view.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = minimumSize
    }
}
