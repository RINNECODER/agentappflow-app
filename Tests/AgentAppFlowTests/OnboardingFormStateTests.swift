import XCTest
@testable import AgentAppFlow

final class OnboardingFormStateTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    func testMakeRequestBuildsExpectedPayload() throws {
        let repositoryURL = try makeGitRepository(named: "LegalPocketAI")

        var formState = OnboardingFormState()
        formState.projectName = "LegalPocketAI"
        formState.projectDescription = "iOS legal assistant for contract analysis."
        formState.projectPath = repositoryURL.path
        formState.projectType = .iosApp
        formState.selectedPlatforms = [.ios, .macos]
        formState.selectedAgentTools = [.codex, .claudeCode]
        formState.approvalMode = .propose
        formState.improvementMode = .auto

        let request = try formState.makeRequest()

        XCTAssertEqual(request.projectName, "LegalPocketAI")
        XCTAssertEqual(request.projectDescription, "iOS legal assistant for contract analysis.")
        XCTAssertEqual(request.projectPath, repositoryURL.path)
        XCTAssertEqual(request.projectType, .iosApp)
        XCTAssertEqual(request.platforms, [.ios, .macos])
        XCTAssertEqual(request.agentTools, [.claudeCode, .codex])
        XCTAssertEqual(request.approvalMode, .propose)
        XCTAssertEqual(request.improvementMode, .auto)
    }

    func testPopulateProjectNameUsesLastPathComponent() throws {
        let repositoryURL = try makeGitRepository(named: "LegalPocketAI")
        var formState = OnboardingFormState()
        formState.projectPath = repositoryURL.path

        formState.populateProjectNameIfNeeded()

        XCTAssertEqual(formState.projectName, "LegalPocketAI")
    }

    func testMakeRequestRejectsMissingPath() {
        var formState = OnboardingFormState()
        formState.projectName = "LegalPocketAI"

        XCTAssertThrowsError(try formState.makeRequest()) { error in
            XCTAssertEqual(error as? OnboardingValidationError, .missingProjectPath)
        }
    }

    func testMakeRequestRejectsNonGitRepository() throws {
        let directory = try makeDirectory(named: "NotAGitRepo")
        var formState = OnboardingFormState()
        formState.projectName = "LegalPocketAI"
        formState.projectPath = directory.path

        XCTAssertThrowsError(try formState.makeRequest()) { error in
            XCTAssertEqual(error as? OnboardingValidationError, .pathIsNotGitRepository)
        }
    }

    func testMakeRequestRejectsProjectNamesThatAreTooShort() throws {
        let repositoryURL = try makeGitRepository(named: "LegalPocketAI")
        var formState = OnboardingFormState()
        formState.projectName = "LP"
        formState.projectPath = repositoryURL.path

        XCTAssertThrowsError(try formState.makeRequest()) { error in
            XCTAssertEqual(
                error as? OnboardingValidationError,
                .invalidProjectNameLength(minimum: 3, maximum: 40)
            )
        }
    }

    func testMakeRequestRejectsMissingAgentTools() throws {
        let repositoryURL = try makeGitRepository(named: "LegalPocketAI")
        var formState = OnboardingFormState()
        formState.projectName = "LegalPocketAI"
        formState.projectPath = repositoryURL.path
        formState.selectedAgentTools = []

        XCTAssertThrowsError(try formState.makeRequest()) { error in
            XCTAssertEqual(error as? OnboardingValidationError, .noAgentToolsSelected)
        }
    }

    func testValidationSnapshotMarksGitRepositoryAsValid() throws {
        let repositoryURL = try makeGitRepository(named: "LegalPocketAI")
        var formState = OnboardingFormState()
        formState.projectName = "LegalPocketAI"
        formState.projectPath = repositoryURL.path

        let snapshot = formState.validationSnapshot()

        XCTAssertEqual(snapshot.projectPathState, .valid("Git repository detected"))
        XCTAssertEqual(snapshot.projectNameState, .valid("27 characters remaining"))
    }

    private func makeGitRepository(named name: String) throws -> URL {
        let directory = try makeDirectory(named: name)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        return directory
    }

    private func makeDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory.deletingLastPathComponent())
        return directory
    }
}
