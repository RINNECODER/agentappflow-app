import AppKit
import SwiftUI

enum SetupStage: Int, CaseIterable, Identifiable {
    case intro
    case repository
    case projectName
    case projectType
    case platforms
    case agentTool
    case approval
    case improvement
    case launch

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .intro:
            "First Launch"
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
        case .launch:
            "Initialize"
        }
    }

    var prompt: String {
        switch self {
        case .intro:
            "Local memory, project guardrails, no backend."
        case .repository:
            "Point AgentAppFlow at the repository you want to wire first."
        case .projectName:
            "Name the workspace and describe what the AI should understand on first contact."
        case .projectType:
            "Pick the base shape for the framework contract."
        case .platforms:
            "Choose the platforms this repo actively targets."
        case .agentTool:
            "Select the agent runtime you want the adapters to prepare."
        case .approval:
            "Define how aggressively the framework can act."
        case .improvement:
            "Set how the framework evolves after each task."
        case .launch:
            "Review the contract and write the first files."
        }
    }

    var interactiveAccessibilityLabels: [String] {
        switch self {
        case .intro:
            ["Next"]
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
        case .launch:
            ["Back", "Initialize"]
        }
    }
}

enum SetupAccessibilityLabel {
    static let repositoryPath = "Repository path"
    static let projectName = "Project name"
    static let projectBrief = "Project brief"
}

struct FirstRunSetupView: View {
    let runtimeService: AgentRuntimeServing
    let completeInitialSetup: (String) -> Void

    @State private var currentStage: SetupStage = .intro
    @State private var formState = OnboardingFormState()
    @State private var commandResult: BootstrapCommandResult?
    @State private var registeredProject: RegisteredProject?
    @State private var errorMessage: String?
    @State private var isInitializing = false

    init(
        runtimeService: AgentRuntimeServing,
        initialStage: SetupStage = .intro,
        completeInitialSetup: @escaping (String) -> Void
    ) {
        self.runtimeService = runtimeService
        self.completeInitialSetup = completeInitialSetup
        _currentStage = State(initialValue: initialStage)
    }

    private var stepNumber: Int {
        currentStage.rawValue + 1
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
                    didSucceed: registeredProject != nil,
                    goBack: goBack,
                    goForward: goForward,
                    initializeProject: initializeProject,
                    openWorkspace: openWorkspace
                )
            }
            .padding(.horizontal, AppTheme.Spacing.xxl)
            .padding(.top, AppTheme.Spacing.xxxl + AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.section)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(
            minWidth: AppTheme.Layout.setupMinSize.width,
            minHeight: AppTheme.Layout.setupMinSize.height
        )
    }

    @ViewBuilder
    private func stageContent(availableHeight: CGFloat) -> some View {
        switch currentStage {
        case .intro:
            IntroStageView()
        case .repository:
            RepositoryStageView(
                projectPath: $formState.projectPath,
                chooseRepositoryPath: chooseProjectPath
            )
        case .projectName:
            ProjectNameStageView(
                availableHeight: availableHeight,
                projectName: $formState.projectName,
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
        case .launch:
            LaunchStageView(
                formState: formState,
                isInitializing: isInitializing,
                commandResult: commandResult,
                errorMessage: errorMessage
            )
        }
    }

    private var canContinue: Bool {
        switch currentStage {
        case .intro:
            true
        case .repository:
            !formState.projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .projectName:
            !formState.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        case .launch:
            registeredProject != nil
        }
    }

    private func goBack() {
        guard let previous = SetupStage(rawValue: currentStage.rawValue - 1) else { return }
        currentStage = previous
    }

    private func goForward() {
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
    private func initializeProject() async {
        errorMessage = nil
        commandResult = nil
        registeredProject = nil
        isInitializing = true

        defer {
            isInitializing = false
        }

        do {
            let request = try formState.makeRequest()
            let result = try await runtimeService.bootstrap(request: request, force: false)
            let project = try await runtimeService.registerProject(
                request: request,
                bootstrapResult: result
            )
            commandResult = result
            registeredProject = project
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openWorkspace() {
        guard let registeredProject else { return }
        completeInitialSetup(registeredProject.id)
    }
}

private struct SetupStepHeader: View {
    let stepNumber: Int
    let totalSteps: Int
    let title: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text("Step \(stepNumber) / \(totalSteps)")
                .font(Font.brutalMeta())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(title)
                .font(Font.brutalHero(30))

            Text(prompt)
                .font(Font.brutalBody(15))
                .foregroundStyle(.secondary)

            SetupStepMeter(stepNumber: stepNumber, totalSteps: totalSteps)
        }
    }
}

private struct SetupStepMeter: View {
    let stepNumber: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index < stepNumber ? Color.primary : Color.primary.opacity(0.14))
                    .frame(height: AppTheme.Spacing.xxs + 1)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct IntroStageView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            Text("Wire one repo.\nGive it memory.\nKeep it local.")
                .font(Font.brutalHero(42))
                .lineSpacing(-2)

            Text("AgentAppFlow sets the first contract, adapters, and working memory layer before any coding agent touches the repo.")
                .font(Font.brutalBody(16, weight: .semibold))
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
                    copy: "Write `.agentappflow`, `AGENTS.md`, and `CLAUDE.md` in one launch."
                )
            }

            VStack(spacing: AppTheme.Spacing.sm) {
                SetupFactRow(label: "NOW", value: "Create the first local contract for the repo you are about to steer.")
                SetupFactRow(label: "LATER", value: "Rust stays reserved for guarded execution once the framework is live.")
            }
        }
    }
}

private struct SetupSpotlightCard: View {
    let eyebrow: String
    let title: String
    let copy: String

    var bodyView: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text(eyebrow)
                .font(Font.brutalMeta())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(title)
                .font(Font.brutalTitle(20, weight: .black))

            Text(copy)
                .font(Font.brutalBody(14, weight: .semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.lg)
        .background(BrutalInset(selected: true))
    }

    var body: some View { bodyView }
}

private struct SetupFactRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            Text(label)
                .font(Font.brutalMeta())
                .frame(width: 74, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(value)
                .font(Font.brutalBody(15, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppTheme.Spacing.regular)
        .background(BrutalInset())
    }
}

private struct RepositoryStageView: View {
    @Binding var projectPath: String
    let chooseRepositoryPath: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("Select a git repository folder.")
                .font(Font.brutalTitle(21, weight: .black))

            SetupRepoTargetCard(projectPath: projectPath)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                AppTextField(
                    title: nil,
                    prompt: "Repository path",
                    text: $projectPath,
                    usesMonospaceFont: true,
                    accessibilityLabel: SetupAccessibilityLabel.repositoryPath
                )

                AppButton("Browse", variant: .primary, action: chooseRepositoryPath)
            }
        }
    }
}

private struct SetupRepoTargetCard: View {
    let projectPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("Target Repo")
                .font(Font.brutalMeta())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(displayPath)
                .font(Font.brutalTitle(24, weight: .black))
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text(description)
                .font(Font.brutalBody(14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(AppTheme.Spacing.relaxed)
        .background(BrutalInset(selected: !projectPath.isEmpty))
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

private struct ProjectNameStageView: View {
    let availableHeight: CGFloat
    @Binding var projectName: String
    @Binding var projectDescription: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("How should the workspace be named?")
                .font(Font.brutalTitle(21, weight: .black))

            AppTextField(
                title: nil,
                prompt: "LegalPocketAI",
                text: $projectName,
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

private struct SetupIdentityCard: View {
    let availableHeight: CGFloat
    let projectName: String
    @Binding var projectDescription: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.relaxed) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs * 2) {
                Text("AI Context")
                    .font(Font.brutalMeta())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(displayName)
                    .font(Font.brutalHero(32))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                Text("Give the framework a compact brief so the generated repo memory starts with real project context.")
                    .font(Font.brutalBody(14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Prompt (optional)")
                    .font(Font.brutalMeta())
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
        .padding(AppTheme.Spacing.xl)
        .background(BrutalInset(selected: !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
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

private struct SetupInlineGuidanceCard: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            Text(label)
                .font(Font.brutalMeta())
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)

            Text(value)
                .font(Font.brutalBody(15, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, AppTheme.Spacing.regular)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private struct ProjectTypeStageView: View {
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

private struct PlatformStageView: View {
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

private struct AgentStageView: View {
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

private struct ApprovalStageView: View {
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

private struct ImprovementStageView: View {
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

private struct LaunchStageView: View {
    let formState: OnboardingFormState
    let isInitializing: Bool
    let commandResult: BootstrapCommandResult?
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            SetupLaunchHero(formState: formState)

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

            if let commandResult {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                    Text("Created")
                        .font(Font.brutalMeta(12, weight: .black))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    ForEach(commandResult.created, id: \.self) { item in
                        Text(item)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    }

                if !commandResult.skipped.isEmpty {
                        AppDivider()
                        Text("Skipped")
                            .font(Font.brutalMeta(12, weight: .black))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)

                        ForEach(commandResult.skipped, id: \.self) { item in
                            Text(item)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(AppTheme.Spacing.regular)
                .background(BrutalInset())
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Font.brutalBody(14, weight: .semibold))
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct SetupLaunchHero: View {
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
                    .font(Font.brutalMeta())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(formState.projectName)
                    .font(Font.brutalHero(34))
                Text("The first launch writes the repo contract, adapter files, and starter memory structure in one pass.")
                    .font(Font.brutalBody(14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppTheme.Spacing.relaxed)
        .background(BrutalInset(selected: true))
    }
}

private struct SetupFooter: View {
    let currentStage: SetupStage
    let canContinue: Bool
    let isInitializing: Bool
    let didSucceed: Bool
    let goBack: () -> Void
    let goForward: () -> Void
    let initializeProject: @MainActor () async -> Void
    let openWorkspace: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if currentStage != .intro {
                AppButton("Back", variant: .secondary, action: goBack)
            }

            Spacer()

            switch currentStage {
            case .launch:
                if didSucceed {
                    AppButton("Open Control Center", variant: .primary, action: openWorkspace)
                } else {
                    AppButton(
                        "Initialize",
                        variant: .primary,
                        isLoading: isInitializing,
                        isDisabled: isInitializing,
                        action: {
                            Task { await initializeProject() }
                        }
                    )
                }
            default:
                AppButton(
                    "Next",
                    variant: .primary,
                    isDisabled: !canContinue,
                    action: goForward
                )
            }
        }
    }
}

private struct SetupChoiceGrid<Content: View>: View {
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

private enum SetupChoiceStyle {
    case single
    case multiple
}

private struct SetupChoiceCard: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let isSelected: Bool
    var selectionStyle: SetupChoiceStyle = .single
    let action: () -> Void

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
                        .font(Font.brutalTitle(18, weight: .black))
                    Text(subtitle)
                        .font(Font.brutalBody(13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
            .padding(AppTheme.Spacing.lg)
            .background(BrutalInset(selected: isSelected))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(subtitle)
    }
}

private struct SetupSelectionIndicator: View {
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
