import Darwin
import Foundation

struct RuntimeCapabilities: Equatable {
    let canStartSessions: Bool
    let canRemoveProjects: Bool
    let canRebootstrapProjects: Bool
    let canUpdateProjectSettings: Bool
    let canResolveProposals: Bool

    static let livePhase2 = RuntimeCapabilities(
        canStartSessions: true,
        canRemoveProjects: false,
        canRebootstrapProjects: false,
        canUpdateProjectSettings: false,
        canResolveProposals: false
    )

    static let fullStub = RuntimeCapabilities(
        canStartSessions: true,
        canRemoveProjects: true,
        canRebootstrapProjects: true,
        canUpdateProjectSettings: true,
        canResolveProposals: true
    )
}

protocol AgentRuntimeServing {
    var capabilities: RuntimeCapabilities { get }
    func healthCheck() async throws -> RuntimeHealth
    func bootstrap(request: BootstrapRequest, force: Bool) async throws -> BootstrapCommandResult
    func registerProject(
        request: BootstrapRequest,
        bootstrapResult: BootstrapCommandResult
    ) async throws -> RegisteredProject
    func listProjects() async throws -> [RegisteredProject]
    func getProject(id: String) async throws -> ProjectDetail
    func startSession(projectID: String, title: String?) async throws -> SessionRecord
    func removeProject(id: String) async throws
    func rebootstrapProject(id: String) async throws -> ProjectDetail
    func updateProjectSettings(id: String, settings: ProjectSettingsSnapshot) async throws -> ProjectDetail
    func resolveProposal(projectID: String, proposalID: String, approve: Bool) async throws -> ProjectDetail
}

extension AgentRuntimeServing {
    var capabilities: RuntimeCapabilities { .livePhase2 }

    func removeProject(id: String) async throws {
        throw AgentRuntimeError.unsupportedOperation("Removing a project is not supported by the current runtime.")
    }

    func rebootstrapProject(id: String) async throws -> ProjectDetail {
        throw AgentRuntimeError.unsupportedOperation("Re-bootstrap is not supported by the current runtime.")
    }

    func updateProjectSettings(id: String, settings: ProjectSettingsSnapshot) async throws -> ProjectDetail {
        throw AgentRuntimeError.unsupportedOperation("Project settings are not supported by the current runtime.")
    }

    func resolveProposal(projectID: String, proposalID: String, approve: Bool) async throws -> ProjectDetail {
        throw AgentRuntimeError.unsupportedOperation("Framework proposals are not supported by the current runtime.")
    }
}

enum AgentRuntimeError: LocalizedError {
    case scriptNotFound
    case runtimeUnavailable(String)
    case invalidResponse(String)
    case socketFailure(String)
    case rpcFailure(Int, String)
    case unsupportedOperation(String)

    var errorDescription: String? {
        switch self {
        case .scriptNotFound:
            "The bundled Python runtime could not be found."
        case .runtimeUnavailable(let message):
            message
        case .invalidResponse(let message):
            "Runtime returned an unreadable response: \(message)"
        case .socketFailure(let message):
            "Failed to communicate with the local runtime: \(message)"
        case .rpcFailure(_, let message):
            message
        case .unsupportedOperation(let message):
            message
        }
    }
}

private struct JSONRPCRequest<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: String
    let method: String
    let params: Params
}

private struct JSONRPCErrorPayload: Decodable {
    let code: Int
    let message: String
}

private struct JSONRPCResponse<Result: Decodable>: Decodable {
    let jsonrpc: String
    let id: String?
    let result: Result?
    let error: JSONRPCErrorPayload?
}

private enum RuntimeJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = RuntimeDateCoding.dateDecodingStrategy
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

private actor AgentRuntimeManager {
    static let shared = AgentRuntimeManager()

    private let pythonFrameworkOverride: String?

    init(pythonFrameworkOverride: String? = nil) {
        self.pythonFrameworkOverride = pythonFrameworkOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct RuntimeLaunchAttempt {
        let name: String
        let executableURL: URL
        let arguments: [String]
        let environment: [String: String]
    }

    private var process: Process?
    private var stderrPipe: Pipe?

    func socketPath() throws -> String {
        let runtimeDirectory = try runtimeSocketDirectoryURL()
        return runtimeDirectory.appendingPathComponent("runtime.sock").path
    }

    func ensureRuntimeRunning() async throws -> String {
        let socketPath = try socketPath()

        if try ping(socketPath: socketPath) {
            return socketPath
        }

        try removeStaleSocket(at: socketPath)

        if process?.isRunning == true {
            stopRuntime()
        }

        return try await launchRuntime(socketPath: socketPath)
    }

    private func runtimeSocketDirectoryURL() throws -> URL {
        guard let cachesDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            throw AgentRuntimeError.runtimeUnavailable("Unable to resolve runtime cache directory.")
        }

        let runtimeDirectory = cachesDirectory
            .appendingPathComponent("AAF", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        return runtimeDirectory
    }

    private func launchRuntime(socketPath: String) async throws -> String {
        let scriptURL = try Self.runtimeScriptURL()
        let attempts = try runtimeLaunchAttempts(scriptURL: scriptURL, socketPath: socketPath)
        var failureMessages: [String] = []

        for attempt in attempts {
            let stderrPipe = Pipe()
            let process = Process()
            process.executableURL = attempt.executableURL
            process.arguments = attempt.arguments
            process.currentDirectoryURL = scriptURL.deletingLastPathComponent()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = stderrPipe
            process.environment = attempt.environment

            do {
                try process.run()
            } catch {
                failureMessages.append("\(attempt.name): \(error.localizedDescription)")
                continue
            }

            self.process = process
            self.stderrPipe = stderrPipe

            if try await waitForRuntimeAvailability(socketPath: socketPath) {
                return socketPath
            }

            let stderr = terminateCurrentRuntimeAndDrainStderr()
            failureMessages.append(
                stderr.isEmpty
                    ? "\(attempt.name): no response from local runtime"
                    : "\(attempt.name): \(stderr)"
            )
            try removeStaleSocket(at: socketPath)
        }

        let joinedFailures = failureMessages.joined(separator: " | ")
        throw AgentRuntimeError.runtimeUnavailable(
            joinedFailures.isEmpty
                ? "The local Python runtime did not become available."
                : "The local Python runtime did not become available. \(joinedFailures)"
        )
    }

    private func runtimeLaunchAttempts(scriptURL: URL, socketPath: String) throws -> [RuntimeLaunchAttempt] {
        let additionalArguments = ["--socket", socketPath]
        var attempts: [RuntimeLaunchAttempt] = []

        if let overrideInterpreter = PythonRuntimeLocator.runtimeOverrideInterpreterURL(runtimeOverridePath: pythonFrameworkOverride) {
            attempts.append(
                RuntimeLaunchAttempt(
                    name: "configured python framework",
                    executableURL: overrideInterpreter,
                    arguments: PythonRuntimeLocator.directLaunchArguments(
                        scriptURL: scriptURL,
                        command: "serve",
                        additionalArguments: additionalArguments
                    ),
                    environment: PythonRuntimeLocator.launchEnvironment(runtimeOverridePath: pythonFrameworkOverride)
                )
            )
        }

        if let embeddedInterpreter = PythonRuntimeLocator.embeddedInterpreterURL() {
            attempts.append(
                RuntimeLaunchAttempt(
                    name: "embedded python",
                    executableURL: embeddedInterpreter,
                    arguments: try PythonRuntimeLocator.launchArguments(
                        scriptURL: scriptURL,
                        command: "serve",
                        additionalArguments: additionalArguments
                    ),
                    environment: PythonRuntimeLocator.launchEnvironment()
                )
            )
        }

        attempts.append(
            RuntimeLaunchAttempt(
                name: "host python3",
                executableURL: PythonRuntimeLocator.hostInterpreterURL(),
                arguments: PythonRuntimeLocator.hostLaunchArguments(
                    scriptURL: scriptURL,
                    command: "serve",
                    additionalArguments: additionalArguments
                ),
                environment: PythonRuntimeLocator.hostLaunchEnvironment(runtimeOverridePath: pythonFrameworkOverride)
            )
        )

        return attempts
    }

    private func waitForRuntimeAvailability(socketPath: String) async throws -> Bool {
        for _ in 0..<100 {
            if try ping(socketPath: socketPath) {
                return true
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private func stopRuntime() {
        process?.terminationHandler = nil
        if let process, process.isRunning {
            terminate(process)
        }
        process = nil
        stderrPipe = nil
    }

    private func terminateCurrentRuntimeAndDrainStderr() -> String {
        process?.terminationHandler = nil
        if let process, process.isRunning {
            terminate(process)
        }

        guard let stderrPipe else {
            process = nil
            return ""
        }
        let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process = nil
        self.stderrPipe = nil
        guard !data.isEmpty else { return "" }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func terminate(_ process: Process) {
        process.terminate()

        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }

        process.waitUntilExit()
    }

    private func removeStaleSocket(at path: String) throws {
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
    }

    private func ping(socketPath: String) throws -> Bool {
        do {
            let request = JSONRPCRequest(
                id: UUID().uuidString,
                method: "health_check",
                params: EmptyRuntimeParams.value
            )
            let data = try RuntimeJSON.encoder.encode(request)
            let responseData = try UNIXDomainSocketClient.send(data: data, to: socketPath)
            let response = try RuntimeJSON.decoder.decode(
                JSONRPCResponse<RuntimeHealth>.self,
                from: responseData
            )
            return response.result?.isResponsive == true
        } catch {
            return false
        }
    }

    private static func runtimeScriptURL() throws -> URL {
        if let bundledURL = Bundle.main.url(forResource: "agentappflow_bootstrap", withExtension: "py") {
            return bundledURL
        }

        let localCandidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("python")
            .appendingPathComponent("agentappflow_bootstrap.py")
        if FileManager.default.fileExists(atPath: localCandidate.path) {
            return localCandidate
        }

        throw AgentRuntimeError.scriptNotFound
    }
}

private enum UNIXDomainSocketClient {
    static func send(data: Data, to path: String) throws -> Data {
        let socketDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw AgentRuntimeError.socketFailure(lastErrnoMessage())
        }
        defer { close(socketDescriptor) }

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)

        let utf8Path = Array(path.utf8)
        guard utf8Path.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw AgentRuntimeError.socketFailure("Socket path is too long.")
        }

        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: CChar.self, repeating: 0)
            for (index, byte) in utf8Path.enumerated() {
                buffer[index] = byte
            }
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(socketDescriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw AgentRuntimeError.socketFailure(lastErrnoMessage())
        }

        try writeAll(data, to: socketDescriptor)
        shutdown(socketDescriptor, SHUT_WR)

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let readCount = read(socketDescriptor, &buffer, buffer.count)
            if readCount == 0 {
                break
            }
            guard readCount > 0 else {
                throw AgentRuntimeError.socketFailure(lastErrnoMessage())
            }
            response.append(buffer, count: readCount)
        }

        return response
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let bytesRemaining = rawBuffer.count - offset
                let result = write(descriptor, baseAddress.advanced(by: offset), bytesRemaining)
                guard result >= 0 else {
                    throw AgentRuntimeError.socketFailure(lastErrnoMessage())
                }
                offset += result
            }
        }
    }

    private static func lastErrnoMessage() -> String {
        String(cString: strerror(errno))
    }
}

final class AgentRuntimeService: AgentRuntimeServing {
    private let runtimeManager: AgentRuntimeManager

    init(pythonFrameworkOverride: String? = nil) {
        runtimeManager = AgentRuntimeManager(pythonFrameworkOverride: pythonFrameworkOverride)
    }

    func healthCheck() async throws -> RuntimeHealth {
        try await sendRequest(method: "health_check", params: EmptyRuntimeParams.value)
    }

    func bootstrap(request: BootstrapRequest, force: Bool = false) async throws -> BootstrapCommandResult {
        try await sendRequest(
            method: "bootstrap_project",
            params: RuntimeBootstrapRequest(request: request, force: force)
        )
    }

    func registerProject(
        request: BootstrapRequest,
        bootstrapResult: BootstrapCommandResult
    ) async throws -> RegisteredProject {
        let payload: RegisteredProjectPayload = try await sendRequest(
            method: "register_project",
            params: RegisterProjectRequest(request: request, bootstrapResult: bootstrapResult)
        )
        return payload.project
    }

    func listProjects() async throws -> [RegisteredProject] {
        let payload: ProjectListPayload = try await sendRequest(
            method: "list_projects",
            params: EmptyRuntimeParams.value
        )
        return payload.projects
    }

    func getProject(id: String) async throws -> ProjectDetail {
        try await sendRequest(method: "get_project", params: ["id": id])
    }

    func startSession(projectID: String, title: String? = nil) async throws -> SessionRecord {
        let payload: SessionRecordPayload = try await sendRequest(
            method: "start_session",
            params: StartSessionRequest(projectID: projectID, title: title)
        )
        return payload.session
    }

    private func sendRequest<Result: Decodable, Params: Encodable>(
        method: String,
        params: Params
    ) async throws -> Result {
        let socketPath = try await runtimeManager.ensureRuntimeRunning()
        let request = JSONRPCRequest(
            id: UUID().uuidString,
            method: method,
            params: params
        )
        let requestData = try RuntimeJSON.encoder.encode(request)
        let responseData = try UNIXDomainSocketClient.send(data: requestData, to: socketPath)

        let response = try RuntimeJSON.decoder.decode(JSONRPCResponse<Result>.self, from: responseData)
        if let error = response.error {
            throw AgentRuntimeError.rpcFailure(error.code, error.message)
        }
        guard let result = response.result else {
            throw AgentRuntimeError.invalidResponse(String(decoding: responseData, as: UTF8.self))
        }
        return result
    }
}
