import Foundation

enum PythonRuntimeLocator {
    private static let embeddedFrameworkName = "Python3.framework"
    private static let embeddedExecutableNames = ["python3", "python3.12", "python3.11", "python3.10", "python3.9"]
    private static let embeddedFrameworkBinaryNames = ["Python3", "Python"]
    private static let hostPythonExecutableURL = URL(fileURLWithPath: "/usr/bin/env")

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
}
