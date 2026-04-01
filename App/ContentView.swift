import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var runtimeStore = AppRuntimeStore()
    @State private var isPresentingSetup = false
    @State private var hasCompletedInitialLoad = false

    var body: some View {
        currentScene
            .background(WindowConfigurator(minimumSize: minimumWindowSize))
        .task {
            await runtimeStore.loadProjects()
            hasCompletedInitialLoad = true
        }
    }

    @ViewBuilder
    private var currentScene: some View {
        if shouldPresentSetup {
            FirstRunSetupView(
                runtimeService: runtimeStore.runtimeService,
                completeInitialSetup: completeInitialSetup
            )
        } else if runtimeStore.isLoading {
            RuntimeLoadingView()
        } else if shouldPresentRuntimeError {
            RuntimeErrorView(
                message: runtimeStore.errorMessage ?? "Unknown runtime error.",
                retryLoad: retryLoad,
                presentSetup: presentSetup
            )
        } else if let projectDetail = runtimeStore.selectedProjectDetail {
            ControlCenterView(
                store: runtimeStore,
                projectDetail: projectDetail,
                presentSetup: presentSetup
            )
        } else {
            RuntimeLoadingView()
        }
    }

    private var shouldPresentSetup: Bool {
        if isPresentingSetup {
            return true
        }

        return hasCompletedInitialLoad
            && !runtimeStore.isLoading
            && runtimeStore.errorMessage == nil
            && !runtimeStore.hasPersistedProjectSelection
            && runtimeStore.projects.isEmpty
            && runtimeStore.selectedProjectDetail == nil
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
            && runtimeStore.errorMessage != nil
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

private struct RuntimeLoadingView: View {
    var body: some View {
        ZStack {
            AppBackground()

            AppCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    AppBadge(status: .idle)
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading local runtime")
                        .font(AppTheme.Typography.display(30))
                    Text("Reading registered projects and runtime health from the local AgentAppFlow daemon.")
                        .font(AppTheme.Typography.body())
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

            AppCard {
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
