import Foundation

enum AppToastStyle: Equatable {
    case success
    case warning
    case error
}

struct AppToastMessage: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let style: AppToastStyle
}

struct ProgressHUDState: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class AppRuntimePresentationState: ObservableObject {
    @Published var errorMessage: String?
    @Published var activeToast: AppToastMessage?
    @Published private(set) var progressHUD: ProgressHUDState?

    private var toastDismissTask: Task<Void, Never>?

    deinit {
        toastDismissTask?.cancel()
    }

    func beginProgress(title: String, message: String) {
        progressHUD = ProgressHUDState(title: title, message: message)
    }

    func endProgress() {
        progressHUD = nil
    }

    func clearError() {
        errorMessage = nil
    }

    func setError(_ message: String) {
        errorMessage = message
    }

    func dismissToast() {
        toastDismissTask?.cancel()
        activeToast = nil
    }

    func presentToast(title: String, message: String, style: AppToastStyle) {
        let toast = AppToastMessage(title: title, message: message, style: style)
        activeToast = toast
        toastDismissTask?.cancel()
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self?.activeToast?.id == toast.id {
                    self?.activeToast = nil
                }
            }
        }
    }
}

struct AppRuntimePreviewState {
    var projects: [RegisteredProject] = []
    var selectedProjectDetail: ProjectDetail? = nil
    var runtimeHealth: RuntimeHealth? = RuntimeHealth(status: "ok", version: "preview")
    var isLoading = false
    var errorMessage: String? = nil
}

@MainActor
final class AppRuntimeStore: ObservableObject {
    static func makeDefaultPresentation() -> AppRuntimePresentationState {
        AppRuntimePresentationState()
    }

    @Published private(set) var projects: [RegisteredProject]
    @Published private(set) var selectedProjectDetail: ProjectDetail?
    @Published private(set) var runtimeHealth: RuntimeHealth?
    @Published private(set) var isLoading: Bool
    @Published var isSidebarCollapsed = false

    let runtimeService: AgentRuntimeServing
    let presentation: AppRuntimePresentationState
    private let defaults: UserDefaults
    private let selectedProjectIDKey: String

    init(
        runtimeService: AgentRuntimeServing = AppRuntimeServiceFactory.makeDefaultService(),
        presentation: AppRuntimePresentationState? = nil,
        defaults: UserDefaults = .standard,
        selectedProjectIDKey: String = "selectedRegisteredProjectID"
    ) {
        self.runtimeService = runtimeService
        self.presentation = presentation ?? Self.makeDefaultPresentation()
        self.defaults = defaults
        self.selectedProjectIDKey = selectedProjectIDKey
        projects = []
        selectedProjectDetail = nil
        runtimeHealth = nil
        isLoading = false
    }

    init(
        previewState: AppRuntimePreviewState,
        runtimeService: AgentRuntimeServing = StubAgentRuntimeService(),
        presentation: AppRuntimePresentationState? = nil,
        defaults: UserDefaults = .standard,
        selectedProjectIDKey: String = "selectedRegisteredProjectID"
    ) {
        let presentation = presentation ?? Self.makeDefaultPresentation()
        self.runtimeService = runtimeService
        self.presentation = presentation
        self.defaults = defaults
        self.selectedProjectIDKey = selectedProjectIDKey
        projects = previewState.projects
        selectedProjectDetail = previewState.selectedProjectDetail
        runtimeHealth = previewState.runtimeHealth
        isLoading = previewState.isLoading
        presentation.errorMessage = previewState.errorMessage
    }

    var selectedProjectID: String? {
        selectedProjectDetail?.project.id
    }

    var capabilities: RuntimeCapabilities {
        runtimeService.capabilities
    }

    func loadProjects(select preferredProjectID: String? = nil) async {
        isLoading = true
        defer { isLoading = false }

        let existingSelectedProjectDetail = selectedProjectDetail

        do {
            runtimeHealth = try await runtimeService.healthCheck()
            let projects = try await runtimeService.listProjects()
            self.projects = projects
            presentation.errorMessage = nil

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

            let detail = try await runtimeService.getProject(id: nextProjectID)
            selectedProjectDetail = detail
            persistSelectedProjectID(nextProjectID)
        } catch {
            runtimeHealth = nil
            selectedProjectDetail = existingSelectedProjectDetail
            presentation.errorMessage = error.localizedDescription
        }
    }

    func selectProject(id: String) async {
        do {
            selectedProjectDetail = try await runtimeService.getProject(id: id)
            persistSelectedProjectID(id)
            presentation.errorMessage = nil
        } catch {
            presentation.errorMessage = error.localizedDescription
            presentation.presentToast(
                title: "Unable to open project",
                message: error.localizedDescription,
                style: .error
            )
        }
    }

    func startSession(title: String? = nil) async {
        guard let projectID = selectedProjectID else { return }

        await withProgress(title: "Starting session", message: "Preparing the next agent run for the selected project.") {
            _ = try await runtimeService.startSession(projectID: projectID, title: title)
            await loadProjects(select: projectID)
            presentation.presentToast(
                title: "Session started",
                message: "The active session banner is now tracking the latest runtime task.",
                style: .success
            )
        }
    }

    func removeProject(id: String) async {
        let nextSelection = projects.first(where: { $0.id != id })?.id

        await withProgress(title: "Removing project", message: "Updating the local runtime index and project list.") {
            try await runtimeService.removeProject(id: id)
            await loadProjects(select: nextSelection)
            presentation.presentToast(
                title: "Project removed",
                message: "The workspace was removed from the local AgentAppFlow index.",
                style: .success
            )
        }
    }

    func rebootstrapSelectedProject() async {
        guard let projectID = selectedProjectID else { return }

        await withProgress(title: "Re-bootstrap in progress", message: "Refreshing framework-owned files and runtime checks.") {
            let detail = try await runtimeService.rebootstrapProject(id: projectID)
            updateDetail(detail)
            presentation.presentToast(
                title: "Bootstrap refreshed",
                message: "Framework health and pending proposals were updated for the selected project.",
                style: .success
            )
        }
    }

    func updateSelectedProjectSettings(_ settings: ProjectSettingsSnapshot) async {
        guard let projectID = selectedProjectID else { return }

        await withProgress(title: "Saving project settings", message: "Persisting approval, memory, and improvement defaults.") {
            let detail = try await runtimeService.updateProjectSettings(id: projectID, settings: settings)
            updateDetail(detail)
            presentation.presentToast(
                title: "Project settings saved",
                message: "The new defaults are active for the selected workspace.",
                style: .success
            )
        }
    }

    func resolveProposal(_ proposalID: String, approve: Bool) async {
        guard let projectID = selectedProjectID else { return }

        await withProgress(
            title: approve ? "Approving proposal" : "Rejecting proposal",
            message: "Updating the framework proposal queue for the selected project."
        ) {
            let detail = try await runtimeService.resolveProposal(projectID: projectID, proposalID: proposalID, approve: approve)
            updateDetail(detail)
            presentation.presentToast(
                title: approve ? "Proposal approved" : "Proposal rejected",
                message: approve
                    ? "The proposal was applied to the project detail state."
                    : "The proposal remains in history with a rejected status.",
                style: approve ? .success : .warning
            )
        }
    }

    func toggleSidebar() {
        isSidebarCollapsed.toggle()
    }

    func dismissToast() {
        presentation.dismissToast()
    }

    var hasPersistedProjectSelection: Bool {
        persistedSelectedProjectID != nil
    }

    private func withProgress(
        title: String,
        message: String,
        operation: () async throws -> Void
    ) async {
        presentation.beginProgress(title: title, message: message)
        defer { presentation.endProgress() }

        do {
            try await operation()
            presentation.clearError()
        } catch {
            presentation.setError(error.localizedDescription)
            presentation.presentToast(title: title, message: error.localizedDescription, style: .error)
        }
    }

    private func updateDetail(_ detail: ProjectDetail) {
        selectedProjectDetail = detail
        persistSelectedProjectID(detail.project.id)
        projects = projects.map { project in
            project.id == detail.project.id ? detail.project : project
        }

        if !projects.contains(where: { $0.id == detail.project.id }) {
            projects.insert(detail.project, at: 0)
        }

        projects.sort { lhs, rhs in
            lhs.lastActivityAt > rhs.lastActivityAt
        }
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
