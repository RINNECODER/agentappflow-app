import Foundation

struct PythonRuntimeInspection: Equatable {
    enum Status: Equatable {
        case checking
        case found
        case missing
        case unsupportedVersion
    }

    enum Source: Equatable {
        case embedded
        case host
        case unavailable
    }

    let status: Status
    let source: Source
    let interpreterPath: String?
    let version: String?

    var canProceed: Bool {
        status == .found
    }

    var title: String {
        switch status {
        case .checking:
            "Checking Python runtime"
        case .found:
            "Python runtime ready"
        case .missing:
            "Python runtime missing"
        case .unsupportedVersion:
            "Python version unsupported"
        }
    }

    var statusCopy: String {
        switch status {
        case .checking:
            "Checking"
        case .found:
            "Found"
        case .missing:
            "Missing"
        case .unsupportedVersion:
            "Wrong version"
        }
    }

    var detail: String {
        switch status {
        case .checking:
            return "Inspecting the embedded framework and host python3 availability."
        case .found:
            let versionLabel = version ?? "version unavailable"
            let sourceLabel: String = switch source {
            case .embedded: "embedded framework"
            case .host: "host python3"
            case .unavailable: "runtime"
            }
            return "Using \(sourceLabel) at \(interpreterPath ?? "unknown path") • \(versionLabel)"
        case .missing:
            return "Install Xcode Command Line Tools or bundle Python3.framework so AgentAppFlow can run the local bootstrap flow."
        case .unsupportedVersion:
            return "Python 3.10 or newer is required. Update your host python3 or point the app at a newer embedded framework."
        }
    }

    static let checking = PythonRuntimeInspection(
        status: .checking,
        source: .unavailable,
        interpreterPath: nil,
        version: nil
    )
}

enum PythonRuntimeLocator {
    private static let embeddedFrameworkName = "Python3.framework"
    private static let embeddedExecutableNames = ["python3", "python3.12", "python3.11", "python3.10", "python3.9"]
    private static let embeddedFrameworkBinaryNames = ["Python3", "Python"]
    private static let hostPythonExecutableURL = URL(fileURLWithPath: "/usr/bin/env")
    private static let minimumSupportedVersion = (major: 3, minor: 10)

    static func interpreterURL(bundle: Bundle = .main) throws -> URL {
        if let embeddedInterpreter = embeddedInterpreterURL(bundle: bundle) {
            return embeddedInterpreter
        }
        return hostPythonExecutableURL
    }

    static func launchArguments(
        scriptURL: URL,
        command: String,
        additionalArguments: [String],
        bundle: Bundle = .main
    ) throws -> [String] {
        if embeddedInterpreterURL(bundle: bundle) != nil {
            return [scriptURL.path, command] + additionalArguments
        }

        return ["python3", scriptURL.path, command] + additionalArguments
    }

    static func launchEnvironment(bundle: Bundle = .main) -> [String: String] {
        launchEnvironment(bundle: bundle, useEmbeddedPythonHome: true)
    }

    static func hostInterpreterURL() -> URL {
        hostPythonExecutableURL
    }

    static func hostLaunchArguments(
        scriptURL: URL,
        command: String,
        additionalArguments: [String]
    ) -> [String] {
        ["python3", scriptURL.path, command] + additionalArguments
    }

    static func hostLaunchEnvironment(bundle: Bundle = .main) -> [String: String] {
        launchEnvironment(bundle: bundle, useEmbeddedPythonHome: false)
    }

    static func inspect(bundle: Bundle = .main) -> PythonRuntimeInspection {
        if let embeddedInterpreter = embeddedInterpreterURL(bundle: bundle) {
            let version = pythonVersion(executableURL: embeddedInterpreter, arguments: ["--version"])
            return makeInspection(
                source: .embedded,
                interpreterPath: embeddedInterpreter.path,
                version: version
            )
        }

        let version = pythonVersion(
            executableURL: hostInterpreterURL(),
            arguments: ["python3", "--version"]
        )
        if version == nil {
            return PythonRuntimeInspection(
                status: .missing,
                source: .unavailable,
                interpreterPath: nil,
                version: nil
            )
        }

        return makeInspection(
            source: .host,
            interpreterPath: hostInterpreterURL().path + " python3",
            version: version
        )
    }

    private static func launchEnvironment(
        bundle: Bundle,
        useEmbeddedPythonHome: Bool
    ) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONNOUSERSITE"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["PYTHONUNBUFFERED"] = "1"

        if useEmbeddedPythonHome, let pythonHome = embeddedPythonHomeURL(bundle: bundle) {
            environment["PYTHONHOME"] = pythonHome.path
        } else {
            environment.removeValue(forKey: "PYTHONHOME")
        }

        return environment
    }

    static func embeddedInterpreterURL(bundle: Bundle = .main) -> URL? {
        if let privateFrameworksURL = bundle.privateFrameworksURL {
            let currentVersionBinDirectory = privateFrameworksURL
                .appendingPathComponent(embeddedFrameworkName, isDirectory: true)
                .appendingPathComponent("Versions/Current/bin", isDirectory: true)

            if let currentVersionExecutable = executableInBinDirectory(currentVersionBinDirectory) {
                return currentVersionExecutable
            }

            let versionsDirectory = privateFrameworksURL
                .appendingPathComponent(embeddedFrameworkName, isDirectory: true)
                .appendingPathComponent("Versions", isDirectory: true)

            if let versionDirectories = try? FileManager.default.contentsOfDirectory(
                at: versionsDirectory,
                includingPropertiesForKeys: nil
            ) {
                for versionDirectory in versionDirectories.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                    if let candidate = executableInBinDirectory(
                        versionDirectory.appendingPathComponent("bin", isDirectory: true)
                    ) {
                        return candidate
                    }

                    if let candidate = frameworkBinaryInVersionDirectory(versionDirectory) {
                        return candidate
                    }
                }
            }

            let currentVersionDirectory = privateFrameworksURL
                .appendingPathComponent(embeddedFrameworkName, isDirectory: true)
                .appendingPathComponent("Versions/Current", isDirectory: true)

            if let currentFrameworkBinary = frameworkBinaryInVersionDirectory(currentVersionDirectory) {
                return currentFrameworkBinary
            }
        }

        return nil
    }

    private static func embeddedPythonHomeURL(bundle: Bundle) -> URL? {
        guard let interpreterURL = embeddedInterpreterURL(bundle: bundle) else {
            return nil
        }

        if interpreterURL.lastPathComponent == "Python3" || interpreterURL.lastPathComponent == "Python" {
            return interpreterURL.deletingLastPathComponent()
        }

        return interpreterURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func executableInBinDirectory(_ binDirectory: URL) -> URL? {
        for executableName in embeddedExecutableNames {
            let candidate = binDirectory.appendingPathComponent(executableName)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    private static func frameworkBinaryInVersionDirectory(_ versionDirectory: URL) -> URL? {
        for executableName in embeddedFrameworkBinaryNames {
            let candidate = versionDirectory.appendingPathComponent(executableName)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    private static func hasBundledBootstrapScript(bundle: Bundle) -> Bool {
        bundle.url(forResource: "agentappflow_bootstrap", withExtension: "py") != nil
    }

    private static func pythonVersion(executableURL: URL, arguments: [String]) -> String? {
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    private static func makeInspection(
        source: PythonRuntimeInspection.Source,
        interpreterPath: String?,
        version: String?
    ) -> PythonRuntimeInspection {
        guard let version else {
            return PythonRuntimeInspection(
                status: .missing,
                source: .unavailable,
                interpreterPath: interpreterPath,
                version: nil
            )
        }

        return PythonRuntimeInspection(
            status: isSupported(version: version) ? .found : .unsupportedVersion,
            source: source,
            interpreterPath: interpreterPath,
            version: version
        )
    }

    private static func isSupported(version: String) -> Bool {
        let digits = version.split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
        guard digits.count >= 2 else {
            return false
        }

        let candidate = (major: digits[0], minor: digits[1])
        if candidate.major != minimumSupportedVersion.major {
            return candidate.major > minimumSupportedVersion.major
        }

        return candidate.minor >= minimumSupportedVersion.minor
    }
}
