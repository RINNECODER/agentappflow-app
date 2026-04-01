import Foundation

@MainActor
final class AppRuntimeStore: ObservableObject {
    @Published private(set) var projects: [RegisteredProject] = []
    @Published private(set) var selectedProjectDetail: ProjectDetail?
    @Published private(set) var runtimeHealth: RuntimeHealth?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    let runtimeService: AgentRuntimeServing
    private let defaults: UserDefaults
    private let selectedProjectIDKey: String

    init(
        runtimeService: AgentRuntimeServing = AgentRuntimeService(),
        defaults: UserDefaults = .standard,
        selectedProjectIDKey: String = "selectedRegisteredProjectID"
    ) {
        self.runtimeService = runtimeService
        self.defaults = defaults
        self.selectedProjectIDKey = selectedProjectIDKey
    }

    var selectedProjectID: String? {
        selectedProjectDetail?.project.id
    }

    func loadProjects(select preferredProjectID: String? = nil) async {
        isLoading = true
        defer { isLoading = false }

        let existingSelectedProjectDetail = selectedProjectDetail

        do {
            runtimeHealth = try await runtimeService.healthCheck()
            let projects = try await runtimeService.listProjects()
            self.projects = projects
            errorMessage = nil

            let candidateProjectIDs: [String] = [
                preferredProjectID,
                persistedSelectedProjectID,
                selectedProjectID,
                projects.first?.id,
            ]
            .compactMap { id in
                guard let trimmed = id?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                    return nil
                }
                return trimmed
            }

            guard let nextProjectID = candidateProjectIDs.first(where: { candidateID in
                projects.contains(where: { $0.id == candidateID })
            }) else {
                selectedProjectDetail = nil
                persistSelectedProjectID(nil)
                return
            }

            selectedProjectDetail = try await runtimeService.getProject(id: nextProjectID)
            persistSelectedProjectID(nextProjectID)
        } catch {
            runtimeHealth = nil
            selectedProjectDetail = existingSelectedProjectDetail
            errorMessage = error.localizedDescription
        }
    }

    func selectProject(id: String) async {
        do {
            selectedProjectDetail = try await runtimeService.getProject(id: id)
            persistSelectedProjectID(id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startSession() async {
        guard let projectID = selectedProjectID else { return }

        do {
            _ = try await runtimeService.startSession(projectID: projectID, title: nil)
            await loadProjects(select: projectID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var hasPersistedProjectSelection: Bool {
        persistedSelectedProjectID != nil
    }

    private var persistedSelectedProjectID: String? {
        let trimmed = defaults.string(forKey: selectedProjectIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func persistSelectedProjectID(_ projectID: String?) {
        guard let projectID = projectID?.trimmingCharacters(in: .whitespacesAndNewlines), !projectID.isEmpty else {
            defaults.removeObject(forKey: selectedProjectIDKey)
            return
        }
        defaults.set(projectID, forKey: selectedProjectIDKey)
    }
}
