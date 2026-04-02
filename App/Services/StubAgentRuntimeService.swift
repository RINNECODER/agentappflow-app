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
    var projects: [StubProjectState]
}

private struct StubProjectState: Codable {
    var project: RegisteredProject
    var sessions: [SessionRecord]
    var frameworkHealth: [FrameworkHealthItem]
    var proposals: [FrameworkProposal]
    var settings: ProjectSettingsSnapshot
}

final class StubAgentRuntimeService: AgentRuntimeServing {
    private let defaults: UserDefaults
    private let storageKey: String
    private let fileManager: FileManager

    var capabilities: RuntimeCapabilities { .fullStub }

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
        RuntimeHealth(
            status: "ok",
            version: "phase-3-stub",
            subsystems: [
                RuntimeSubsystemHealth(name: "process", status: "ok", detail: "Stub runtime is running."),
                RuntimeSubsystemHealth(name: "sessionPipeline", status: "ok", detail: "Session state is writable in stub storage."),
                RuntimeSubsystemHealth(name: "improvementQueue", status: "ok", detail: "Proposal and retro state is readable in stub storage.")
            ]
        )
    }

    func bootstrap(request: BootstrapRequest, force: Bool) async throws -> BootstrapCommandResult {
        let state = loadState()
        let bootstrapURL = URL(fileURLWithPath: request.projectPath)
            .appendingPathComponent(".agentappflow", isDirectory: true)

        if (
            fileManager.fileExists(atPath: bootstrapURL.path)
            || state.projects.contains(where: { $0.project.projectPath == request.projectPath })
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

        if let existingIndex = state.projects.firstIndex(where: { $0.project.projectPath == request.projectPath }) {
            var existing = state.projects[existingIndex]
            existing.project = RegisteredProject(
                id: existing.project.id,
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
                registeredAt: existing.project.registeredAt,
                updatedAt: now,
                lastBootstrappedAt: now,
                latestSessionStartedAt: existing.project.latestSessionStartedAt,
                sessionCount: existing.project.sessionCount
            )
            existing.settings = ProjectSettingsSnapshot(
                approvalMode: request.approvalMode,
                memoryMode: existing.settings.memoryMode,
                improvementMode: request.improvementMode
            )
            existing.frameworkHealth = seedFrameworkHealth(
                projectPath: request.projectPath,
                createdItems: bootstrapResult.created
            )
            existing.proposals = seedProposals(now: now)
            state.projects[existingIndex] = existing
            saveState(state)
            return existing.project
        }

        let projectID = makeProjectID(path: request.projectPath)
        let sessions: [SessionRecord] = []
        let project = RegisteredProject(
            id: projectID,
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
        let projectState = StubProjectState(
            project: project,
            sessions: sessions,
            frameworkHealth: seedFrameworkHealth(projectPath: request.projectPath, createdItems: bootstrapResult.created),
            proposals: seedProposals(now: now),
            settings: ProjectSettingsSnapshot(
                approvalMode: request.approvalMode,
                memoryMode: .project,
                improvementMode: request.improvementMode
            )
        )

        state.projects.append(projectState)
        saveState(state)
        return project
    }

    func listProjects() async throws -> [RegisteredProject] {
        loadState().projects
            .map(\.project)
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
    }

    func getProject(id: String) async throws -> ProjectDetail {
        let projectState = try loadProjectState(id: id)
        let sessions = projectState.sessions.sorted { $0.startedAt > $1.startedAt }
        let latestSession = sessions.first
        let activeSession = sessions.first(where: \.isRunning)

        return ProjectDetail(
            project: projectState.project,
            latestSession: latestSession,
            sessions: sessions,
            frameworkHealth: projectState.frameworkHealth,
            proposals: projectState.proposals,
            settings: projectState.settings,
            activeSession: activeSession
        )
    }

    func startSession(projectID: String, title: String?) async throws -> SessionRecord {
        var state = loadState()
        guard let index = state.projects.firstIndex(where: { $0.project.id == projectID }) else {
            throw StubRuntimeServiceError.projectNotFound(projectID)
        }

        var projectState = state.projects[index]
        let now = Date()
        let session = seedRunningSession(
            projectID: projectID,
            projectName: projectState.project.projectName,
            startedAt: now,
            title: title
        )
        projectState.sessions.insert(session, at: 0)
        projectState.project = RegisteredProject(
            id: projectState.project.id,
            projectName: projectState.project.projectName,
            projectDescription: projectState.project.projectDescription,
            projectPath: projectState.project.projectPath,
            projectType: projectState.project.projectType,
            platforms: projectState.project.platforms,
            agentTools: projectState.project.agentTools,
            approvalMode: projectState.project.approvalMode,
            improvementMode: projectState.project.improvementMode,
            createdItems: projectState.project.createdItems,
            skippedItems: projectState.project.skippedItems,
            registeredAt: projectState.project.registeredAt,
            updatedAt: now,
            lastBootstrappedAt: projectState.project.lastBootstrappedAt,
            latestSessionStartedAt: now,
            sessionCount: projectState.project.sessionCount + 1
        )
        state.projects[index] = projectState
        saveState(state)
        return session
    }

    func removeProject(id: String) async throws {
        var state = loadState()
        guard let index = state.projects.firstIndex(where: { $0.project.id == id }) else {
            throw StubRuntimeServiceError.projectNotFound(id)
        }
        state.projects.remove(at: index)
        saveState(state)
    }

    func rebootstrapProject(id: String) async throws -> ProjectDetail {
        var state = loadState()
        guard let index = state.projects.firstIndex(where: { $0.project.id == id }) else {
            throw StubRuntimeServiceError.projectNotFound(id)
        }

        var projectState = state.projects[index]
        let now = Date()
        projectState.project = RegisteredProject(
            id: projectState.project.id,
            projectName: projectState.project.projectName,
            projectDescription: projectState.project.projectDescription,
            projectPath: projectState.project.projectPath,
            projectType: projectState.project.projectType,
            platforms: projectState.project.platforms,
            agentTools: projectState.project.agentTools,
            approvalMode: projectState.project.approvalMode,
            improvementMode: projectState.project.improvementMode,
            createdItems: projectState.project.createdItems,
            skippedItems: projectState.project.skippedItems,
            registeredAt: projectState.project.registeredAt,
            updatedAt: now,
            lastBootstrappedAt: now,
            latestSessionStartedAt: projectState.project.latestSessionStartedAt,
            sessionCount: projectState.project.sessionCount
        )
        projectState.frameworkHealth = projectState.frameworkHealth.map { item in
            FrameworkHealthItem(
                id: item.id,
                path: item.path,
                status: item.path.contains("memory/index.json") ? .missing : .present,
                detail: item.path.contains("memory/index.json")
                    ? "Memory index will be generated after the first full run."
                    : "Verified during local re-bootstrap.",
                isRequired: item.isRequired
            )
        }
        let proposal = FrameworkProposal(
            title: "Refresh framework contracts",
            summary: "Re-run bootstrap templates to align AGENTS and runtime contracts with the latest local phase.",
            filePath: ".agentappflow/context/project-brief.md",
            createdAt: now,
            changeSummary: [
                "Refresh the project brief with the latest stack summary.",
                "Rewrite bootstrap metadata to match the current approval defaults.",
            ]
        )
        projectState.proposals.insert(proposal, at: 0)

        state.projects[index] = projectState
        saveState(state)
        return try await getProject(id: id)
    }

    func updateProjectSettings(id: String, settings: ProjectSettingsSnapshot) async throws -> ProjectDetail {
        var state = loadState()
        guard let index = state.projects.firstIndex(where: { $0.project.id == id }) else {
            throw StubRuntimeServiceError.projectNotFound(id)
        }

        var projectState = state.projects[index]
        let now = Date()
        projectState.settings = settings
        projectState.project = RegisteredProject(
            id: projectState.project.id,
            projectName: projectState.project.projectName,
            projectDescription: projectState.project.projectDescription,
            projectPath: projectState.project.projectPath,
            projectType: projectState.project.projectType,
            platforms: projectState.project.platforms,
            agentTools: projectState.project.agentTools,
            approvalMode: settings.approvalMode,
            improvementMode: settings.improvementMode,
            createdItems: projectState.project.createdItems,
            skippedItems: projectState.project.skippedItems,
            registeredAt: projectState.project.registeredAt,
            updatedAt: now,
            lastBootstrappedAt: projectState.project.lastBootstrappedAt,
            latestSessionStartedAt: projectState.project.latestSessionStartedAt,
            sessionCount: projectState.project.sessionCount
        )
        state.projects[index] = projectState
        saveState(state)
        return try await getProject(id: id)
    }

    func resolveProposal(projectID: String, proposalID: String, approve: Bool) async throws -> ProjectDetail {
        var state = loadState()
        guard let index = state.projects.firstIndex(where: { $0.project.id == projectID }) else {
            throw StubRuntimeServiceError.projectNotFound(projectID)
        }

        var projectState = state.projects[index]
        let now = Date()
        projectState.proposals = projectState.proposals.map { proposal in
            guard proposal.id == proposalID else { return proposal }
            return FrameworkProposal(
                id: proposal.id,
                title: proposal.title,
                summary: proposal.summary,
                filePath: proposal.filePath,
                createdAt: proposal.createdAt,
                status: approve ? .approved : .rejected,
                changeSummary: proposal.changeSummary
            )
        }

        if approve, let matchingProposal = projectState.proposals.first(where: { $0.id == proposalID }) {
            let createdPath = matchingProposal.filePath
            if !projectState.project.createdItems.contains(createdPath) {
                var createdItems = projectState.project.createdItems
                createdItems.append(createdPath)
                projectState.project = RegisteredProject(
                    id: projectState.project.id,
                    projectName: projectState.project.projectName,
                    projectDescription: projectState.project.projectDescription,
                    projectPath: projectState.project.projectPath,
                    projectType: projectState.project.projectType,
                    platforms: projectState.project.platforms,
                    agentTools: projectState.project.agentTools,
                    approvalMode: projectState.project.approvalMode,
                    improvementMode: projectState.project.improvementMode,
                    createdItems: createdItems,
                    skippedItems: projectState.project.skippedItems,
                    registeredAt: projectState.project.registeredAt,
                    updatedAt: now,
                    lastBootstrappedAt: projectState.project.lastBootstrappedAt,
                    latestSessionStartedAt: projectState.project.latestSessionStartedAt,
                    sessionCount: projectState.project.sessionCount
                )
            }
        }

        state.projects[index] = projectState
        saveState(state)
        return try await getProject(id: projectID)
    }

    private func loadState() -> StubRuntimeState {
        guard
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder.stubRuntimeDecoder.decode(StubRuntimeState.self, from: data)
        else {
            return StubRuntimeState(projects: [])
        }

        return decoded
    }

    private func saveState(_ state: StubRuntimeState) {
        guard let data = try? JSONEncoder.stubRuntimeEncoder.encode(state) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func loadProjectState(id: String) throws -> StubProjectState {
        guard let projectState = loadState().projects.first(where: { $0.project.id == id }) else {
            throw StubRuntimeServiceError.projectNotFound(id)
        }
        return projectState
    }

    private func makeProjectID(path: String) -> String {
        let slug = URL(fileURLWithPath: path).lastPathComponent
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return "stub-\(slug)-\(abs(path.hashValue))"
    }

    private func seedCompletedSessions(projectID: String, now: Date) -> [SessionRecord] {
        let baseEntries: [(String, SessionOutcome, Int, Int, [SessionTaskProgress])] = [
            (
                "Onboarding hardening pass",
                .success,
                48,
                6,
                [
                    SessionTaskProgress(title: "Review repo contract state", status: .completed, agentRole: .planner),
                    SessionTaskProgress(title: "Patch onboarding shell", status: .completed, agentRole: .editor),
                    SessionTaskProgress(title: "Validate bootstrapping outputs", status: .completed, agentRole: .executor),
                ]
            ),
            (
                "Session trace audit",
                .partial,
                31,
                3,
                [
                    SessionTaskProgress(title: "Inspect session logs", status: .completed, agentRole: .navigator),
                    SessionTaskProgress(title: "Document runtime gaps", status: .completed, agentRole: .planner),
                    SessionTaskProgress(title: "Defer proposal application", status: .blocked, agentRole: .editor),
                ]
            ),
            (
                "Framework cleanup drill",
                .failed,
                19,
                1,
                [
                    SessionTaskProgress(title: "Apply framework patch", status: .running, agentRole: .executor),
                    SessionTaskProgress(title: "Collect rollback notes", status: .pending, agentRole: .planner),
                ]
            ),
        ]

        return baseEntries.enumerated().map { index, entry in
            let startedAt = now.addingTimeInterval(TimeInterval(-(index + 1) * 86_400))
            let durationSeconds = entry.2 * 60
            return SessionRecord(
                id: UUID().uuidString,
                projectID: projectID,
                title: entry.0,
                status: "completed",
                createdAt: startedAt,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(TimeInterval(durationSeconds)),
                outcome: entry.1,
                durationSeconds: durationSeconds,
                currentTaskName: nil,
                transcriptSummary: summary(for: entry.1),
                retroNotes: retroNotes(for: entry.1),
                taskProgress: entry.4,
                logEntries: completedLogEntries(startedAt: startedAt, outcome: entry.1),
                filesTouchedCount: entry.3,
                retroURL: ".agentappflow/retros/\(projectID)-\(index).md"
            )
        }
    }

    private func seedRunningSession(
        projectID: String,
        projectName: String,
        startedAt: Date,
        title: String?
    ) -> SessionRecord {
        let sessionTitle = title ?? "\(projectName) Runtime Session"
        let taskProgress = [
            SessionTaskProgress(title: "Plan repository update", status: .completed, agentRole: .planner),
            SessionTaskProgress(title: "Inspect session context", status: .completed, agentRole: .navigator),
            SessionTaskProgress(title: "Patch control center view", status: .running, agentRole: .editor),
            SessionTaskProgress(title: "Queue validation run", status: .pending, agentRole: .executor),
        ]
        let logEntries = [
            SessionLogEntry(timestamp: startedAt, level: "info", message: "Planner loaded workspace intent and constraints."),
            SessionLogEntry(timestamp: startedAt.addingTimeInterval(18), level: "info", message: "Navigator enumerated project files and recent tests."),
            SessionLogEntry(timestamp: startedAt.addingTimeInterval(42), level: "warning", message: "Editor is waiting on proposal approval for framework-owned files."),
            SessionLogEntry(timestamp: startedAt.addingTimeInterval(73), level: "info", message: "Executor queued a dry-run validation pass."),
        ]
        return SessionRecord(
            id: UUID().uuidString,
            projectID: projectID,
            title: sessionTitle,
            status: "running",
            createdAt: startedAt,
            startedAt: startedAt,
            outcome: nil,
            durationSeconds: nil,
            currentTaskName: "Patch control center view",
            transcriptSummary: "The active session is refining UI scaffolding and waiting on guarded framework approval.",
            retroNotes: [
                "Keep the session banner visible while the editor is writing.",
                "Surface proposal approval state before auto-applying framework files.",
            ],
            taskProgress: taskProgress,
            logEntries: logEntries,
            filesTouchedCount: 2,
            retroURL: nil
        )
    }

    private func completedLogEntries(startedAt: Date, outcome: SessionOutcome) -> [SessionLogEntry] {
        [
            SessionLogEntry(timestamp: startedAt, level: "info", message: "Planner established the task sequence."),
            SessionLogEntry(timestamp: startedAt.addingTimeInterval(12), level: "info", message: "Navigator inspected the local repo contract."),
            SessionLogEntry(
                timestamp: startedAt.addingTimeInterval(28),
                level: outcome == .failed ? "error" : "info",
                message: outcome == .failed
                    ? "Executor hit a guardrail failure while attempting the last patch."
                    : "Editor applied the requested changes and prepared validation."
            ),
        ]
    }

    private func summary(for outcome: SessionOutcome) -> String {
        switch outcome {
        case .success:
            "The workflow completed cleanly and the resulting changes matched the contract."
        case .partial:
            "The main task landed, but a follow-up framework proposal remained pending."
        case .failed:
            "The session stopped on a guarded write and left notes for a manual retry."
        }
    }

    private func retroNotes(for outcome: SessionOutcome) -> [String] {
        switch outcome {
        case .success:
            [
                "Keep the plan narrow before touching framework-owned files.",
                "Validation passed after the first patch attempt.",
            ]
        case .partial:
            [
                "Proposal generation worked, but approval friction interrupted the flow.",
                "A faster summary panel would have shortened the review cycle.",
            ]
        case .failed:
            [
                "The guarded write needs a clearer approval path in the UI.",
                "Runtime retries should surface the failed command earlier.",
            ]
        }
    }

    private func seedFrameworkHealth(projectPath: String, createdItems: [String]) -> [FrameworkHealthItem] {
        let requiredPaths = [
            ".agentappflow/project.yaml": "Project contract registered for the runtime.",
            ".agentappflow/context/project-brief.md": "Project brief available to planner and navigator roles.",
            ".agentappflow/sessions/.gitkeep": "Session ledger directory initialized.",
            "AGENTS.md": "Repo-specific agent instructions detected.",
            "CLAUDE.md": "Claude-specific behavior contract available.",
            ".agentappflow/memory/index.json": "Memory index is still pending the first runtime synthesis.",
        ]

        return requiredPaths.map { path, detail in
            let isPresent = createdItems.contains(path) || !path.contains("memory/index.json")
            return FrameworkHealthItem(
                path: path,
                status: isPresent ? .present : .missing,
                detail: detail
            )
        }
    }

    private func seedProposals(now: Date) -> [FrameworkProposal] {
        [
            FrameworkProposal(
                title: "Tighten AGENTS repo contract",
                summary: "Clarify approval routing and runtime health escalation for the local agent workflow.",
                filePath: "AGENTS.md",
                createdAt: now.addingTimeInterval(-7_200),
                changeSummary: [
                    "Add the local runtime escalation rule.",
                    "Describe the Phase 3 control center expectations for agents.",
                ]
            ),
            FrameworkProposal(
                title: "Seed session retro template",
                summary: "Create a richer retrospective stub so failed sessions capture next actions explicitly.",
                filePath: ".agentappflow/retros/template.md",
                createdAt: now.addingTimeInterval(-3_600),
                changeSummary: [
                    "Add outcome taxonomy guidance.",
                    "Reserve a block for framework proposals and rollback notes.",
                ]
            ),
        ]
    }
}

enum AppRuntimeServiceFactory {
    static func makeDefaultService(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard,
        pythonFrameworkOverrideKey: String = "pythonFrameworkOverride"
    ) -> AgentRuntimeServing {
        if environment["AGENTAPPFLOW_USE_STUB_RUNTIME"] == "1" {
            return StubAgentRuntimeService()
        }

        let pythonFrameworkOverride = defaults.string(forKey: pythonFrameworkOverrideKey)
        return AgentRuntimeService(pythonFrameworkOverride: pythonFrameworkOverride)
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
