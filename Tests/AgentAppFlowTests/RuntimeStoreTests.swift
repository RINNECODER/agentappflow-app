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
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let projects = try decoder.decode(ProjectListPayload.self, from: Data(payload.utf8)).projects

        XCTAssertEqual(projects.first?.projectName, "LegalPocketAI")
        XCTAssertEqual(projects.first?.platforms, [.ios, .macos])
        XCTAssertEqual(projects.first?.agentTools, [.codex, .claudeCode])
        XCTAssertEqual(projects.first?.sessionCount, 1)
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
        XCTAssertEqual(store.errorMessage, "runtime unavailable")
        XCTAssertEqual(defaults.string(forKey: "selectedRegisteredProjectID"), project.id)
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
}

@MainActor
private final class MockRuntimeService: AgentRuntimeServing {
    var projects: [RegisteredProject]
    var projectDetails: [String: ProjectDetail]
    var projectDetailResolver: ((String) -> ProjectDetail)?
    var healthCheckError: Error?

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
        return RuntimeHealth(status: "ok", version: "0.2.0")
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
