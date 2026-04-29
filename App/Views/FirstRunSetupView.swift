import AppKit
import SwiftUI

enum SetupStage: Int, CaseIterable, Identifiable {
    case intro
    case runtimeCheck
    case repository
    case projectName
    case projectType
    case platforms
    case agentTool
    case approval
    case improvement
    case installGate
    case complete

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .intro:
            "First Launch"
        case .runtimeCheck:
            "Python Runtime"
        case .repository:
            "Repository"
        case .projectName:
            "Project Name"
        case .projectType:
            "Project Type"
        case .platforms:
            "Platforms"
        case .agentTool:
            "Agent Tool"
        case .approval:
            "Approval"
        case .improvement:
            "Improvement"
        case .installGate:
            "Install Gate"
        case .complete:
            "Complete"
        }
    }

    var prompt: String {
        switch self {
        case .intro:
            "Local memory, repo-owned rules, no backend required."
        case .runtimeCheck:
            "Verify the local Python runtime before the framework writes anything."
        case .repository:
            "Point AgentAppFlow at the git repository you want to wire first."
        case .projectName:
            "Name the workspace and give the AI a compact project brief."
        case .projectType:
            "Pick the base shape for the framework contract."
        case .platforms:
            "Choose the platforms this repo actively targets."
        case .agentTool:
            "Select the agent runtime adapters this repo needs."
        case .approval:
            "Decide how framework-owned files can change."
        case .improvement:
            "Set how the framework evolves after each task."
        case .installGate:
            "Review the exact files the bootstrap will stage."
        case .complete:
            "Your first workspace is ready to open."
        }
    }

    var interactiveAccessibilityLabels: [String] {
        switch self {
        case .intro:
            ["Next"]
        case .runtimeCheck:
            ["Back", "Next"]
        case .repository:
            [SetupAccessibilityLabel.repositoryPath, "Browse", "Back", "Next"]
        case .projectName:
            [SetupAccessibilityLabel.projectName, SetupAccessibilityLabel.projectBrief, "Back", "Next"]
        case .projectType:
            ProjectType.allCases.map(\.displayName) + ["Back", "Next"]
        case .platforms:
            PlatformChoice.allCases.map(\.displayName) + ["Back", "Next"]
        case .agentTool:
            AgentToolChoice.allCases.map(\.displayName) + ["Back", "Next"]
        case .approval:
            ApprovalMode.allCases.map(\.displayName) + ["Back", "Next"]
        case .improvement:
            ImprovementMode.allCases.map(\.displayName) + ["Back", "Next"]
        case .installGate:
            ["Back", "Initialize", "Open Existing", "Re-bootstrap"]
        case .complete:
            ["Open Control Center"]
        }
    }
}

enum SetupAccessibilityLabel {
    static let repositoryPath = "Repository path"
    static let projectName = "Project name"
    static let projectBrief = "Project brief"
}

enum SetupBootstrapError: Equatable, Identifiable {
    case bootstrapAlreadyExists(path: String)
    case permissionDenied(path: String)
    case generic(message: String)

    var id: String {
        switch self {
        case .bootstrapAlreadyExists(let path):
            "bootstrap-\(path)"
        case .permissionDenied(let path):
            "permission-\(path)"
        case .generic(let message):
            "generic-\(message)"
        }
    }

    var title: String {
        switch self {
        case .bootstrapAlreadyExists:
            "Bootstrap already exists"
        case .permissionDenied:
            "Permission denied"
        case .generic:
            "Bootstrap blocked"
        }
    }

    var detail: String {
        switch self {
        case .bootstrapAlreadyExists(let path):
            "A previous AgentAppFlow contract already exists at \(path). Re-bootstrap the repo or open the existing workspace."
        case .permissionDenied(let path):
            "AgentAppFlow cannot write inside \(path). Choose a writable repository or adjust permissions."
        case .generic(let message):
            message
        }
    }
}

struct FirstRunSetupView: View {
    let runtimeService: AgentRuntimeServing
    let defaultApprovalMode: ApprovalMode
    let pythonFrameworkOverride: String?
    let completeInitialSetup: (String) -> Void

    @State private var currentStage: SetupStage
    @State private var formState: OnboardingFormState
    @State private var commandResult: BootstrapCommandResult?
    @State private var registeredProject: RegisteredProject?
    @State private var bootstrapError: SetupBootstrapError?
    @State private var isInitializing = false
    @State private var pythonInspection: PythonRuntimeInspection

    init(
        runtimeService: AgentRuntimeServing,
        defaultApprovalMode: ApprovalMode = .propose,
        pythonFrameworkOverride: String? = nil,
        initialStage: SetupStage = .intro,
        initialFormState: OnboardingFormState? = nil,
        initialCommandResult: BootstrapCommandResult? = nil,
        initialRegisteredProject: RegisteredProject? = nil,
        initialBootstrapError: SetupBootstrapError? = nil,
        initialPythonInspection: PythonRuntimeInspection = .checking,
        completeInitialSetup: @escaping (String) -> Void
    ) {
        self.runtimeService = runtimeService
        self.defaultApprovalMode = defaultApprovalMode
        self.pythonFrameworkOverride = pythonFrameworkOverride
        self.completeInitialSetup = completeInitialSetup
        _currentStage = State(initialValue: initialStage)
        _formState = State(initialValue: initialFormState ?? OnboardingFormState(approvalMode: defaultApprovalMode))
        _commandResult = State(initialValue: initialCommandResult)
        _registeredProject = State(initialValue: initialRegisteredProject)
        _bootstrapError = State(initialValue: initialBootstrapError)
        _pythonInspection = State(initialValue: initialPythonInspection)
    }

    private var stepNumber: Int {
        currentStage.rawValue + 1
    }

    private var validationSnapshot: OnboardingValidationSnapshot {
        formState.validationSnapshot()
    }

    private var installPreviewPlan: BootstrapPreviewPlan? {
        guard let request = try? formState.makeRequest() else {
            return nil
        }
        return BootstrapPreviewPlan(request: request)
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                SetupStepHeader(
                    stepNumber: stepNumber,
                    totalSteps: SetupStage.allCases.count,
                    title: currentStage.title,
                    prompt: currentStage.prompt
                )

                GeometryReader { geometry in
                    stageContent(availableHeight: geometry.size.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                SetupFooter(
                    currentStage: currentStage,
                    canContinue: canContinue,
                    isInitializing: isInitializing,
                    bootstrapError: bootstrapError,
                    goBack: goBack,
                    goForward: goForward,
                    initializeProject: initializeProject,
                    openExistingWorkspace: openExistingWorkspace,
                    rebootstrapProject: rebootstrapProject,
                    openWorkspace: openWorkspace
                )
            }
            .padding(.horizontal, AppTheme.Spacing.xxl)
            .padding(.top, AppTheme.Spacing.xxxl + AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.section)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.shell, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.shell, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.horizontal, AppTheme.Spacing.xl)
                    .padding(.vertical, AppTheme.Spacing.lg)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(
            minWidth: AppTheme.Layout.setupMinSize.width,
            minHeight: AppTheme.Layout.setupMinSize.height
        )
        .onChange(of: formState) { _, _ in
            if currentStage != .complete {
                commandResult = nil
                registeredProject = nil
            }
            bootstrapError = nil
        }
        .task {
            guard pythonInspection.status == .checking else { return }
            let inspection = await Task.detached(priority: .userInitiated) {
                PythonRuntimeLocator.inspect(runtimeOverridePath: pythonFrameworkOverride)
            }.value
            pythonInspection = inspection
        }
    }

    @ViewBuilder
    private func stageContent(availableHeight: CGFloat) -> some View {
        switch currentStage {
        case .intro:
            IntroStageView()
        case .runtimeCheck:
            PythonRuntimeStageView(inspection: pythonInspection)
        case .repository:
            RepositoryStageView(
                projectPath: $formState.projectPath,
                projectPathState: validationSnapshot.projectPathState,
                chooseRepositoryPath: chooseProjectPath
            )
        case .projectName:
            ProjectNameStageView(
                availableHeight: availableHeight,
                projectName: $formState.projectName,
                projectNameState: validationSnapshot.projectNameState,
                projectDescription: $formState.projectDescription
            )
        case .projectType:
            ProjectTypeStageView(selection: $formState.projectType)
        case .platforms:
            PlatformStageView(selection: $formState.selectedPlatforms)
        case .agentTool:
            AgentStageView(selection: $formState.selectedAgentTools)
        case .approval:
            ApprovalStageView(selection: $formState.approvalMode)
        case .improvement:
            ImprovementStageView(selection: $formState.improvementMode)
        case .installGate:
            InstallGateStageView(
                formState: formState,
                previewPlan: installPreviewPlan,
                isInitializing: isInitializing,
                bootstrapError: bootstrapError
            )
        case .complete:
            CompletionStageView(
                project: registeredProject,
                commandResult: commandResult
            )
        }
    }

    private var canContinue: Bool {
        switch currentStage {
        case .intro:
            true
        case .runtimeCheck:
            pythonInspection.canProceed
        case .repository:
            formState.projectPathError() == nil
        case .projectName:
            formState.projectNameError() == nil
        case .projectType:
            true
        case .platforms:
            !formState.selectedPlatforms.isEmpty
        case .agentTool:
            !formState.selectedAgentTools.isEmpty
        case .approval:
            true
        case .improvement:
            true
        case .installGate:
            installPreviewPlan != nil && !isInitializing
        case .complete:
            registeredProject != nil
        }
    }

    private func goBack() {
        guard let previous = SetupStage(rawValue: currentStage.rawValue - 1) else { return }
        currentStage = previous
    }

    private func goForward() {
        if currentStage == .repository {
            formState.populateProjectNameIfNeeded()
        }
        guard let next = SetupStage(rawValue: currentStage.rawValue + 1) else { return }
        currentStage = next
    }

    private func chooseProjectPath() {
        let panel = NSOpenPanel()
        panel.prompt = "Choose Repository"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            formState.projectPath = url.path
            formState.populateProjectNameIfNeeded()
        }
    }

    @MainActor
    private func initializeProject(force: Bool = false) async {
        commandResult = nil
        registeredProject = nil
        bootstrapError = nil

        guard pythonInspection.canProceed else {
            currentStage = .runtimeCheck
            return
        }

        isInitializing = true
        defer { isInitializing = false }

        do {
            let request = try formState.makeRequest()
            let result = try await runtimeService.bootstrap(request: request, force: force)
            let project = try await runtimeService.registerProject(
                request: request,
                bootstrapResult: result
            )
            commandResult = result
            registeredProject = project
            currentStage = .complete
        } catch let error as StubRuntimeServiceError {
            bootstrapError = mapBootstrapError(error)
        } catch {
            bootstrapError = .generic(message: error.localizedDescription)
        }
    }

    @MainActor
    private func rebootstrapProject() async {
        await initializeProject(force: true)
    }

    @MainActor
    private func openExistingWorkspace() async {
        do {
            let projects = try await runtimeService.listProjects()
            guard let project = projects.first(where: { $0.projectPath == formState.trimmedProjectPath }) else {
                bootstrapError = .generic(message: "No registered workspace matches this repository yet.")
                return
            }
            registeredProject = project
            currentStage = .complete
        } catch {
            bootstrapError = .generic(message: error.localizedDescription)
        }
    }

    private func openWorkspace() {
        guard let registeredProject else { return }
        completeInitialSetup(registeredProject.id)
    }

    private func mapBootstrapError(_ error: StubRuntimeServiceError) -> SetupBootstrapError {
        switch error {
        case .bootstrapAlreadyExists(let path):
            return .bootstrapAlreadyExists(path: path)
        case .permissionDenied(let path):
            return .permissionDenied(path: path)
        case .projectNotFound:
            return .generic(message: error.localizedDescription)
        }
    }
}

struct SetupStepHeader: View {
    let stepNumber: Int
    let totalSteps: Int
    let title: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack(spacing: AppTheme.Spacing.sm) {
                AppBadge(status: .idle)
                Text("Step \(stepNumber) / \(totalSteps)")
                    .font(AppTheme.Typography.mono(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            Text(title)
                .font(AppTheme.Typography.display(30))

            Text(prompt)
                .font(AppTheme.Typography.body(14, weight: .semibold))
                .foregroundStyle(.secondary)

            SetupStepMeter(stepNumber: stepNumber, totalSteps: totalSteps)
        }
    }
}

struct SetupStepMeter: View {
    let stepNumber: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index < stepNumber ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.primary.opacity(0.12)))
                    .overlay(
                        Capsule()
                            .fill(index + 1 == stepNumber ? AnyShapeStyle(AppTheme.Colors.chromeHighlight(for: .dark)) : AnyShapeStyle(Color.clear))
                    )
                    .frame(height: AppTheme.Spacing.xxs + 2)
            }
        }
        .accessibilityHidden(true)
    }
}

struct IntroStageView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            Text("Wire one repo.\nGive it memory.\nKeep it local.")
                .font(AppTheme.Typography.display(38))
                .lineSpacing(-2)

            Text("AgentAppFlow sets the first contract, adapters, and working memory layer before any coding agent touches the repo.")
                .font(AppTheme.Typography.body(14, weight: .semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AppTheme.Spacing.compact) {
                SetupSpotlightCard(
                    eyebrow: "LOCAL",
                    title: "Repo-owned memory",
                    copy: "Sessions, rules, and retros stay inside the project."
                )
                SetupSpotlightCard(
                    eyebrow: "FIRST PASS",
                    title: "One controlled bootstrap",
                    copy: "Stage `.agentappflow`, `AGENTS.md`, and adapter notes in one pass."
                )
            }

            VStack(spacing: AppTheme.Spacing.sm) {
                SetupFactRow(label: "NOW", value: "Register the first local workspace and verify the runtime before any files are touched.")
                SetupFactRow(label: "LATER", value: "Swap the stub runtime for the daemon once the frontend contract is locked.")
            }
        }
    }
}

struct PythonRuntimeStageView: View {
    let inspection: PythonRuntimeInspection

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            SetupRuntimeHero(inspection: inspection)

            if inspection.status == .checking {
                ProgressView("Inspecting Python runtime...")
                    .controlSize(.large)
            } else if inspection.canProceed {
                SetupInlineGuidanceCard(
                    label: "READY",
                    value: "The runtime check passed. Continue into repository registration."
                )
            } else {
                SetupBootstrapErrorCard(
                    title: inspection.title,
                    detail: inspection.detail
                )
            }
        }
    }
}

struct SetupRuntimeHero: View {
    let inspection: PythonRuntimeInspection

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.relaxed) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        AppIcon(
                            systemName: iconName,
                            size: 28,
                            color: iconColor
                        )
                    )
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text(inspection.title)
                        .font(AppTheme.Typography.display(30))
                    Text(inspection.detail)
                        .font(AppTheme.Typography.body(14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                SetupFactRow(label: "STATE", value: inspection.statusCopy)
                SetupFactRow(label: "PATH", value: inspection.interpreterPath ?? "Unavailable")
            }

            if let overridePath = inspection.overridePath {
                SetupFactRow(label: "OVERRIDE", value: overridePath)
            }
        }
        .padding(AppTheme.Spacing.relaxed)
        .background(AppInsetSurface(emphasized: inspection.canProceed, cornerRadius: AppTheme.Radius.xl))
    }

    private var iconName: String {
        switch inspection.status {
        case .checking:
            "hourglass"
        case .found:
            "checkmark.circle.fill"
        case .missing:
            "exclamationmark.triangle.fill"
        case .unsupportedVersion:
            "xmark.octagon.fill"
        }
    }

    private var iconColor: Color {
        switch inspection.status {
        case .checking:
            AppTheme.Colors.idle
        case .found:
            AppTheme.Colors.healthy
        case .missing:
            AppTheme.Colors.warning
        case .unsupportedVersion:
            AppTheme.Colors.destructive
        }
    }
}

struct SetupSpotlightCard: View {
    let eyebrow: String
    let title: String
    let copy: String

    var bodyView: some View {
        AppCard(padding: AppTheme.Spacing.lg, cornerRadius: AppTheme.Radius.lg, interactive: true) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                Text(eyebrow)
                    .font(AppTheme.Typography.mono(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(title)
                    .font(AppTheme.Typography.headline(18, weight: .semibold))

                Text(copy)
                    .font(AppTheme.Typography.body(13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View { bodyView }
}

struct SetupFactRow: View {
    let label: String
    let value: String

    var body: some View {
        AppCard(padding: AppTheme.Spacing.regular, cornerRadius: AppTheme.Radius.md) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                Text(label)
                    .font(AppTheme.Typography.mono(10, weight: .semibold))
                    .frame(width: 74, alignment: .leading)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(AppTheme.Typography.body(14, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct RepositoryStageView: View {
    @Binding var projectPath: String
    let projectPathState: AppFieldState
    let chooseRepositoryPath: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("Select a git repository folder.")
                .font(AppTheme.Typography.headline(21, weight: .bold))

            SetupRepoTargetCard(projectPath: projectPath)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                AppTextField(
                    title: nil,
                    prompt: "Repository path",
                    text: $projectPath,
                    state: projectPathState,
                    usesMonospaceFont: true,
                    accessibilityLabel: SetupAccessibilityLabel.repositoryPath
                )

                AppButton("Browse", variant: .primary, action: chooseRepositoryPath)
            }
        }
    }
}

struct SetupRepoTargetCard: View {
    let projectPath: String

    var body: some View {
        AppCard(padding: AppTheme.Spacing.relaxed, cornerRadius: AppTheme.Radius.xl, interactive: !projectPath.isEmpty) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Target Repo")
                    .font(AppTheme.Typography.mono(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(displayPath)
                    .font(AppTheme.Typography.headline(24, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text(description)
                    .font(AppTheme.Typography.body(14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var displayPath: String {
        projectPath.isEmpty ? "No repository selected yet." : projectPath
    }

    private var description: String {
        projectPath.isEmpty
            ? "Choose the repo where AgentAppFlow will write the first framework contract."
            : "This folder becomes the first workspace AgentAppFlow tracks and bootstraps."
    }
}

struct ProjectNameStageView: View {
    let availableHeight: CGFloat
    @Binding var projectName: String
    let projectNameState: AppFieldState
    @Binding var projectDescription: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("How should the workspace be named?")
                .font(AppTheme.Typography.headline(21, weight: .bold))

            AppTextField(
                title: nil,
                prompt: "LegalPocketAI",
                text: $projectName,
                state: projectNameState,
                accessibilityLabel: SetupAccessibilityLabel.projectName
            )

            SetupIdentityCard(
                availableHeight: availableHeight,
                projectName: projectName,
                projectDescription: $projectDescription
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct SetupIdentityCard: View {
    let availableHeight: CGFloat
    let projectName: String
    @Binding var projectDescription: String

    var body: some View {
        AppCard(padding: AppTheme.Spacing.xl, cornerRadius: AppTheme.Radius.xl, interactive: !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.relaxed) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs * 2) {
                    Text("AI Context")
                        .font(AppTheme.Typography.mono(10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text(displayName)
                        .font(AppTheme.Typography.display(30))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    Text("Give the framework a compact brief so the generated repo memory starts with real project context.")
                        .font(AppTheme.Typography.body(13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("Prompt (optional)")
                        .font(AppTheme.Typography.mono(10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    AppTextArea(
                        title: nil,
                        prompt: "Example: Building an iOS legal assistant that analyzes contracts locally, keeps project memory inside the repo, and optimizes codex and claude workflows around legal review.",
                        text: $projectDescription,
                        minHeight: 112,
                        maxHeight: editorHeight,
                        accessibilityLabel: SetupAccessibilityLabel.projectBrief
                    )
                }

                SetupInlineGuidanceCard(
                    label: "USE",
                    value: "Include the product goal, target user, repo focus, constraints, and what makes this project specific."
                )
            }
            .frame(maxWidth: .infinity, maxHeight: cardHeight, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var displayName: String {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Workspace" : trimmed
    }

    private var cardHeight: CGFloat {
        availableHeight
            .advanced(by: -(AppTheme.Spacing.xxxl + AppTheme.Spacing.xxl + AppTheme.Spacing.relaxed))
            .clamped(to: 300...410)
    }

    private var editorHeight: CGFloat {
        (cardHeight * 0.40).clamped(to: 112...168)
    }
}

struct SetupInlineGuidanceCard: View {
    let label: String
    let value: String

    var body: some View {
        AppCard(padding: AppTheme.Spacing.regular, cornerRadius: AppTheme.Radius.md) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                Text(label)
                    .font(AppTheme.Typography.mono(11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .leading)

                Text(value)
                    .font(AppTheme.Typography.body(15, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

struct ProjectTypeStageView: View {
    @Binding var selection: ProjectType

    var body: some View {
        SetupChoiceGrid {
            ForEach(ProjectType.allCases) { type in
                SetupChoiceCard(
                    title: type.displayName,
                    subtitle: type.subtitle,
                    symbolName: type.symbolName,
                    isSelected: selection == type
                ) {
                    selection = type
                }
            }
        }
    }
}

struct PlatformStageView: View {
    @Binding var selection: Set<PlatformChoice>

    var body: some View {
        SetupChoiceGrid {
            ForEach(PlatformChoice.allCases) { platform in
                SetupChoiceCard(
                    title: platform.displayName,
                    subtitle: platform.subtitle,
                    symbolName: platform.symbolName,
                    isSelected: selection.contains(platform),
                    selectionStyle: .multiple
                ) {
                    if selection.contains(platform) {
                        selection.remove(platform)
                    } else {
                        selection.insert(platform)
                    }
                }
            }
        }
    }
}

struct AgentStageView: View {
    @Binding var selection: Set<AgentToolChoice>

    var body: some View {
        SetupChoiceGrid {
            ForEach(AgentToolChoice.allCases) { tool in
                SetupChoiceCard(
                    title: tool.displayName,
                    subtitle: tool.subtitle,
                    symbolName: tool.symbolName,
                    isSelected: selection.contains(tool),
                    selectionStyle: .multiple
                ) {
                    if selection.contains(tool) {
                        selection.remove(tool)
                    } else {
                        selection.insert(tool)
                    }
                }
            }
        }
    }
}

struct ApprovalStageView: View {
    @Binding var selection: ApprovalMode

    var body: some View {
        SetupChoiceGrid {
            ForEach(ApprovalMode.allCases) { mode in
                SetupChoiceCard(
                    title: mode.displayName,
                    subtitle: mode.subtitle,
                    symbolName: "lock.shield",
                    isSelected: selection == mode
                ) {
                    selection = mode
                }
            }
        }
    }
}

struct ImprovementStageView: View {
    @Binding var selection: ImprovementMode

    var body: some View {
        SetupChoiceGrid {
            ForEach(ImprovementMode.allCases) { mode in
                SetupChoiceCard(
                    title: mode.displayName,
                    subtitle: mode.subtitle,
                    symbolName: "arrow.triangle.2.circlepath",
                    isSelected: selection == mode
                ) {
                    selection = mode
                }
            }
        }
    }
}

struct InstallGateStageView: View {
    let formState: OnboardingFormState
    let previewPlan: BootstrapPreviewPlan?
    let isInitializing: Bool
    let bootstrapError: SetupBootstrapError?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            SetupLaunchHero(formState: formState)

            if let previewPlan {
                SetupPreviewPanel(previewPlan: previewPlan)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                SetupFactRow(label: "PATH", value: formState.projectPath)
                SetupFactRow(label: "AGENT", value: formState.selectedAgentTools.map(\.displayName).sorted().joined(separator: " + "))
                SetupFactRow(label: "PLAT", value: formState.selectedPlatforms.map(\.displayName).sorted().joined(separator: " + "))
                SetupFactRow(label: "MODE", value: "\(formState.approvalMode.displayName) / \(formState.improvementMode.displayName)")
                if !formState.projectDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SetupFactRow(label: "BRIEF", value: formState.projectDescription)
                }
            }

            if isInitializing {
                ProgressView("Initializing framework...")
                    .controlSize(.large)
            }

            if let bootstrapError {
                SetupBootstrapErrorCard(
                    title: bootstrapError.title,
                    detail: bootstrapError.detail
                )
            }
        }
    }
}

struct SetupLaunchHero: View {
    let formState: OnboardingFormState

    var body: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 34, weight: .black))
                )
                .frame(width: 104, height: 104)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Ready to initialize")
                    .font(AppTheme.Typography.mono(10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(formState.projectName)
                    .font(AppTheme.Typography.display(30))
                Text("The stub bootstrap will register the repo, adapter files, and starter memory structure without calling the live daemon.")
                    .font(AppTheme.Typography.body(13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppTheme.Spacing.relaxed)
        .background(AppInsetSurface(emphasized: true, cornerRadius: AppTheme.Radius.xl))
    }
}

struct SetupPreviewPanel: View {
    let previewPlan: BootstrapPreviewPlan

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                Text("Planned Writes")
                    .font(AppTheme.Typography.mono(11, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                ForEach(previewPlan.treeItems, id: \.self) { item in
                    Text(item)
                        .font(AppTheme.Typography.mono(12, weight: .medium))
                }

                AppDivider()

                Text(previewPlan.approvalSummary)
                    .font(AppTheme.Typography.body(12, weight: .semibold))
                Text(previewPlan.improvementSummary)
                    .font(AppTheme.Typography.body(12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SetupBootstrapErrorCard: View {
    let title: String
    let detail: String

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text(title)
                    .font(AppTheme.Typography.headline(17, weight: .semibold))
                Text(detail)
                    .font(AppTheme.Typography.body(13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CompletionStageView: View {
    let project: RegisteredProject?
    let commandResult: BootstrapCommandResult?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            AppCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    AppBadge(status: .healthy)
                    Text("Workspace ready")
                        .font(AppTheme.Typography.display(30))
                    Text(project?.projectName ?? "Registered workspace")
                        .font(AppTheme.Typography.headline(20, weight: .semibold))
                    Text(project?.projectPath ?? "Unknown path")
                        .font(AppTheme.Typography.mono(12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if let commandResult {
                AppCard {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("Created")
                            .font(AppTheme.Typography.mono(11, weight: .semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)

                        ForEach(commandResult.created, id: \.self) { item in
                            Text(item)
                                .font(AppTheme.Typography.mono(12, weight: .medium))
                        }
                    }
                }
            }
        }
    }
}

struct SetupFooter: View {
    let currentStage: SetupStage
    let canContinue: Bool
    let isInitializing: Bool
    let bootstrapError: SetupBootstrapError?
    let goBack: () -> Void
    let goForward: () -> Void
    let initializeProject: @MainActor (Bool) async -> Void
    let openExistingWorkspace: @MainActor () async -> Void
    let rebootstrapProject: @MainActor () async -> Void
    let openWorkspace: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if currentStage != .intro && currentStage != .complete {
                AppButton("Back", variant: .secondary, action: goBack)
            }

            Spacer()

            switch currentStage {
            case .installGate:
                if case .bootstrapAlreadyExists = bootstrapError {
                    AppButton("Open Existing", variant: .secondary) {
                        Task { await openExistingWorkspace() }
                    }
                    AppButton(
                        "Re-bootstrap",
                        variant: .primary,
                        isLoading: isInitializing,
                        isDisabled: isInitializing
                    ) {
                        Task { await rebootstrapProject() }
                    }
                } else {
                    AppButton(
                        "Initialize",
                        variant: .primary,
                        isLoading: isInitializing,
                        isDisabled: !canContinue || isInitializing
                    ) {
                        Task { await initializeProject(false) }
                    }
                }
            case .complete:
                AppButton("Open Control Center", variant: .primary, action: openWorkspace)
            default:
                AppButton(
                    "Next",
                    variant: .primary,
                    isDisabled: !canContinue,
                    action: goForward
                )
            }
        }
        .padding(.top, AppTheme.Spacing.md)
    }
}

struct SetupChoiceGrid<Content: View>: View {
    @ViewBuilder let content: Content

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 360), spacing: AppTheme.Spacing.compact)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: AppTheme.Spacing.compact) {
            content
        }
    }
}

enum SetupChoiceStyle {
    case single
    case multiple
}

struct SetupChoiceCard: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let isSelected: Bool
    var selectionStyle: SetupChoiceStyle = .single
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                HStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .fill(.thinMaterial)
                        .overlay(
                            Image(systemName: symbolName)
                                .font(.system(size: 18, weight: .black))
                        )
                        .frame(width: AppTheme.Layout.minimumTapTarget, height: AppTheme.Layout.minimumTapTarget)
                        .accessibilityHidden(true)

                    Spacer()

                    SetupSelectionIndicator(
                        isSelected: isSelected,
                        style: selectionStyle
                    )
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(title)
                        .font(AppTheme.Typography.headline(18, weight: .bold))
                    Text(subtitle)
                        .font(AppTheme.Typography.body(13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
            .padding(AppTheme.Spacing.lg)
            .background(AppInsetSurface(emphasized: isSelected || isHovered, cornerRadius: AppTheme.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.primary.opacity(0.8) : (isHovered ? Color.primary.opacity(0.18) : Color.clear),
                        lineWidth: isSelected ? 1.4 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(AppTheme.Motion.emphasis, value: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(subtitle)
    }
}

struct SetupSelectionIndicator: View {
    let isSelected: Bool
    let style: SetupChoiceStyle

    var body: some View {
        Group {
            switch style {
            case .single:
                Circle()
                    .fill(isSelected ? Color.primary : Color.clear)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary, lineWidth: 1.5)
                    )
            case .multiple:
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.primary : Color.clear)
                    .frame(width: 18, height: 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary, lineWidth: 1.4)
                    )
            }
        }
        .accessibilityHidden(true)
    }
}
