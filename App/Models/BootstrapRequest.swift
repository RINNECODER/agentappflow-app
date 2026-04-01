import Foundation

enum ProjectType: String, CaseIterable, Codable, Identifiable {
    case iosApp = "ios_app"
    case macOSApp = "macos_app"
    case crossPlatformApp = "cross_platform_app"
    case library = "library"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iosApp:
            "iOS App"
        case .macOSApp:
            "macOS App"
        case .crossPlatformApp:
            "Cross-platform App"
        case .library:
            "Library"
        }
    }

    var subtitle: String {
        switch self {
        case .iosApp:
            "Touch-first product with a Mac control plane."
        case .macOSApp:
            "Desktop-native workflow and local automation."
        case .crossPlatformApp:
            "Shared foundations across Apple platforms."
        case .library:
            "Tooling, SDKs, and reusable internal infrastructure."
        }
    }

    var symbolName: String {
        switch self {
        case .iosApp:
            "iphone.gen3"
        case .macOSApp:
            "laptopcomputer"
        case .crossPlatformApp:
            "square.stack.3d.up"
        case .library:
            "shippingbox"
        }
    }
}

enum PlatformChoice: String, CaseIterable, Codable, Identifiable, Hashable {
    case ios
    case macos
    case library

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ios:
            "iOS"
        case .macos:
            "macOS"
        case .library:
            "Library"
        }
    }

    var symbolName: String {
        switch self {
        case .ios:
            "iphone"
        case .macos:
            "macbook"
        case .library:
            "shippingbox"
        }
    }

    var subtitle: String {
        switch self {
        case .ios:
            "Generate memory and adapter defaults for iOS."
        case .macos:
            "Generate memory and adapter defaults for macOS."
        case .library:
            "Generate framework defaults for packages, SDKs, or tooling repos."
        }
    }
}

enum AgentToolChoice: String, CaseIterable, Codable, Identifiable, Hashable {
    case claudeCode = "claude_code"
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode:
            "Claude Code"
        case .codex:
            "Codex"
        }
    }

    var subtitle: String {
        switch self {
        case .claudeCode:
            "Reasoning-heavy pair programming with repo memory."
        case .codex:
            "Execution-oriented coding workflows with adapter guidance."
        }
    }

    var symbolName: String {
        switch self {
        case .claudeCode:
            "text.bubble"
        case .codex:
            "sparkles"
        }
    }
}

enum ApprovalMode: String, CaseIterable, Codable, Identifiable {
    case observe
    case propose
    case auto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .observe:
            "Observe"
        case .propose:
            "Propose"
        case .auto:
            "Auto"
        }
    }

    var subtitle: String {
        switch self {
        case .observe:
            "Review every framework write before it lands."
        case .propose:
            "Generate changes as reviewable proposals."
        case .auto:
            "Allow framework-owned files to update automatically."
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case "observe", "manual":
            self = .observe
        case "propose":
            self = .propose
        case "auto":
            self = .auto
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown ApprovalMode value \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .observe:
            try container.encode("manual")
        case .propose:
            try container.encode("propose")
        case .auto:
            try container.encode("auto")
        }
    }
}

enum ImprovementMode: String, CaseIterable, Codable, Identifiable {
    case observe
    case propose
    case auto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .observe:
            "Observe"
        case .propose:
            "Propose"
        case .auto:
            "Auto"
        }
    }

    var subtitle: String {
        switch self {
        case .observe:
            "Collect lessons without changing the framework."
        case .propose:
            "Generate upgrades as reviewable proposals."
        case .auto:
            "Apply framework refinements without extra prompts."
        }
    }
}

struct BootstrapRequest: Codable, Equatable {
    let projectName: String
    let projectDescription: String
    let projectPath: String
    let projectType: ProjectType
    let platforms: [PlatformChoice]
    let agentTools: [AgentToolChoice]
    let approvalMode: ApprovalMode
    let improvementMode: ImprovementMode

    private enum CodingKeys: String, CodingKey {
        case projectName = "project_name"
        case projectDescription = "project_description"
        case projectPath = "project_path"
        case projectType = "project_type"
        case platforms
        case agentTools = "agent_tools"
        case approvalMode = "approval_mode"
        case improvementMode = "improvement_mode"
    }
}

enum OnboardingValidationError: LocalizedError, Equatable {
    case missingProjectPath
    case repositoryDoesNotExist
    case projectPathIsNotDirectory
    case pathIsNotGitRepository
    case missingProjectName
    case invalidProjectNameLength(minimum: Int, maximum: Int)
    case noPlatformsSelected
    case noAgentToolsSelected

    var errorDescription: String? {
        switch self {
        case .missingProjectPath:
            "Choose a repository folder to initialize."
        case .repositoryDoesNotExist:
            "The selected repository folder could not be found."
        case .projectPathIsNotDirectory:
            "Choose a folder instead of a file."
        case .pathIsNotGitRepository:
            "The selected folder is not a git repository."
        case .missingProjectName:
            "Enter a project name before initialization."
        case .invalidProjectNameLength(let minimum, let maximum):
            "Project name must be between \(minimum) and \(maximum) characters."
        case .noPlatformsSelected:
            "Select at least one platform."
        case .noAgentToolsSelected:
            "Select at least one AI agent tool."
        }
    }
}

struct OnboardingValidationSnapshot: Equatable {
    let projectPathState: AppFieldState
    let projectNameState: AppFieldState
}

struct BootstrapPreviewPlan: Equatable {
    let treeItems: [String]
    let createdItems: [String]
    let approvalSummary: String
    let improvementSummary: String

    init(request: BootstrapRequest) {
        let adapterItems = request.agentTools.map { tool in
            ".agentappflow/adapters/\(tool.rawValue).md"
        }

        treeItems = [
            ".agentappflow/",
            ".agentappflow/project.yaml",
            ".agentappflow/context/project-brief.md",
            ".agentappflow/sessions/.gitkeep",
            ".agentappflow/adapters/",
        ] + adapterItems + [
            "AGENTS.md",
            "CLAUDE.md",
        ]

        createdItems = [
            ".agentappflow/project.yaml",
            ".agentappflow/context/project-brief.md",
            ".agentappflow/sessions/.gitkeep",
        ] + adapterItems + [
            "AGENTS.md",
            "CLAUDE.md",
        ]

        approvalSummary = request.approvalMode.subtitle
        improvementSummary = request.improvementMode.subtitle
    }
}

struct OnboardingFormState: Equatable {
    static let projectNameLengthRange = 3...40

    var projectName = ""
    var projectDescription = ""
    var projectPath = ""
    var projectType: ProjectType = .iosApp
    var selectedPlatforms: Set<PlatformChoice> = [.ios]
    var selectedAgentTools: Set<AgentToolChoice> = [.codex, .claudeCode]
    var approvalMode: ApprovalMode = .propose
    var improvementMode: ImprovementMode = .propose

    var trimmedProjectName: String {
        projectName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedProjectDescription: String {
        projectDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedProjectPath: String {
        projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func populateProjectNameIfNeeded() {
        guard trimmedProjectName.isEmpty, !trimmedProjectPath.isEmpty else { return }

        let inferredName = URL(fileURLWithPath: trimmedProjectPath).lastPathComponent
        if !inferredName.isEmpty {
            projectName = inferredName
        }
    }

    func validationSnapshot(fileManager: FileManager = .default) -> OnboardingValidationSnapshot {
        OnboardingValidationSnapshot(
            projectPathState: projectPathState(fileManager: fileManager),
            projectNameState: projectNameState()
        )
    }

    func projectPathError(fileManager: FileManager = .default) -> OnboardingValidationError? {
        let trimmedPath = trimmedProjectPath
        guard !trimmedPath.isEmpty else {
            return .missingProjectPath
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: trimmedPath, isDirectory: &isDirectory) else {
            return .repositoryDoesNotExist
        }

        guard isDirectory.boolValue else {
            return .projectPathIsNotDirectory
        }

        let gitURL = URL(fileURLWithPath: trimmedPath).appendingPathComponent(".git")
        guard fileManager.fileExists(atPath: gitURL.path) else {
            return .pathIsNotGitRepository
        }

        return nil
    }

    func projectNameError() -> OnboardingValidationError? {
        let trimmedName = trimmedProjectName
        guard !trimmedName.isEmpty else {
            return .missingProjectName
        }

        guard Self.projectNameLengthRange.contains(trimmedName.count) else {
            return .invalidProjectNameLength(
                minimum: Self.projectNameLengthRange.lowerBound,
                maximum: Self.projectNameLengthRange.upperBound
            )
        }

        return nil
    }

    func projectPathState(fileManager: FileManager = .default) -> AppFieldState {
        let trimmedPath = trimmedProjectPath
        guard !trimmedPath.isEmpty else {
            return .normal
        }

        if let error = projectPathError(fileManager: fileManager) {
            return .error(error.errorDescription ?? "Invalid repository.")
        }

        return .valid("Git repository detected")
    }

    func projectNameState() -> AppFieldState {
        let trimmedName = trimmedProjectName
        guard !trimmedName.isEmpty else {
            return .normal
        }

        if let error = projectNameError() {
            return .error(error.errorDescription ?? "Invalid project name.")
        }

        let remaining = Self.projectNameLengthRange.upperBound - trimmedName.count
        return .valid("\(remaining) characters remaining")
    }

    func previewPlan() throws -> BootstrapPreviewPlan {
        BootstrapPreviewPlan(request: try makeRequest(fileManager: .default))
    }

    func makeRequest(fileManager: FileManager = .default) throws -> BootstrapRequest {
        let trimmedPath = trimmedProjectPath
        let trimmedName = trimmedProjectName
        let trimmedDescription = trimmedProjectDescription

        if let projectPathError = projectPathError(fileManager: fileManager) {
            throw projectPathError
        }
        if let projectNameError = projectNameError() {
            throw projectNameError
        }
        guard !selectedPlatforms.isEmpty else {
            throw OnboardingValidationError.noPlatformsSelected
        }
        guard !selectedAgentTools.isEmpty else {
            throw OnboardingValidationError.noAgentToolsSelected
        }

        return BootstrapRequest(
            projectName: trimmedName,
            projectDescription: trimmedDescription,
            projectPath: trimmedPath,
            projectType: projectType,
            platforms: selectedPlatforms.sorted(by: { $0.rawValue < $1.rawValue }),
            agentTools: selectedAgentTools.sorted(by: { $0.rawValue < $1.rawValue }),
            approvalMode: approvalMode,
            improvementMode: improvementMode
        )
    }
}
