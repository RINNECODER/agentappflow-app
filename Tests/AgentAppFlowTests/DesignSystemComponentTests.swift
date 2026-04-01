import AppKit
import SwiftUI
import XCTest
@testable import AgentAppFlow

final class DesignSystemComponentTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    func testDesignSystemGalleryRendersInBothColorSchemes() throws {
        let lightData = try snapshotData(
            of: DesignSystemGallery(),
            size: CGSize(width: 960, height: 760),
            scheme: .light
        )
        let darkData = try snapshotData(
            of: DesignSystemGallery(),
            size: CGSize(width: 960, height: 760),
            scheme: .dark
        )

        XCTAssertFalse(lightData.isEmpty)
        XCTAssertFalse(darkData.isEmpty)
        XCTAssertNotEqual(lightData, darkData, "Light and dark gallery renders should differ.")
    }

    func testDisabledButtonRendersDifferentlyFromEnabledButton() throws {
        let enabledData = try snapshotData(
            of: AppButton("Continue", variant: .primary, action: {}),
            size: CGSize(width: 220, height: 80),
            scheme: .light
        )
        let disabledData = try snapshotData(
            of: AppButton("Continue", variant: .primary, isDisabled: true, action: {}),
            size: CGSize(width: 220, height: 80),
            scheme: .light
        )

        XCTAssertNotEqual(enabledData, disabledData, "Disabled buttons should have a distinct visual treatment.")
    }

    func testAppButtonMeetsMinimumTapTarget() {
        let size = fittingSize(
            of: AppButton("Continue", variant: .primary, action: {})
        )

        XCTAssertGreaterThanOrEqual(size.height, AppTheme.Layout.minimumTapTarget)
        XCTAssertGreaterThanOrEqual(size.width, AppTheme.Layout.minimumTapTarget)
    }

    func testThemeModePickerMeetsMinimumTapTarget() {
        let size = fittingSize(of: ThemeModePickerHarness())

        XCTAssertGreaterThanOrEqual(size.height, AppTheme.Layout.minimumTapTarget)
    }

    func testOnboardingStagesDeclareVoiceOverLabelsForInteractiveControls() {
        for stage in SetupStage.allCases {
            let labels = stage.interactiveAccessibilityLabels
            let unlabeled = labels.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let unlabeledDescription = unlabeled.joined(separator: ", ")

            XCTAssertFalse(labels.isEmpty, "Expected accessibility labels in stage \(stage.title).")
            XCTAssertTrue(
                unlabeled.isEmpty,
                "Missing VoiceOver labels in stage \(stage.title): \(unlabeledDescription)"
            )
        }
    }

    func testEveryOnboardingStageRendersInBothColorSchemes() throws {
        let repositoryURL = try makeGitRepository(named: "AgentAppFlowDemo")
        let formState = populatedFormState(repositoryURL: repositoryURL)
        let runtimeService = StubAgentRuntimeService(
            defaults: UserDefaults(suiteName: #function)!,
            storageKey: #function
        )

        for stage in SetupStage.allCases {
            let view = FirstRunSetupView(
                runtimeService: runtimeService,
                initialStage: stage,
                initialFormState: formState,
                initialCommandResult: sampleBootstrapResult,
                initialRegisteredProject: sampleProject(path: repositoryURL.path),
                initialPythonInspection: .readyPreview,
                completeInitialSetup: { _ in }
            )

            let lightData = try snapshotData(
                of: view,
                size: CGSize(width: 1100, height: 900),
                scheme: .light
            )
            let darkData = try snapshotData(
                of: view,
                size: CGSize(width: 1100, height: 900),
                scheme: .dark
            )

            XCTAssertFalse(lightData.isEmpty, "Expected light snapshot for stage \(stage.title)")
            XCTAssertFalse(darkData.isEmpty, "Expected dark snapshot for stage \(stage.title)")
        }
    }

    func testErrorScreensRender() throws {
        let repositoryURL = try makeGitRepository(named: "AgentAppFlowErrors")
        let formState = populatedFormState(repositoryURL: repositoryURL)

        let views: [AnyView] = [
            AnyView(PythonRuntimeStageView(inspection: .missingPreview)),
            AnyView(
                RepositoryStageView(
                    projectPath: .constant("/tmp/not-a-repo"),
                    projectPathState: .error("The selected folder is not a git repository."),
                    chooseRepositoryPath: {}
                )
            ),
            AnyView(
                InstallGateStageView(
                    formState: formState,
                    previewPlan: BootstrapPreviewPlan(request: try formState.makeRequest()),
                    isInitializing: false,
                    bootstrapError: .bootstrapAlreadyExists(path: repositoryURL.path)
                )
            ),
            AnyView(
                InstallGateStageView(
                    formState: formState,
                    previewPlan: BootstrapPreviewPlan(request: try formState.makeRequest()),
                    isInitializing: false,
                    bootstrapError: .permissionDenied(path: repositoryURL.path)
                )
            ),
        ]

        for view in views {
            let pngData = try snapshotData(
                of: view,
                size: CGSize(width: 980, height: 760),
                scheme: .light
            )
            XCTAssertFalse(pngData.isEmpty)
        }
    }

    private func populatedFormState(repositoryURL: URL) -> OnboardingFormState {
        var formState = OnboardingFormState()
        formState.projectName = "AgentAppFlow Demo"
        formState.projectDescription = "Mac-first repo memory orchestration."
        formState.projectPath = repositoryURL.path
        formState.projectType = .macOSApp
        formState.selectedPlatforms = [.macos]
        formState.selectedAgentTools = [.codex, .claudeCode]
        formState.approvalMode = .observe
        formState.improvementMode = .propose
        return formState
    }

    private func sampleProject(path: String) -> RegisteredProject {
        RegisteredProject(
            id: "project-1",
            projectName: "AgentAppFlow Demo",
            projectDescription: "Mac-first repo memory orchestration.",
            projectPath: path,
            projectType: .macOSApp,
            platforms: [.macos],
            agentTools: [.codex, .claudeCode],
            approvalMode: .observe,
            improvementMode: .propose,
            createdItems: sampleBootstrapResult.created,
            skippedItems: sampleBootstrapResult.skipped,
            registeredAt: Date(timeIntervalSince1970: 1_743_466_800),
            updatedAt: Date(timeIntervalSince1970: 1_743_466_800),
            lastBootstrappedAt: Date(timeIntervalSince1970: 1_743_466_800),
            latestSessionStartedAt: Date(timeIntervalSince1970: 1_743_466_800),
            sessionCount: 1
        )
    }

    private func makeGitRepository(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory.deletingLastPathComponent())
        return directory
    }
}

private let sampleBootstrapResult = BootstrapCommandResult(
    ok: true,
    message: "ok",
    created: [
        ".agentappflow/project.yaml",
        ".agentappflow/context/project-brief.md",
        ".agentappflow/sessions/.gitkeep",
        "AGENTS.md",
        "CLAUDE.md",
    ],
    skipped: []
)

private struct DesignSystemGallery: View {
    @State private var repoPath = "/Users/example/AgentAppFlow"
    @State private var description = "Mac-first local AI orchestration with guarded repo writes."
    @State private var appearanceMode: AppearanceMode = .system

    var body: some View {
        ZStack {
            AppBackground()

            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                AppCard {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("AgentAppFlow Design System")
                            .font(AppTheme.Typography.display(34))
                        Text("Foundation snapshot for buttons, badges, text inputs, and surfaces.")
                            .font(AppTheme.Typography.body(15, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ThemeModePicker(selection: $appearanceMode)
                    }
                }

                HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
                    AppCard {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                            Text("Buttons")
                                .font(AppTheme.Typography.mono(12, weight: .black))
                                .textCase(.uppercase)
                            HStack(spacing: AppTheme.Spacing.sm) {
                                AppButton("Primary", variant: .primary, action: {})
                                AppButton("Secondary", variant: .secondary, action: {})
                                AppButton("Ghost", variant: .ghost, action: {})
                                AppButton("Delete", variant: .destructive, action: {})
                            }
                            AppButton("Loading", variant: .primary, isLoading: true, action: {})
                        }
                    }

                    AppCard {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                            Text("Status")
                                .font(AppTheme.Typography.mono(12, weight: .black))
                                .textCase(.uppercase)
                            HStack(spacing: AppTheme.Spacing.sm) {
                                AppBadge(status: .healthy)
                                AppBadge(status: .warning)
                                AppBadge(status: .error)
                                AppBadge(status: .idle)
                            }
                            AppDivider()
                            HStack(spacing: AppTheme.Spacing.sm) {
                                AppIcon(systemName: "sparkles", size: 18)
                                AppSpacer(AppTheme.Spacing.sm, axis: .horizontal)
                                Text("Icons share a single wrapper.")
                                    .font(AppTheme.Typography.body(14, weight: .semibold))
                            }
                        }
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("Inputs")
                            .font(AppTheme.Typography.mono(12, weight: .black))
                            .textCase(.uppercase)
                        AppTextField(
                            title: "Repository",
                            prompt: "Repository path",
                            text: $repoPath,
                            state: .valid("Path detected"),
                            usesMonospaceFont: true
                        )
                        AppTextArea(
                            title: "Project Brief",
                            prompt: "Describe the project context",
                            text: $description,
                            state: .warning("Keep the summary concise and repo-specific"),
                            minHeight: 120,
                            maxHeight: 140
                        )
                    }
                }
            }
            .padding(AppTheme.Spacing.xxxl)
        }
        .frame(width: 960, height: 760)
    }
}

private struct ThemeModePickerHarness: View {
    @State private var selection: AppearanceMode = .system

    var body: some View {
        ThemeModePicker(selection: $selection)
    }
}

private extension PythonRuntimeInspection {
    static let readyPreview = PythonRuntimeInspection(
        status: .found,
        source: .embedded,
        interpreterPath: "/Applications/AgentAppFlow.app/Contents/Frameworks/Python3.framework",
        version: "Python 3.12.3"
    )

    static let missingPreview = PythonRuntimeInspection(
        status: .missing,
        source: .unavailable,
        interpreterPath: nil,
        version: nil
    )
}

private func fittingSize<V: View>(of view: V) -> CGSize {
    let hostingView = NSHostingView(rootView: view)
    hostingView.layoutSubtreeIfNeeded()
    return hostingView.fittingSize
}

private func snapshotData<V: View>(
    of view: V,
    size: CGSize,
    scheme: ColorScheme
) throws -> Data {
    let hostingView = NSHostingView(
        rootView: view
            .environment(\.colorScheme, scheme)
            .frame(width: size.width, height: size.height)
    )
    hostingView.frame = CGRect(origin: .zero, size: size)
    hostingView.layoutSubtreeIfNeeded()

    guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
        XCTFail("Failed to create bitmap for snapshot rendering.")
        return Data()
    }

    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        XCTFail("Failed to encode snapshot as PNG.")
        return Data()
    }

    return pngData
}
