import XCTest
@testable import AgentAppFlow

final class WorkspaceSnapshotTests: XCTestCase {
    func testSnapshotRoundTripPreservesWorkspaceState() {
        let snapshot = WorkspaceSnapshot(
            projectName: "LegalPocketAI",
            projectPath: "/tmp/LegalPocketAI",
            projectType: .iosApp,
            platforms: [.ios, .macos],
            agentTools: [.claudeCode, .codex],
            approvalMode: .propose,
            improvementMode: .observe,
            createdItems: ["AGENTS.md", ".agentappflow/project.yaml"],
            skippedItems: [],
            initializedAt: Date(timeIntervalSince1970: 1_743_466_800)
        )

        let encoded = snapshot.encoded()
        let decoded = encoded.flatMap(WorkspaceSnapshot.decode(from:))

        XCTAssertEqual(decoded, snapshot)
    }

    func testAppearanceModeResolvesExpectedColorScheme() {
        XCTAssertNil(AppearanceMode.system.colorScheme)
        XCTAssertEqual(AppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(AppearanceMode.dark.colorScheme, .dark)
    }
}
