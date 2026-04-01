import XCTest
@testable import AgentAppFlow

final class OnboardingFormStateTests: XCTestCase {
    func testMakeRequestBuildsExpectedPayload() throws {
        var formState = OnboardingFormState()
        formState.projectName = "LegalPocketAI"
        formState.projectPath = "/tmp/LegalPocketAI"
        formState.projectType = .iosApp
        formState.selectedPlatforms = [.ios, .macos]
        formState.selectedAgentTools = [.codex, .claudeCode]
        formState.approvalMode = .propose
        formState.improvementMode = .auto

        let request = try formState.makeRequest()

        XCTAssertEqual(request.projectName, "LegalPocketAI")
        XCTAssertEqual(request.projectPath, "/tmp/LegalPocketAI")
        XCTAssertEqual(request.projectType, .iosApp)
        XCTAssertEqual(request.platforms, [.ios, .macos])
        XCTAssertEqual(request.agentTools, [.claudeCode, .codex])
        XCTAssertEqual(request.approvalMode, .propose)
        XCTAssertEqual(request.improvementMode, .auto)
    }

    func testPopulateProjectNameUsesLastPathComponent() {
        var formState = OnboardingFormState()
        formState.projectPath = "/Users/example/Projects/LegalPocketAI"

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

    func testMakeRequestRejectsMissingAgentTools() {
        var formState = OnboardingFormState()
        formState.projectName = "LegalPocketAI"
        formState.projectPath = "/tmp/LegalPocketAI"
        formState.selectedAgentTools = []

        XCTAssertThrowsError(try formState.makeRequest()) { error in
            XCTAssertEqual(error as? OnboardingValidationError, .noAgentToolsSelected)
        }
    }
}
