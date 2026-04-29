import Foundation

enum RuntimeDateCoding {
    static let dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()

        if let timestamp = try? container.decode(Double.self) {
            return Date(timeIntervalSince1970: timestamp)
        }

        let value = try container.decode(String.self)
        for formatter in iso8601Formatters {
            if let date = formatter.date(from: value) {
                return date
            }
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected an ISO-8601 date string."
        )
    }

    private static let iso8601Formatters: [ISO8601DateFormatter] = [
        {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }(),
        {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter
        }(),
    ]
}

struct RuntimeSubsystemHealth: Decodable, Equatable {
    let name: String
    let status: String
    let detail: String

    var isHealthy: Bool {
        status.lowercased() == "ok"
    }
}

struct RuntimeHealth: Decodable, Equatable {
    let status: String
    let version: String
    let subsystems: [RuntimeSubsystemHealth]

    init(
        status: String,
        version: String,
        subsystems: [RuntimeSubsystemHealth] = []
    ) {
        self.status = status
        self.version = version
        self.subsystems = subsystems
    }

    var isHealthy: Bool {
        status.lowercased() == "ok"
    }

    var isResponsive: Bool {
        ["ok", "degraded"].contains(status.lowercased())
    }

    var hasDegradedSubsystems: Bool {
        subsystems.contains { !$0.isHealthy }
    }
}

enum MemoryMode: String, CaseIterable, Codable, Identifiable {
    case session
    case project
    case continuous

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .session:
            "Session"
        case .project:
            "Project"
        case .continuous:
            "Continuous"
        }
    }

    var subtitle: String {
        switch self {
        case .session:
            "Keep memory scoped to the active session."
        case .project:
            "Retain project-level context between sessions."
        case .continuous:
            "Persist broader working memory across runs."
        }
    }
}

enum FrameworkHealthStatus: String, Codable, CaseIterable {
    case present
    case missing
}

enum ProposalStatus: String, Codable, CaseIterable {
    case pending
    case approved
    case rejected
}

enum SessionOutcome: String, Codable, CaseIterable {
    case success
    case partial
    case failed
}

enum SessionTaskStatus: String, Codable, CaseIterable {
    case pending
    case running
    case completed
    case blocked
}

enum AgentRole: String, Codable, CaseIterable, Identifiable {
    case planner
    case navigator
    case editor
    case executor

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

struct FrameworkHealthItem: Codable, Equatable, Identifiable {
    let id: String
    let path: String
    let status: FrameworkHealthStatus
    let detail: String
    let isRequired: Bool

    init(
        id: String = UUID().uuidString,
        path: String,
        status: FrameworkHealthStatus,
        detail: String,
        isRequired: Bool = true
    ) {
        self.id = id
        self.path = path
        self.status = status
        self.detail = detail
        self.isRequired = isRequired
    }
}

struct SessionTaskProgress: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let status: SessionTaskStatus
    let agentRole: AgentRole

    init(
        id: String = UUID().uuidString,
        title: String,
        status: SessionTaskStatus,
        agentRole: AgentRole
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.agentRole = agentRole
    }
}

struct SessionLogEntry: Codable, Equatable, Identifiable {
    let id: String
    let timestamp: Date
    let level: String
    let message: String

    init(
        id: String = UUID().uuidString,
        timestamp: Date,
        level: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

struct FrameworkProposal: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let filePath: String
    let createdAt: Date
    let status: ProposalStatus
    let changeSummary: [String]

    init(
        id: String = UUID().uuidString,
        title: String,
        summary: String,
        filePath: String,
        createdAt: Date,
        status: ProposalStatus = .pending,
        changeSummary: [String]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.filePath = filePath
        self.createdAt = createdAt
        self.status = status
        self.changeSummary = changeSummary
    }
}

struct ProjectSettingsSnapshot: Codable, Equatable {
    let approvalMode: ApprovalMode
    let memoryMode: MemoryMode
    let improvementMode: ImprovementMode

    init(
        approvalMode: ApprovalMode,
        memoryMode: MemoryMode,
        improvementMode: ImprovementMode
    ) {
        self.approvalMode = approvalMode
        self.memoryMode = memoryMode
        self.improvementMode = improvementMode
    }
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
    let latestSessionStartedAt: Date?
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
        latestSessionStartedAt: Date? = nil,
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
        self.latestSessionStartedAt = latestSessionStartedAt
        self.sessionCount = sessionCount
    }

    var stackSummary: String {
        ([projectType.displayName] + platforms.map(\.displayName) + agentTools.map(\.displayName))
            .joined(separator: " • ")
    }

    var lastActivityAt: Date {
        latestSessionStartedAt ?? updatedAt
    }
}

struct SessionRecord: Codable, Equatable, Identifiable {
    let id: String
    let projectID: String
    let title: String
    let status: String
    let createdAt: Date
    let startedAt: Date
    let endedAt: Date?
    let outcome: SessionOutcome?
    let durationSeconds: Int?
    let currentTaskName: String?
    let transcriptSummary: String?
    let retroNotes: [String]
    let taskProgress: [SessionTaskProgress]
    let logEntries: [SessionLogEntry]
    let filesTouchedCount: Int
    let retroURL: String?

    init(
        id: String,
        projectID: String,
        title: String,
        status: String,
        createdAt: Date,
        startedAt: Date,
        endedAt: Date? = nil,
        outcome: SessionOutcome? = nil,
        durationSeconds: Int? = nil,
        currentTaskName: String? = nil,
        transcriptSummary: String? = nil,
        retroNotes: [String] = [],
        taskProgress: [SessionTaskProgress] = [],
        logEntries: [SessionLogEntry] = [],
        filesTouchedCount: Int = 0,
        retroURL: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.status = status
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.outcome = outcome
        self.durationSeconds = durationSeconds
        self.currentTaskName = currentTaskName
        self.transcriptSummary = transcriptSummary
        self.retroNotes = retroNotes
        self.taskProgress = taskProgress
        self.logEntries = logEntries
        self.filesTouchedCount = filesTouchedCount
        self.retroURL = retroURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        projectID = try container.decode(String.self, forKey: .projectID)
        title = try container.decode(String.self, forKey: .title)
        status = try container.decode(String.self, forKey: .status)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        outcome = try container.decodeIfPresent(SessionOutcome.self, forKey: .outcome)
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds)
        currentTaskName = try container.decodeIfPresent(String.self, forKey: .currentTaskName)
        transcriptSummary = try container.decodeIfPresent(String.self, forKey: .transcriptSummary)
        retroNotes = try container.decodeIfPresent([String].self, forKey: .retroNotes) ?? []
        taskProgress = try container.decodeIfPresent([SessionTaskProgress].self, forKey: .taskProgress) ?? []
        logEntries = try container.decodeIfPresent([SessionLogEntry].self, forKey: .logEntries) ?? []
        filesTouchedCount = try container.decodeIfPresent(Int.self, forKey: .filesTouchedCount) ?? 0
        retroURL = try container.decodeIfPresent(String.self, forKey: .retroURL)
    }

    var isRunning: Bool {
        status.lowercased() == "running"
    }

    var resolvedDurationSeconds: Int {
        if let durationSeconds {
            return durationSeconds
        }

        let endDate = endedAt ?? Date()
        return max(Int(endDate.timeIntervalSince(startedAt)), 0)
    }

    var outcomeBadgeLabel: String {
        if let outcome {
            return outcome.rawValue.capitalized
        }
        return status.capitalized
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case projectID = "projectId"
        case title
        case status
        case createdAt
        case startedAt
        case endedAt
        case outcome
        case durationSeconds
        case currentTaskName
        case transcriptSummary
        case retroNotes
        case taskProgress
        case logEntries
        case filesTouchedCount
        case retroURL = "retroUrl"
    }
}

struct ProjectDetail: Decodable, Equatable {
    let project: RegisteredProject
    let latestSession: SessionRecord?
    let sessions: [SessionRecord]
    let frameworkHealth: [FrameworkHealthItem]
    let proposals: [FrameworkProposal]
    let settings: ProjectSettingsSnapshot
    let activeSession: SessionRecord?

    init(
        project: RegisteredProject,
        latestSession: SessionRecord?,
        sessions: [SessionRecord] = [],
        frameworkHealth: [FrameworkHealthItem] = [],
        proposals: [FrameworkProposal] = [],
        settings: ProjectSettingsSnapshot? = nil,
        activeSession: SessionRecord? = nil
    ) {
        self.project = project
        self.latestSession = latestSession
        self.sessions = sessions.isEmpty ? (latestSession.map { [$0] } ?? []) : sessions
        self.frameworkHealth = frameworkHealth
        self.proposals = proposals
        self.settings = settings ?? ProjectSettingsSnapshot(
            approvalMode: project.approvalMode,
            memoryMode: .project,
            improvementMode: project.improvementMode
        )
        self.activeSession = activeSession ?? self.sessions.first(where: \.isRunning)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let project = try container.decode(RegisteredProject.self, forKey: .project)
        let latestSession = try container.decodeIfPresent(SessionRecord.self, forKey: .latestSession)
        let sessions = try container.decodeIfPresent([SessionRecord].self, forKey: .sessions) ?? []
        let frameworkHealth = try container.decodeIfPresent([FrameworkHealthItem].self, forKey: .frameworkHealth) ?? []
        let proposals = try container.decodeIfPresent([FrameworkProposal].self, forKey: .proposals) ?? []
        let settings = try container.decodeIfPresent(ProjectSettingsSnapshot.self, forKey: .settings)
        let activeSession = try container.decodeIfPresent(SessionRecord.self, forKey: .activeSession)
        self.init(
            project: project,
            latestSession: latestSession,
            sessions: sessions,
            frameworkHealth: frameworkHealth,
            proposals: proposals,
            settings: settings,
            activeSession: activeSession
        )
    }

    var pendingProposals: [FrameworkProposal] {
        proposals.filter { $0.status == .pending }
    }

    private enum CodingKeys: String, CodingKey {
        case project
        case latestSession
        case sessions
        case frameworkHealth
        case proposals
        case settings
        case activeSession
    }
}

struct ProjectListPayload: Decodable, Equatable {
    let projects: [RegisteredProject]

    init(projects: [RegisteredProject]) {
        self.projects = projects
    }

    init(from decoder: Decoder) throws {
        if let projects = try? [RegisteredProject].init(from: decoder) {
            self.init(projects: projects)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(projects: try container.decode([RegisteredProject].self, forKey: .projects))
    }

    private enum CodingKeys: String, CodingKey {
        case projects
    }
}

struct RegisteredProjectPayload: Decodable, Equatable {
    let project: RegisteredProject

    init(project: RegisteredProject) {
        self.project = project
    }

    init(from decoder: Decoder) throws {
        if let project = try? RegisteredProject(from: decoder) {
            self.init(project: project)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(project: try container.decode(RegisteredProject.self, forKey: .project))
    }

    private enum CodingKeys: String, CodingKey {
        case project
    }
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
