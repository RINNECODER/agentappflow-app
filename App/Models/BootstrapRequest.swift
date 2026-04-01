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
    case manual
    case propose
    case auto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual:
            "Manual"
        case .propose:
            "Propose"
        case .auto:
            "Auto"
        }
    }

    var subtitle: String {
        switch self {
        case .manual:
            "Require direct confirmation before changes."
        case .propose:
            "Draft framework updates and review them before activation."
        case .auto:
            "Allow framework-owned files to update automatically."
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
    let projectPath: String
    let projectType: ProjectType
    let platforms: [PlatformChoice]
    let agentTools: [AgentToolChoice]
    let approvalMode: ApprovalMode
    let improvementMode: ImprovementMode

    private enum CodingKeys: String, CodingKey {
        case projectName = "project_name"
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
    case missingProjectName
    case noPlatformsSelected
    case noAgentToolsSelected

    var errorDescription: String? {
        switch self {
        case .missingProjectPath:
            "Choose a repository folder to initialize."
        case .missingProjectName:
            "Enter a project name before initialization."
        case .noPlatformsSelected:
            "Select at least one platform."
        case .noAgentToolsSelected:
            "Select at least one AI agent tool."
        }
    }
}

struct OnboardingFormState: Equatable {
    var projectName = ""
    var projectPath = ""
    var projectType: ProjectType = .iosApp
    var selectedPlatforms: Set<PlatformChoice> = [.ios]
    var selectedAgentTools: Set<AgentToolChoice> = [.codex, .claudeCode]
    var approvalMode: ApprovalMode = .propose
    var improvementMode: ImprovementMode = .propose

    mutating func populateProjectNameIfNeeded() {
        let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty, !projectPath.isEmpty else { return }

        let inferredName = URL(fileURLWithPath: projectPath).lastPathComponent
        if !inferredName.isEmpty {
            projectName = inferredName
        }
    }

    func makeRequest() throws -> BootstrapRequest {
        let trimmedPath = projectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedPath.isEmpty else {
            throw OnboardingValidationError.missingProjectPath
        }
        guard !trimmedName.isEmpty else {
            throw OnboardingValidationError.missingProjectName
        }
        guard !selectedPlatforms.isEmpty else {
            throw OnboardingValidationError.noPlatformsSelected
        }
        guard !selectedAgentTools.isEmpty else {
            throw OnboardingValidationError.noAgentToolsSelected
        }

        return BootstrapRequest(
            projectName: trimmedName,
            projectPath: trimmedPath,
            projectType: projectType,
            platforms: selectedPlatforms.sorted(by: { $0.rawValue < $1.rawValue }),
            agentTools: selectedAgentTools.sorted(by: { $0.rawValue < $1.rawValue }),
            approvalMode: approvalMode,
            improvementMode: improvementMode
        )
    }
}
