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
    let overridePath: String?

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
            return overridePath == nil
                ? "Inspecting the embedded framework and host python3 availability."
                : "Inspecting the configured Python framework override before falling back to embedded and host runtimes."
        case .found:
            let versionLabel = version ?? "version unavailable"
            let sourceLabel: String = switch source {
            case .embedded: overridePath == nil ? "embedded framework" : "configured framework override"
            case .host: "host python3"
            case .unavailable: "runtime"
            }
            return "Using \(sourceLabel) at \(interpreterPath ?? "unknown path") • \(versionLabel)"
        case .missing:
            return overridePath == nil
                ? "Install Xcode Command Line Tools or bundle Python3.framework so AgentAppFlow can run the local bootstrap flow."
                : "The configured Python framework override could not provide a usable Python runtime. Update the override path or bundle Python3.framework."
        case .unsupportedVersion:
            return overridePath == nil
                ? "Python 3.10 or newer is required. Update your host python3 or point the app at a newer embedded framework."
                : "The configured Python framework override is too old. Point AgentAppFlow at Python 3.10 or newer."
        }
    }

    static let checking = PythonRuntimeInspection(
        status: .checking,
        source: .unavailable,
        interpreterPath: nil,
        version: nil,
        overridePath: nil
    )
}

enum PythonRuntimeLocator {
    private static let embeddedFrameworkName = "Python3.framework"
    private static let pythonFrameworkOverrideEnvKey = "AGENTAPPFLOW_PYTHON_FRAMEWORK_PATH"
    private static let embeddedExecutableNames = ["python3", "python3.12", "python3.11", "python3.10", "python3.9"]
    private static let embeddedFrameworkBinaryNames = ["Python3", "Python"]
    private static let hostPythonExecutableURL = URL(fileURLWithPath: "/usr/bin/env")
    private static let minimumSupportedVersion = (major: 3, minor: 10)

    static func interpreterURL(
        runtimeOverridePath: String? = nil,
        bundle: Bundle = .main
    ) throws -> URL {
        if let overrideInterpreter = runtimeOverrideInterpreterURL(runtimeOverridePath: runtimeOverridePath) {
            return overrideInterpreter
        }

        if let embeddedInterpreter = embeddedInterpreterURL(bundle: bundle) {
            return embeddedInterpreter
        }
        return hostPythonExecutableURL
    }

    static func launchArguments(
        scriptURL: URL,
        command: String,
        additionalArguments: [String],
        runtimeOverridePath: String? = nil,
        bundle: Bundle = .main
    ) throws -> [String] {
        if runtimeOverrideInterpreterURL(runtimeOverridePath: runtimeOverridePath) != nil
            || embeddedInterpreterURL(bundle: bundle) != nil {
            return directLaunchArguments(
                scriptURL: scriptURL,
                command: command,
                additionalArguments: additionalArguments
            )
        }

        return ["python3", scriptURL.path, command] + additionalArguments
    }

    static func directLaunchArguments(
        scriptURL: URL,
        command: String,
        additionalArguments: [String]
    ) -> [String] {
        [scriptURL.path, command] + additionalArguments
    }

    static func launchEnvironment(bundle: Bundle = .main) -> [String: String] {
        launchEnvironment(bundle: bundle, useEmbeddedPythonHome: true)
    }

    static func launchEnvironment(
        runtimeOverridePath: String?,
        bundle: Bundle = .main
    ) -> [String: String] {
        launchEnvironment(runtimeOverridePath: runtimeOverridePath, bundle: bundle, useEmbeddedPythonHome: true)
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

    static func hostLaunchEnvironment(
        runtimeOverridePath: String?,
        bundle: Bundle = .main
    ) -> [String: String] {
        launchEnvironment(runtimeOverridePath: nil, bundle: bundle, useEmbeddedPythonHome: false)
    }

    static func inspect(
        runtimeOverridePath: String? = nil,
        bundle: Bundle = .main
    ) -> PythonRuntimeInspection {
        let trimmedOverride = runtimeOverridePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedOverride, !trimmedOverride.isEmpty {
            let overrideInspection = inspectRuntimeOverride(trimmedOverride)
            if overrideInspection.status == .found {
                return overrideInspection
            }

            let fallbackInspection = inspectFallbackRuntime(bundle: bundle, overridePath: trimmedOverride)
            if fallbackInspection.status == .found {
                return fallbackInspection
            }

            return overrideInspection
        }

        return inspectFallbackRuntime(bundle: bundle)
    }

    static func runtimeOverrideInterpreterURL(runtimeOverridePath: String?) -> URL? {
        let trimmedOverride = runtimeOverridePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedOverride, !trimmedOverride.isEmpty else {
            return nil
        }

        let inspection = inspectRuntimeOverride(trimmedOverride)
        guard inspection.status == .found, let interpreterPath = inspection.interpreterPath else {
            return nil
        }

        return URL(fileURLWithPath: interpreterPath)
    }

    private static func inspectFallbackRuntime(
        bundle: Bundle,
        overridePath: String? = nil
    ) -> PythonRuntimeInspection {
        if let embeddedInterpreter = embeddedInterpreterURL(bundle: bundle) {
            let version = pythonVersion(executableURL: embeddedInterpreter, arguments: ["--version"])
            return makeInspection(
                source: .embedded,
                interpreterPath: embeddedInterpreter.path,
                version: version,
                overridePath: overridePath
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
                version: nil,
                overridePath: overridePath
            )
        }

        return makeInspection(
            source: .host,
            interpreterPath: hostInterpreterURL().path + " python3",
            version: version,
            overridePath: overridePath
        )
    }

    private static func launchEnvironment(
        runtimeOverridePath: String? = nil,
        bundle: Bundle,
        useEmbeddedPythonHome: Bool
    ) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONNOUSERSITE"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["PYTHONUNBUFFERED"] = "1"
        environment.removeValue(forKey: "PYTHONPATH")
        environment.removeValue(forKey: "PYTHONSTARTUP")
        environment.removeValue(forKey: "PYTHONEXECUTABLE")

        let overrideInterpreter = runtimeOverrideInterpreterURL(runtimeOverridePath: runtimeOverridePath)
        if let overrideInterpreter,
           let overrideFrameworkURL = runtimeOverrideFrameworkURL(runtimeOverridePath) {
            environment[pythonFrameworkOverrideEnvKey] = overrideFrameworkURL.path
        } else {
            environment.removeValue(forKey: pythonFrameworkOverrideEnvKey)
        }

        if useEmbeddedPythonHome, let overrideInterpreter {
            environment["PYTHONHOME"] = pythonHomeURL(for: overrideInterpreter).path
        } else if useEmbeddedPythonHome, let pythonHome = embeddedPythonHomeURL(bundle: bundle) {
            environment["PYTHONHOME"] = pythonHome.path
        } else {
            environment.removeValue(forKey: "PYTHONHOME")
        }

        return environment
    }

    private static func inspectRuntimeOverride(_ frameworkPath: String) -> PythonRuntimeInspection {
        guard let frameworkURL = runtimeOverrideFrameworkURL(frameworkPath) else {
            return PythonRuntimeInspection(
                status: .missing,
                source: .unavailable,
                interpreterPath: frameworkPath,
                version: nil,
                overridePath: frameworkPath
            )
        }
        let currentVersionBinDirectory = frameworkURL.appendingPathComponent("Versions/Current/bin", isDirectory: true)

        let interpreterURL = executableInBinDirectory(currentVersionBinDirectory)
            ?? frameworkBinaryInVersionDirectory(frameworkURL.appendingPathComponent("Versions/Current", isDirectory: true))
            ?? frameworkBinaryInVersionDirectory(frameworkURL)

        guard let interpreterURL else {
            return PythonRuntimeInspection(
                status: .missing,
                source: .unavailable,
                interpreterPath: frameworkURL.path,
                version: nil,
                overridePath: frameworkURL.path
            )
        }

        let version = pythonVersion(executableURL: interpreterURL, arguments: ["--version"])
        return makeInspection(
            source: .embedded,
            interpreterPath: interpreterURL.path,
            version: version,
            overridePath: frameworkURL.path
        )
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

        return pythonHomeURL(for: interpreterURL)
    }

    private static func pythonHomeURL(for interpreterURL: URL) -> URL {
        if interpreterURL.lastPathComponent == "Python3" || interpreterURL.lastPathComponent == "Python" {
            return interpreterURL.deletingLastPathComponent()
        }

        return interpreterURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func runtimeOverrideFrameworkURL(_ runtimeOverridePath: String?) -> URL? {
        let trimmedPath = runtimeOverridePath?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedPath, !trimmedPath.isEmpty else {
            return nil
        }

        let expandedPath = NSString(string: trimmedPath).expandingTildeInPath
        guard expandedPath.hasPrefix("/") else {
            return nil
        }

        let frameworkURL = URL(fileURLWithPath: expandedPath, isDirectory: true).standardizedFileURL
        guard ["Python3.framework", "Python.framework"].contains(frameworkURL.lastPathComponent) else {
            return nil
        }

        let resourceValues = try? frameworkURL.resourceValues(forKeys: [.isDirectoryKey])
        guard resourceValues?.isDirectory == true else {
            return nil
        }

        return frameworkURL
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
        version: String?,
        overridePath: String? = nil
    ) -> PythonRuntimeInspection {
        guard let version else {
            return PythonRuntimeInspection(
                status: .missing,
                source: .unavailable,
                interpreterPath: interpreterPath,
                version: nil,
                overridePath: overridePath
            )
        }

        return PythonRuntimeInspection(
            status: isSupported(version: version) ? .found : .unsupportedVersion,
            source: source,
            interpreterPath: interpreterPath,
            version: version,
            overridePath: overridePath
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
