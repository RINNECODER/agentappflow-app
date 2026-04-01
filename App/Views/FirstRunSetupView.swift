import AppKit
import SwiftUI

private enum SetupStage: Int, CaseIterable, Identifiable {
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
            "Name the project the way the control center should frame it."
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

    var symbolName: String {
        switch self {
        case .intro:
            "sparkles.rectangle.stack"
        case .repository:
            "folder.badge.plus"
        case .projectName:
            "textformat.alt"
        case .projectType:
            "square.stack.3d.up"
        case .platforms:
            "square.grid.3x3"
        case .agentTool:
            "bolt.horizontal.circle"
        case .approval:
            "lock.shield"
        case .improvement:
            "arrow.triangle.2.circlepath"
        case .launch:
            "play.circle"
        }
    }
}

struct FirstRunSetupView: View {
    let completeInitialSetup: (WorkspaceSnapshot) -> Void

    private let bootstrapService = BootstrapCLIService()

    @State private var currentStage: SetupStage = .intro
    @State private var formState = OnboardingFormState()
    @State private var commandResult: BootstrapCommandResult?
    @State private var initializedSnapshot: WorkspaceSnapshot?
    @State private var errorMessage: String?
    @State private var isInitializing = false

    private var stepNumber: Int {
        currentStage.rawValue + 1
    }

    var body: some View {
        ZStack {
            AgentAppFlowBackdrop()

            VStack(alignment: .leading, spacing: 28) {
                SetupStepHeader(
                    stepNumber: stepNumber,
                    totalSteps: SetupStage.allCases.count,
                    title: currentStage.title,
                    prompt: currentStage.prompt,
                    symbolName: currentStage.symbolName
                )

                stageContent

                Spacer(minLength: 0)

                SetupFooter(
                    currentStage: currentStage,
                    canContinue: canContinue,
                    isInitializing: isInitializing,
                    didSucceed: initializedSnapshot != nil,
                    goBack: goBack,
                    goForward: goForward,
                    initializeProject: initializeProject,
                    openWorkspace: openWorkspace
                )
            }
            .padding(.horizontal, 28)
            .padding(.top, 54)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    @ViewBuilder
    private var stageContent: some View {
        switch currentStage {
        case .intro:
            IntroStageView()
        case .repository:
            RepositoryStageView(
                projectPath: $formState.projectPath,
                chooseRepositoryPath: chooseProjectPath
            )
        case .projectName:
            ProjectNameStageView(projectName: $formState.projectName)
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
            initializedSnapshot != nil
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
        initializedSnapshot = nil
        isInitializing = true

        defer {
            isInitializing = false
        }

        do {
            let request = try formState.makeRequest()
            let result = try await bootstrapService.bootstrap(request: request)
            commandResult = result
            initializedSnapshot = WorkspaceSnapshot.from(request: request, result: result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openWorkspace() {
        guard let initializedSnapshot else { return }
        completeInitialSetup(initializedSnapshot)
    }
}

private struct SetupStepHeader: View {
    let stepNumber: Int
    let totalSteps: Int
    let title: String
    let prompt: String
    let symbolName: String

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
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

            Spacer(minLength: 0)

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .frame(width: 94, height: 94)

                Image(systemName: symbolName)
                    .font(.system(size: 28, weight: .black))
            }
        }
    }
}

private struct SetupStepMeter: View {
    let stepNumber: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index < stepNumber ? Color.primary : Color.primary.opacity(0.14))
                    .frame(height: 5)
            }
        }
    }
}

private struct IntroStageView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Wire one repo.\nGive it memory.\nKeep it local.")
                .font(Font.brutalHero(42))
                .lineSpacing(-2)

            Text("AgentAppFlow sets the first contract, adapters, and working memory layer before any coding agent touches the repo.")
                .font(Font.brutalBody(16, weight: .semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
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

            VStack(spacing: 10) {
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
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(18)
        .background(BrutalInset(selected: true))
    }

    var body: some View { bodyView }
}

private struct SetupFactRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label)
                .font(Font.brutalMeta())
                .frame(width: 74, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(value)
                .font(Font.brutalBody(15, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(BrutalInset())
    }
}

private struct RepositoryStageView: View {
    @Binding var projectPath: String
    let chooseRepositoryPath: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Select a git repository folder.")
                .font(Font.brutalTitle(21, weight: .black))

            SetupRepoTargetCard(projectPath: projectPath)

            VStack(alignment: .leading, spacing: 12) {
                TextField("Repository path", text: $projectPath)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .background(BrutalInset())

                Button("Browse", action: chooseRepositoryPath)
                    .buttonStyle(BrutalButtonStyle(inverted: true))
            }
        }
    }
}

private struct SetupRepoTargetCard: View {
    let projectPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
        .padding(20)
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
    @Binding var projectName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("How should the workspace be named?")
                .font(Font.brutalTitle(21, weight: .black))

            TextField("LegalPocketAI", text: $projectName)
                .textFieldStyle(.plain)
                .font(Font.brutalTitle(18, weight: .black))
                .padding(.horizontal, 16)
                .frame(height: 58)
                .background(BrutalInset())

            SetupNamePreviewCard(projectName: projectName)
        }
    }
}

private struct SetupNamePreviewCard: View {
    let projectName: String

    var body: some View {
        HStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    Text(monogram)
                        .font(Font.brutalHero(24))
                )
                .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 8) {
                Text("Control Center Preview")
                    .font(Font.brutalMeta())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(displayName)
                    .font(Font.brutalHero(32))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                Text("This title anchors the workspace shell after the first launch.")
                    .font(Font.brutalBody(14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(BrutalInset(selected: !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
    }

    private var displayName: String {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Workspace" : trimmed
    }

    private var monogram: String {
        let words = displayName.split(separator: " ").prefix(2)
        let initials = words.compactMap(\.first).map { String($0) }.joined()
        return initials.isEmpty ? "AF" : initials.uppercased()
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
        VStack(alignment: .leading, spacing: 18) {
            SetupLaunchHero(formState: formState)

            VStack(alignment: .leading, spacing: 10) {
                SetupFactRow(label: "PATH", value: formState.projectPath)
                SetupFactRow(label: "AGENT", value: formState.selectedAgentTools.map(\.displayName).sorted().joined(separator: " + "))
                SetupFactRow(label: "PLAT", value: formState.selectedPlatforms.map(\.displayName).sorted().joined(separator: " + "))
                SetupFactRow(label: "MODE", value: "\(formState.approvalMode.displayName) / \(formState.improvementMode.displayName)")
            }

            if isInitializing {
                ProgressView("Initializing framework...")
                    .controlSize(.large)
            }

            if let commandResult {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Created")
                        .font(Font.brutalMeta(12, weight: .black))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    ForEach(commandResult.created, id: \.self) { item in
                        Text(item)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    }

                    if !commandResult.skipped.isEmpty {
                        Divider()
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
                .padding(16)
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
        HStack(spacing: 18) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 34, weight: .black))
                )
                .frame(width: 104, height: 104)

            VStack(alignment: .leading, spacing: 10) {
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
        .padding(20)
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
        HStack(spacing: 10) {
            if currentStage != .intro {
                Button("Back", action: goBack)
                    .buttonStyle(BrutalButtonStyle(inverted: false))
            }

            Spacer()

            switch currentStage {
            case .launch:
                if didSucceed {
                    Button("Open Control Center", action: openWorkspace)
                        .buttonStyle(BrutalButtonStyle(inverted: true))
                } else {
                    Button {
                        Task { await initializeProject() }
                    } label: {
                        if isInitializing {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 18, height: 18)
                        } else {
                            Text("Initialize")
                        }
                    }
                    .buttonStyle(BrutalButtonStyle(inverted: true))
                    .disabled(isInitializing)
                }
            default:
                Button("Next", action: goForward)
                    .buttonStyle(BrutalButtonStyle(inverted: true))
                    .disabled(!canContinue)
            }
        }
    }
}

private struct SetupChoiceGrid<Content: View>: View {
    @ViewBuilder let content: Content

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
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
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.thinMaterial)
                        .overlay(
                            Image(systemName: symbolName)
                                .font(.system(size: 18, weight: .black))
                        )
                        .frame(width: 44, height: 44)

                    Spacer()

                    SetupSelectionIndicator(
                        isSelected: isSelected,
                        style: selectionStyle
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(Font.brutalTitle(18, weight: .black))
                    Text(subtitle)
                        .font(Font.brutalBody(13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
            .padding(18)
            .background(BrutalInset(selected: isSelected))
        }
        .buttonStyle(.plain)
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
    }
}

private struct BrutalInset: View {
    var selected: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.thinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: selected ? 1.5 : 1)
            )
    }

    private var fillColor: Color {
        if colorScheme == .dark {
            return selected ? Color.white.opacity(0.10) : Color.white.opacity(0.04)
        }
        return selected ? Color.white.opacity(0.38) : Color.white.opacity(0.20)
    }

    private var strokeColor: Color {
        if selected {
            return Color.primary
        }
        return colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }
}

struct BrutalButtonStyle: ButtonStyle {
    let inverted: Bool
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.brutalTitle(14, weight: .black))
            .foregroundStyle(foregroundColor)
            .frame(height: 46)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(inverted ? AnyShapeStyle(backgroundColor(configuration: configuration)) : AnyShapeStyle(.thinMaterial))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(inverted ? Color.clear : backgroundTint)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        if inverted {
            let base = colorScheme == .dark ? Color.white : Color.black
            return base.opacity(configuration.isPressed ? 0.82 : 1)
        }
        return Color.clear
    }

    private var foregroundColor: Color {
        if inverted {
            return colorScheme == .dark ? .black : .white
        }
        return .primary
    }

    private var borderColor: Color {
        if inverted {
            return colorScheme == .dark ? Color.white : Color.black
        }
        return colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private var backgroundTint: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.05)
        }
        return Color.white.opacity(0.24)
    }
}
