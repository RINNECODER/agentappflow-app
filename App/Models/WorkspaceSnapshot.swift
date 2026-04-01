import Foundation
import SwiftUI

enum AppearanceMode: String, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

struct WorkspaceSnapshot: Codable, Equatable {
    let projectName: String
    let projectPath: String
    let projectType: ProjectType
    let platforms: [PlatformChoice]
    let agentTools: [AgentToolChoice]
    let approvalMode: ApprovalMode
    let improvementMode: ImprovementMode
    let createdItems: [String]
    let skippedItems: [String]
    let initializedAt: Date

    static func from(request: BootstrapRequest, result: BootstrapCommandResult) -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            projectName: request.projectName,
            projectPath: request.projectPath,
            projectType: request.projectType,
            platforms: request.platforms,
            agentTools: request.agentTools,
            approvalMode: request.approvalMode,
            improvementMode: request.improvementMode,
            createdItems: result.created,
            skippedItems: result.skipped,
            initializedAt: .now
        )
    }

    func encoded() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func decode(from rawValue: String) -> WorkspaceSnapshot? {
        guard let data = rawValue.data(using: .utf8) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WorkspaceSnapshot.self, from: data)
    }
}
