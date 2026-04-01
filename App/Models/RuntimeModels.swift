import Foundation

struct RuntimeHealth: Decodable, Equatable {
    let status: String
    let version: String
}

struct RegisteredProject: Codable, Equatable, Identifiable {
    let id: String
    let projectName: String
    let projectDescription: String
    let projectPath: String
    let projectType: ProjectType
    let platforms: [PlatformChoice]
    let agentTools: [AgentToolChoice]
    let approvalMode: ApprovalMode
    let improvementMode: ImprovementMode
    let createdItems: [String]
    let skippedItems: [String]
    let registeredAt: Date
    let updatedAt: Date
    let lastBootstrappedAt: Date
    let sessionCount: Int

    init(
        id: String,
        projectName: String,
        projectDescription: String,
        projectPath: String,
        projectType: ProjectType,
        platforms: [PlatformChoice],
        agentTools: [AgentToolChoice],
        approvalMode: ApprovalMode,
        improvementMode: ImprovementMode,
        createdItems: [String],
        skippedItems: [String],
        registeredAt: Date,
        updatedAt: Date,
        lastBootstrappedAt: Date,
        sessionCount: Int
    ) {
        self.id = id
        self.projectName = projectName
        self.projectDescription = projectDescription
        self.projectPath = projectPath
        self.projectType = projectType
        self.platforms = platforms
        self.agentTools = agentTools
        self.approvalMode = approvalMode
        self.improvementMode = improvementMode
        self.createdItems = createdItems
        self.skippedItems = skippedItems
        self.registeredAt = registeredAt
        self.updatedAt = updatedAt
        self.lastBootstrappedAt = lastBootstrappedAt
        self.sessionCount = sessionCount
    }
}

struct SessionRecord: Codable, Equatable, Identifiable {
    let id: String
    let projectID: String
    let title: String
    let status: String
    let createdAt: Date
    let startedAt: Date

    init(
        id: String,
        projectID: String,
        title: String,
        status: String,
        createdAt: Date,
        startedAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.status = status
        self.createdAt = createdAt
        self.startedAt = startedAt
    }
}

struct ProjectDetail: Decodable, Equatable {
    let project: RegisteredProject
    let latestSession: SessionRecord?
}

struct ProjectListPayload: Decodable, Equatable {
    let projects: [RegisteredProject]
}

struct RegisteredProjectPayload: Decodable, Equatable {
    let project: RegisteredProject
}

struct SessionRecordPayload: Decodable, Equatable {
    let session: SessionRecord
}

struct RuntimeBootstrapRequest: Encodable {
    let projectName: String
    let projectDescription: String
    let projectPath: String
    let projectType: ProjectType
    let platforms: [PlatformChoice]
    let agentTools: [AgentToolChoice]
    let approvalMode: ApprovalMode
    let improvementMode: ImprovementMode
    let force: Bool

    init(request: BootstrapRequest, force: Bool = false) {
        projectName = request.projectName
        projectDescription = request.projectDescription
        projectPath = request.projectPath
        projectType = request.projectType
        platforms = request.platforms
        agentTools = request.agentTools
        approvalMode = request.approvalMode
        improvementMode = request.improvementMode
        self.force = force
    }

    private enum CodingKeys: String, CodingKey {
        case projectName = "project_name"
        case projectDescription = "project_description"
        case projectPath = "project_path"
        case projectType = "project_type"
        case platforms
        case agentTools = "agent_tools"
        case approvalMode = "approval_mode"
        case improvementMode = "improvement_mode"
        case force
    }
}

struct RegisterProjectRequest: Encodable {
    let projectName: String
    let projectDescription: String
    let projectPath: String
    let projectType: ProjectType
    let platforms: [PlatformChoice]
    let agentTools: [AgentToolChoice]
    let approvalMode: ApprovalMode
    let improvementMode: ImprovementMode
    let bootstrapResult: BootstrapCommandResult

    init(request: BootstrapRequest, bootstrapResult: BootstrapCommandResult) {
        projectName = request.projectName
        projectDescription = request.projectDescription
        projectPath = request.projectPath
        projectType = request.projectType
        platforms = request.platforms
        agentTools = request.agentTools
        approvalMode = request.approvalMode
        improvementMode = request.improvementMode
        self.bootstrapResult = bootstrapResult
    }

    private enum CodingKeys: String, CodingKey {
        case projectName = "project_name"
        case projectDescription = "project_description"
        case projectPath = "project_path"
        case projectType = "project_type"
        case platforms
        case agentTools = "agent_tools"
        case approvalMode = "approval_mode"
        case improvementMode = "improvement_mode"
        case bootstrapResult = "bootstrap_result"
    }
}

struct StartSessionRequest: Encodable {
    let projectID: String
    let title: String?

    private enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case title
    }
}

enum EmptyRuntimeParams: Encodable {
    case value
}
