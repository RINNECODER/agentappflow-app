import Foundation

enum StubRuntimeServiceError: LocalizedError, Equatable {
    case projectNotFound(String)
    case bootstrapAlreadyExists(path: String)
    case permissionDenied(path: String)

    var errorDescription: String? {
        switch self {
        case .projectNotFound(let id):
            "Project \(id) could not be found in the local onboarding stub."
        case .bootstrapAlreadyExists(let path):
            "AgentAppFlow is already bootstrapped at \(path)."
        case .permissionDenied(let path):
            "AgentAppFlow does not have permission to write inside \(path)."
        }
    }
}

private struct StubRuntimeState: Codable {
    var projects: [RegisteredProject]
    var sessionsByProjectID: [String: [SessionRecord]]
}

final class StubAgentRuntimeService: AgentRuntimeServing {
    private let defaults: UserDefaults
    private let storageKey: String
    private let fileManager: FileManager

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "stubAgentRuntimeState",
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.fileManager = fileManager
    }

    func healthCheck() async throws -> RuntimeHealth {
        RuntimeHealth(status: "ok", version: "phase-2-stub")
    }

    func bootstrap(request: BootstrapRequest, force: Bool) async throws -> BootstrapCommandResult {
        let state = loadState()
        let bootstrapURL = URL(fileURLWithPath: request.projectPath)
            .appendingPathComponent(".agentappflow", isDirectory: true)

        if (
            fileManager.fileExists(atPath: bootstrapURL.path)
            || state.projects.contains(where: { $0.projectPath == request.projectPath })
        ), !force {
            throw StubRuntimeServiceError.bootstrapAlreadyExists(path: request.projectPath)
        }

        guard fileManager.isWritableFile(atPath: request.projectPath) else {
            throw StubRuntimeServiceError.permissionDenied(path: request.projectPath)
        }

        let previewPlan = BootstrapPreviewPlan(request: request)
        return BootstrapCommandResult(
            ok: true,
            message: force ? "Stub re-bootstrap complete." : "Stub bootstrap complete.",
            created: previewPlan.createdItems,
            skipped: force ? [] : []
        )
    }

    func registerProject(
        request: BootstrapRequest,
        bootstrapResult: BootstrapCommandResult
    ) async throws -> RegisteredProject {
        var state = loadState()
        let now = Date()

        if let existingIndex = state.projects.firstIndex(where: { $0.projectPath == request.projectPath }) {
            let existingProject = state.projects[existingIndex]
            let updatedProject = RegisteredProject(
                id: existingProject.id,
                projectName: request.projectName,
                projectDescription: request.projectDescription,
                projectPath: request.projectPath,
                projectType: request.projectType,
                platforms: request.platforms,
                agentTools: request.agentTools,
                approvalMode: request.approvalMode,
                improvementMode: request.improvementMode,
                createdItems: bootstrapResult.created,
                skippedItems: bootstrapResult.skipped,
                registeredAt: existingProject.registeredAt,
                updatedAt: now,
                lastBootstrappedAt: now,
                latestSessionStartedAt: existingProject.latestSessionStartedAt,
                sessionCount: existingProject.sessionCount
            )
            state.projects[existingIndex] = updatedProject
            saveState(state)
            return updatedProject
        }

        let project = RegisteredProject(
            id: makeProjectID(path: request.projectPath),
            projectName: request.projectName,
            projectDescription: request.projectDescription,
            projectPath: request.projectPath,
            projectType: request.projectType,
            platforms: request.platforms,
            agentTools: request.agentTools,
            approvalMode: request.approvalMode,
            improvementMode: request.improvementMode,
            createdItems: bootstrapResult.created,
            skippedItems: bootstrapResult.skipped,
            registeredAt: now,
            updatedAt: now,
            lastBootstrappedAt: now,
            latestSessionStartedAt: nil,
            sessionCount: 0
        )

        state.projects.append(project)
        saveState(state)
        return project
    }

    func listProjects() async throws -> [RegisteredProject] {
        loadState().projects.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
    }

    func getProject(id: String) async throws -> ProjectDetail {
        let state = loadState()
        guard let project = state.projects.first(where: { $0.id == id }) else {
            throw StubRuntimeServiceError.projectNotFound(id)
        }

        let latestSession = state.sessionsByProjectID[id]?
            .sorted(by: { $0.startedAt > $1.startedAt })
            .first

        return ProjectDetail(project: project, latestSession: latestSession)
    }

    func startSession(projectID: String, title: String?) async throws -> SessionRecord {
        var state = loadState()
        guard let projectIndex = state.projects.firstIndex(where: { $0.id == projectID }) else {
            throw StubRuntimeServiceError.projectNotFound(projectID)
        }

        let now = Date()
        let session = SessionRecord(
            id: UUID().uuidString,
            projectID: projectID,
            title: title ?? "\(state.projects[projectIndex].projectName) Session",
            status: "running",
            createdAt: now,
            startedAt: now
        )

        var sessions = state.sessionsByProjectID[projectID, default: []]
        sessions.insert(session, at: 0)
        state.sessionsByProjectID[projectID] = sessions

        let currentProject = state.projects[projectIndex]
        state.projects[projectIndex] = RegisteredProject(
            id: currentProject.id,
            projectName: currentProject.projectName,
            projectDescription: currentProject.projectDescription,
            projectPath: currentProject.projectPath,
            projectType: currentProject.projectType,
            platforms: currentProject.platforms,
            agentTools: currentProject.agentTools,
            approvalMode: currentProject.approvalMode,
            improvementMode: currentProject.improvementMode,
            createdItems: currentProject.createdItems,
            skippedItems: currentProject.skippedItems,
            registeredAt: currentProject.registeredAt,
            updatedAt: now,
            lastBootstrappedAt: currentProject.lastBootstrappedAt,
            latestSessionStartedAt: now,
            sessionCount: currentProject.sessionCount + 1
        )

        saveState(state)
        return session
    }

    private func loadState() -> StubRuntimeState {
        guard
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder.stubRuntimeDecoder.decode(StubRuntimeState.self, from: data)
        else {
            return StubRuntimeState(projects: [], sessionsByProjectID: [:])
        }

        return decoded
    }

    private func saveState(_ state: StubRuntimeState) {
        guard let data = try? JSONEncoder.stubRuntimeEncoder.encode(state) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func makeProjectID(path: String) -> String {
        let slug = URL(fileURLWithPath: path).lastPathComponent
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return "stub-\(slug)-\(abs(path.hashValue))"
    }
}

enum AppRuntimeServiceFactory {
    static func makeDefaultService(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AgentRuntimeServing {
        if environment["AGENTAPPFLOW_USE_STUB_RUNTIME"] == "1" {
            return StubAgentRuntimeService()
        }
        return AgentRuntimeService()
    }
}

private extension JSONDecoder {
    static let stubRuntimeDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension JSONEncoder {
    static let stubRuntimeEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
