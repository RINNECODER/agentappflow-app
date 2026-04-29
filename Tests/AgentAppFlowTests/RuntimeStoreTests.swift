import XCTest
@testable import AgentAppFlow

@MainActor
final class RuntimeStoreTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        UserDefaults().removePersistentDomain(forName: #file)
    }

    func testRegisteredProjectDecodesSnakeCasePayload() throws {
        let payload = """
        {
          "projects": [
            {
              "id": "project-1",
              "project_name": "LegalPocketAI",
              "project_description": "AI legal assistant for contract review.",
              "project_path": "/tmp/LegalPocketAI",
              "project_type": "ios_app",
              "platforms": ["ios", "macos"],
              "agent_tools": ["codex", "claude_code"],
              "approval_mode": "propose",
              "improvement_mode": "propose",
              "created_items": ["AGENTS.md"],
              "skipped_items": [],
              "registered_at": "2026-03-31T20:00:00Z",
              "updated_at": "2026-03-31T20:00:00Z",
              "last_bootstrapped_at": "2026-03-31T20:00:00Z",
              "session_count": 1
            }
          ]
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = RuntimeDateCoding.dateDecodingStrategy
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let projects = try decoder.decode(ProjectListPayload.self, from: Data(payload.utf8)).projects

        XCTAssertEqual(projects.first?.projectName, "LegalPocketAI")
        XCTAssertEqual(projects.first?.platforms, [.ios, .macos])
        XCTAssertEqual(projects.first?.agentTools, [.codex, .claudeCode])
        XCTAssertEqual(projects.first?.sessionCount, 1)
    }

    func testProjectListPayloadDecodesBareRuntimeArray() throws {
        let payload = """
        [
          {
            "id": "project-1",
            "project_name": "LegalPocketAI",
            "project_description": "AI legal assistant for contract review.",
            "project_path": "/tmp/LegalPocketAI",
            "project_type": "ios_app",
            "platforms": ["ios", "macos"],
            "agent_tools": ["codex", "claude_code"],
            "approval_mode": "propose",
            "improvement_mode": "propose",
            "created_items": ["AGENTS.md"],
            "skipped_items": [],
            "registered_at": "2026-03-31T20:00:00.123456+00:00",
            "updated_at": "2026-03-31T20:00:00.123456+00:00",
            "last_bootstrapped_at": "2026-03-31T20:00:00.123456+00:00",
            "session_count": 1
          }
        ]
        """

        let projects = try runtimeDecoder().decode(ProjectListPayload.self, from: Data(payload.utf8)).projects

        XCTAssertEqual(projects.count, 1)
        let project = try XCTUnwrap(projects.first)
        XCTAssertEqual(project.projectName, "LegalPocketAI")
        XCTAssertEqual(project.registeredAt.timeIntervalSince1970, 1_774_987_200.123456, accuracy: 0.001)
    }

    func testRegisteredProjectPayloadDecodesRawRuntimeProject() throws {
        let payload = """
        {
          "id": "project-1",
          "project_name": "LegalPocketAI",
          "project_description": "AI legal assistant for contract review.",
          "project_path": "/tmp/LegalPocketAI",
          "project_type": "ios_app",
          "platforms": ["ios"],
          "agent_tools": ["codex"],
          "approval_mode": "propose",
          "improvement_mode": "propose",
          "created_items": [],
          "skipped_items": [],
          "registered_at": "2026-03-31T20:00:00.123456+00:00",
          "updated_at": "2026-03-31T20:00:00.123456+00:00",
          "last_bootstrapped_at": "2026-03-31T20:00:00.123456+00:00",
          "session_count": 0
        }
        """

        let project = try runtimeDecoder().decode(RegisteredProjectPayload.self, from: Data(payload.utf8)).project

        XCTAssertEqual(project.id, "project-1")
        XCTAssertEqual(project.sessionCount, 0)
        XCTAssertEqual(project.registeredAt.timeIntervalSince1970, 1_774_987_200.123456, accuracy: 0.001)
    }

    func testDegradedRuntimeHealthIsResponsive() {
        let health = RuntimeHealth(status: "degraded", version: "0.2.0")

        XCTAssertFalse(health.isHealthy)
        XCTAssertTrue(health.isResponsive)
    }

    func testStoreLoadsProjectsAndSelectsPreferredProject() async {
        let project = sampleProject(id: "preferred-project")
        let session = sampleSession(projectID: project.id)
        let service = MockRuntimeService(
            projects: [project],
            projectDetails: [project.id: ProjectDetail(project: project, latestSession: session)]
        )
        let store = AppRuntimeStore(runtimeService: service)

        await store.loadProjects(select: project.id)

        XCTAssertEqual(store.projects, [project])
        XCTAssertEqual(store.selectedProjectDetail?.project.id, project.id)
        XCTAssertEqual(store.selectedProjectDetail?.latestSession, session)
        XCTAssertEqual(service.listProjectsCalls, 1)
    }

    func testStoreRestoresPersistedProjectSelectionBeforeFallingBackToFirstProject() async {
        let firstProject = sampleProject(id: "project-1", name: "First Project")
        let secondProject = sampleProject(id: "project-2", name: "Second Project")
        let service = MockRuntimeService(
            projects: [firstProject, secondProject],
            projectDetails: [
                firstProject.id: ProjectDetail(project: firstProject, latestSession: nil),
                secondProject.id: ProjectDetail(project: secondProject, latestSession: nil),
            ]
        )
        let defaults = makeDefaults()
        defaults.set(secondProject.id, forKey: "selectedRegisteredProjectID")
        let store = AppRuntimeStore(
            runtimeService: service,
            defaults: defaults,
            selectedProjectIDKey: "selectedRegisteredProjectID"
        )

        await store.loadProjects()

        XCTAssertEqual(store.selectedProjectDetail?.project.id, secondProject.id)
    }

    func testStorePreservesSelectionWhenRefreshFails() async {
        let project = sampleProject(id: "project-1")
        let detail = ProjectDetail(project: project, latestSession: nil)
        let service = MockRuntimeService(
            projects: [project],
            projectDetails: [project.id: detail]
        )
        let defaults = makeDefaults()
        let store = AppRuntimeStore(
            runtimeService: service,
            defaults: defaults,
            selectedProjectIDKey: "selectedRegisteredProjectID"
        )

        await store.selectProject(id: project.id)
        service.healthCheckError = MockRuntimeError.message("runtime unavailable")

        await store.loadProjects()

        XCTAssertEqual(store.selectedProjectDetail?.project.id, project.id)
        XCTAssertEqual(store.presentation.errorMessage, "runtime unavailable")
        XCTAssertEqual(defaults.string(forKey: "selectedRegisteredProjectID"), project.id)
    }

    func testPresentationStateTracksErrorsAndToasts() async {
        let project = sampleProject(id: "project-1")
        let service = MockRuntimeService(
            projects: [project],
            projectDetails: [project.id: ProjectDetail(project: project, latestSession: nil)]
        )
        service.getProjectError = MockRuntimeError.message("project failed")
        let store = AppRuntimeStore(runtimeService: service)

        await store.selectProject(id: project.id)

        XCTAssertEqual(store.presentation.errorMessage, "project failed")
        XCTAssertEqual(store.presentation.activeToast?.style, .error)
        XCTAssertEqual(store.presentation.activeToast?.title, "Unable to open project")
    }

    func testLoadProjectsKeepsDegradedRuntimeHealthVisible() async {
        let project = sampleProject(id: "project-1")
        let service = MockRuntimeService(
            projects: [project],
            projectDetails: [project.id: ProjectDetail(project: project, latestSession: nil)]
        )
        service.healthCheckResult = RuntimeHealth(
            status: "degraded",
            version: "0.2.0",
            subsystems: [
                RuntimeSubsystemHealth(name: "process", status: "ok", detail: "Runtime process is alive."),
                RuntimeSubsystemHealth(name: "sessionPipeline", status: "degraded", detail: "Session storage unavailable."),
                RuntimeSubsystemHealth(name: "improvementQueue", status: "ok", detail: "Proposal state is readable.")
            ]
        )
        let store = AppRuntimeStore(runtimeService: service)

        await store.loadProjects(select: project.id)

        XCTAssertEqual(store.runtimeHealth?.status, "degraded")
        XCTAssertEqual(store.runtimeHealth?.hasDegradedSubsystems, true)
    }

    func testStartSessionRefreshesSelectedProject() async {
        let project = sampleProject(id: "project-1", sessionCount: 0)
        let refreshedProject = sampleProject(id: "project-1", sessionCount: 1)
        let initialDetail = ProjectDetail(project: project, latestSession: nil)
        let refreshedSession = sampleSession(projectID: project.id)
        let refreshedDetail = ProjectDetail(project: refreshedProject, latestSession: refreshedSession)

        let service = MockRuntimeService(
            projects: [refreshedProject],
            projectDetails: [
                project.id: initialDetail,
                "reloaded-\(project.id)": refreshedDetail
            ]
        )
        service.projectDetailResolver = { id in
            service.getProjectCalls += 1
            if service.getProjectCalls == 1 {
                return initialDetail
            }
            return refreshedDetail
        }

        let store = AppRuntimeStore(runtimeService: service)
        await store.selectProject(id: project.id)
        await store.startSession()

        XCTAssertEqual(service.startSessionCalls, 1)
        XCTAssertEqual(store.selectedProjectDetail?.latestSession, refreshedSession)
        XCTAssertEqual(store.selectedProjectDetail?.project.sessionCount, 1)
    }

    func testRemoveProjectReloadsFallbackSelection() async {
        let firstProject = sampleProject(id: "project-1", name: "First Project")
        let secondProject = sampleProject(id: "project-2", name: "Second Project")
        let secondDetail = ProjectDetail(project: secondProject, latestSession: nil)
        let service = MockRuntimeService(
            projects: [firstProject, secondProject],
            projectDetails: [
                firstProject.id: ProjectDetail(project: firstProject, latestSession: nil),
                secondProject.id: secondDetail,
            ]
        )
        service.removeProjectHandler = { id in
            XCTAssertEqual(id, firstProject.id)
            service.projects = [secondProject]
            service.projectDetails[firstProject.id] = nil
        }

        let store = AppRuntimeStore(runtimeService: service)
        await store.selectProject(id: firstProject.id)
        await store.removeProject(id: firstProject.id)

        XCTAssertEqual(store.projects, [secondProject])
        XCTAssertEqual(store.selectedProjectDetail?.project.id, secondProject.id)
    }

    func testResolveProposalApproveRefreshesProjectDetail() async {
        let project = sampleProject(id: "project-1")
        let proposal = FrameworkProposal(
            id: "proposal-1",
            title: "Tighten rules",
            summary: "Update framework defaults.",
            filePath: ".agentappflow/rules/default.md",
            createdAt: Date(timeIntervalSince1970: 1_743_466_800),
            status: .pending,
            changeSummary: ["Adjust default rules"]
        )
        let initialDetail = ProjectDetail(project: project, latestSession: nil, proposals: [proposal])
        let approvedDetail = ProjectDetail(project: project, latestSession: nil, proposals: [FrameworkProposal(
            id: proposal.id,
            title: proposal.title,
            summary: proposal.summary,
            filePath: proposal.filePath,
            createdAt: proposal.createdAt,
            status: .approved,
            changeSummary: proposal.changeSummary
        )])
        let service = MockRuntimeService(
            projects: [project],
            projectDetails: [project.id: initialDetail]
        )
        service.resolveProposalHandler = { projectID, proposalID, approve in
            XCTAssertEqual(projectID, project.id)
            XCTAssertEqual(proposalID, proposal.id)
            XCTAssertTrue(approve)
            return approvedDetail
        }
        let store = AppRuntimeStore(runtimeService: service)

        await store.selectProject(id: project.id)
        await store.resolveProposal(proposal.id, approve: true)

        XCTAssertEqual(store.selectedProjectDetail?.pendingProposals.count, 0)
        XCTAssertEqual(store.presentation.activeToast?.title, "Proposal approved")
    }

    func testResolveProposalRejectRefreshesProjectDetail() async {
        let project = sampleProject(id: "project-1")
        let proposal = FrameworkProposal(
            id: "proposal-1",
            title: "Tighten rules",
            summary: "Update framework defaults.",
            filePath: ".agentappflow/rules/default.md",
            createdAt: Date(timeIntervalSince1970: 1_743_466_800),
            status: .pending,
            changeSummary: ["Adjust default rules"]
        )
        let initialDetail = ProjectDetail(project: project, latestSession: nil, proposals: [proposal])
        let rejectedDetail = ProjectDetail(project: project, latestSession: nil, proposals: [FrameworkProposal(
            id: proposal.id,
            title: proposal.title,
            summary: proposal.summary,
            filePath: proposal.filePath,
            createdAt: proposal.createdAt,
            status: .rejected,
            changeSummary: proposal.changeSummary
        )])
        let service = MockRuntimeService(
            projects: [project],
            projectDetails: [project.id: initialDetail]
        )
        service.resolveProposalHandler = { projectID, proposalID, approve in
            XCTAssertEqual(projectID, project.id)
            XCTAssertEqual(proposalID, proposal.id)
            XCTAssertFalse(approve)
            return rejectedDetail
        }
        let store = AppRuntimeStore(runtimeService: service)

        await store.selectProject(id: project.id)
        await store.resolveProposal(proposal.id, approve: false)

        XCTAssertEqual(store.selectedProjectDetail?.pendingProposals.count, 0)
        XCTAssertEqual(store.presentation.activeToast?.title, "Proposal rejected")
    }

    func testUpdateSelectedProjectSettingsRefreshesProjectDetail() async {
        let project = sampleProject(id: "project-1")
        let initialDetail = ProjectDetail(project: project, latestSession: nil)
        let updatedDetail = ProjectDetail(
            project: RegisteredProject(
                id: project.id,
                projectName: project.projectName,
                projectDescription: project.projectDescription,
                projectPath: project.projectPath,
                projectType: project.projectType,
                platforms: project.platforms,
                agentTools: project.agentTools,
                approvalMode: .auto,
                improvementMode: .auto,
                createdItems: project.createdItems,
                skippedItems: project.skippedItems,
                registeredAt: project.registeredAt,
                updatedAt: project.updatedAt,
                lastBootstrappedAt: project.lastBootstrappedAt,
                latestSessionStartedAt: project.latestSessionStartedAt,
                sessionCount: project.sessionCount
            ),
            latestSession: nil,
            settings: ProjectSettingsSnapshot(
                approvalMode: .auto,
                memoryMode: .continuous,
                improvementMode: .auto
            )
        )

        let service = MockRuntimeService(
            projects: [project],
            projectDetails: [project.id: initialDetail]
        )
        service.updateProjectSettingsHandler = { id, _ in
            XCTAssertEqual(id, project.id)
            return updatedDetail
        }

        let store = AppRuntimeStore(runtimeService: service)
        await store.selectProject(id: project.id)
        await store.updateSelectedProjectSettings(
            ProjectSettingsSnapshot(
                approvalMode: .auto,
                memoryMode: .continuous,
                improvementMode: .auto
            )
        )

        XCTAssertEqual(store.selectedProjectDetail?.settings.memoryMode, .continuous)
        XCTAssertEqual(store.selectedProjectDetail?.project.approvalMode, .auto)
    }

    func testStubRegistrationStartsWithZeroSessions() async throws {
        let suiteName = "\(Self.self).stubRegistration"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let runtimeService = StubAgentRuntimeService(defaults: defaults, storageKey: "stub-state")

        let repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: repositoryURL.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: repositoryURL.deletingLastPathComponent()) }

        let request = BootstrapRequest(
            projectName: "Fresh Repo",
            projectDescription: "Brand-new stubbed registration.",
            projectPath: repositoryURL.path,
            projectType: .macOSApp,
            platforms: [.macos],
            agentTools: [.codex],
            approvalMode: .observe,
            improvementMode: .propose
        )
        let bootstrapResult = BootstrapCommandResult(
            ok: true,
            message: "ok",
            created: ["AGENTS.md", ".agentappflow/project.yaml"],
            skipped: []
        )

        let project = try await runtimeService.registerProject(request: request, bootstrapResult: bootstrapResult)
        let detail = try await runtimeService.getProject(id: project.id)

        XCTAssertEqual(detail.sessions.count, 0)
        XCTAssertNil(detail.latestSession)
        XCTAssertNil(detail.activeSession)
        XCTAssertEqual(detail.project.sessionCount, 0)
    }

    private func sampleProject(
        id: String,
        name: String = "LegalPocketAI",
        sessionCount: Int = 1
    ) -> RegisteredProject {
        RegisteredProject(
            id: id,
            projectName: name,
            projectDescription: "AI legal assistant for contract review.",
            projectPath: "/tmp/LegalPocketAI",
            projectType: .iosApp,
            platforms: [.ios, .macos],
            agentTools: [.codex, .claudeCode],
            approvalMode: .propose,
            improvementMode: .propose,
            createdItems: ["AGENTS.md", ".agentappflow/project.yaml"],
            skippedItems: [],
            registeredAt: Date(timeIntervalSince1970: 1_743_466_800),
            updatedAt: Date(timeIntervalSince1970: 1_743_466_800),
            lastBootstrappedAt: Date(timeIntervalSince1970: 1_743_466_800),
            sessionCount: sessionCount
        )
    }

    private func sampleSession(projectID: String) -> SessionRecord {
        SessionRecord(
            id: "session-1",
            projectID: projectID,
            title: "LegalPocketAI Session",
            status: "running",
            createdAt: Date(timeIntervalSince1970: 1_743_466_800),
            startedAt: Date(timeIntervalSince1970: 1_743_466_800)
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = #file
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func runtimeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = RuntimeDateCoding.dateDecodingStrategy
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

@MainActor
private final class MockRuntimeService: AgentRuntimeServing {
    var projects: [RegisteredProject]
    var projectDetails: [String: ProjectDetail]
    var projectDetailResolver: ((String) -> ProjectDetail)?
    var healthCheckError: Error?
    var healthCheckResult = RuntimeHealth(
        status: "ok",
        version: "0.2.0",
        subsystems: [
            RuntimeSubsystemHealth(name: "process", status: "ok", detail: "Runtime process is alive."),
            RuntimeSubsystemHealth(name: "sessionPipeline", status: "ok", detail: "Session storage is writable."),
            RuntimeSubsystemHealth(name: "improvementQueue", status: "ok", detail: "Proposal state is readable.")
        ]
    )
    var getProjectError: Error?
    var removeProjectHandler: ((String) -> Void)?
    var resolveProposalHandler: ((String, String, Bool) -> ProjectDetail)?
    var updateProjectSettingsHandler: ((String, ProjectSettingsSnapshot) -> ProjectDetail)?

    var listProjectsCalls = 0
    var getProjectCalls = 0
    var startSessionCalls = 0

    init(projects: [RegisteredProject], projectDetails: [String: ProjectDetail]) {
        self.projects = projects
        self.projectDetails = projectDetails
    }

    func healthCheck() async throws -> RuntimeHealth {
        if let healthCheckError {
            throw healthCheckError
        }
        return healthCheckResult
    }

    func bootstrap(request: BootstrapRequest, force: Bool) async throws -> BootstrapCommandResult {
        return BootstrapCommandResult(ok: true, message: "ok", created: [], skipped: [])
    }

    func registerProject(
        request: BootstrapRequest,
        bootstrapResult: BootstrapCommandResult
    ) async throws -> RegisteredProject {
        return projects[0]
    }

    func listProjects() async throws -> [RegisteredProject] {
        listProjectsCalls += 1
        return projects
    }

    func getProject(id: String) async throws -> ProjectDetail {
        if let getProjectError {
            throw getProjectError
        }
        if let projectDetailResolver {
            return projectDetailResolver(id)
        }
        getProjectCalls += 1
        return projectDetails[id]!
    }

    func startSession(projectID: String, title: String?) async throws -> SessionRecord {
        startSessionCalls += 1
        return SessionRecord(
            id: "session-1",
            projectID: projectID,
            title: title ?? "LegalPocketAI Session",
            status: "running",
            createdAt: Date(timeIntervalSince1970: 1_743_466_800),
            startedAt: Date(timeIntervalSince1970: 1_743_466_800)
        )
    }

    func removeProject(id: String) async throws {
        removeProjectHandler?(id)
        projects.removeAll { $0.id == id }
        projectDetails[id] = nil
    }

    func resolveProposal(projectID: String, proposalID: String, approve: Bool) async throws -> ProjectDetail {
        if let resolveProposalHandler {
            return resolveProposalHandler(projectID, proposalID, approve)
        }
        return projectDetails[projectID]!
    }

    func updateProjectSettings(id: String, settings: ProjectSettingsSnapshot) async throws -> ProjectDetail {
        if let updateProjectSettingsHandler {
            return updateProjectSettingsHandler(id, settings)
        }
        return projectDetails[id]!
    }
}

private enum MockRuntimeError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            message
        }
    }
}
