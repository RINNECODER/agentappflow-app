import Foundation

struct BootstrapCommandResult: Codable, Equatable {
    let ok: Bool
    let message: String
    let created: [String]
    let skipped: [String]
}

enum BootstrapServiceError: LocalizedError {
    case scriptNotFound
    case invalidResponse(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .scriptNotFound:
            "The bundled Python bootstrap script could not be found."
        case .invalidResponse(let response):
            "Bootstrap returned an unreadable response: \(response)"
        case .commandFailed(let message):
            message
        }
    }
}

final class BootstrapCLIService {
    private let pythonFrameworkOverride: String?

    init(pythonFrameworkOverride: String? = nil) {
        self.pythonFrameworkOverride = pythonFrameworkOverride
    }

    func bootstrap(request: BootstrapRequest, force: Bool = false) async throws -> BootstrapCommandResult {
        try await Task.detached(priority: .userInitiated) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let tempFileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("json")

            defer {
                try? FileManager.default.removeItem(at: tempFileURL)
            }

            let scriptURL = try Self.bootstrapScriptURL()
            let payload = try encoder.encode(request)
            try payload.write(to: tempFileURL)
            let executableURL = try PythonRuntimeLocator.interpreterURL()

            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = executableURL
            process.arguments = try PythonRuntimeLocator.launchArguments(
                scriptURL: scriptURL,
                command: "bootstrap_project",
                additionalArguments: ["--input", tempFileURL.path] + (force ? ["--force"] : [])
            )
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.environment = PythonRuntimeLocator.launchEnvironment(runtimeOverridePath: self.pythonFrameworkOverride)

            try process.run()
            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(decoding: stdoutData, as: UTF8.self)
            let stderr = String(decoding: stderrData, as: UTF8.self)

            if let result = try? JSONDecoder().decode(BootstrapCommandResult.self, from: stdoutData) {
                if process.terminationStatus == 0, result.ok {
                    return result
                }
                throw BootstrapServiceError.commandFailed(result.message)
            }

            if process.terminationStatus == 0 {
                throw BootstrapServiceError.invalidResponse(stdout.isEmpty ? stderr : stdout)
            }

            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                throw BootstrapServiceError.commandFailed(message)
            }
            throw BootstrapServiceError.commandFailed(stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        }.value
    }

    private static func bootstrapScriptURL() throws -> URL {
        if let bundledURL = Bundle.main.url(forResource: "agentappflow_bootstrap", withExtension: "py") {
            return bundledURL
        }

        let localCandidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("python")
            .appendingPathComponent("agentappflow_bootstrap.py")
        if FileManager.default.fileExists(atPath: localCandidate.path) {
            return localCandidate
        }

        throw BootstrapServiceError.scriptNotFound
    }
}
