import XCTest
@testable import AgentAppFlow

final class PythonRuntimeLocatorTests: XCTestCase {
    func testInterpreterURLPrefersBundledFramework() throws {
        let bundleURL = try makeFakeBundle(includeBootstrapScript: true, includeEmbeddedPython: true)
        let bundle = try XCTUnwrap(Bundle(path: bundleURL.path))

        let interpreterURL = try PythonRuntimeLocator.interpreterURL(bundle: bundle)
        let environment = PythonRuntimeLocator.launchEnvironment(bundle: bundle)

        XCTAssertEqual(interpreterURL.lastPathComponent, "python3")
        XCTAssertTrue(interpreterURL.path.contains("/Contents/Frameworks/Python3.framework/Versions/Current/bin/"))
        XCTAssertEqual(environment["PYTHONHOME"], interpreterURL.deletingLastPathComponent().deletingLastPathComponent().path)
    }

    func testInterpreterURLAcceptsVersionedEmbeddedExecutableName() throws {
        let bundleURL = try makeFakeBundle(
            includeBootstrapScript: true,
            includeEmbeddedPython: true,
            executableName: "python3.9"
        )
        let bundle = try XCTUnwrap(Bundle(path: bundleURL.path))

        XCTAssertEqual(
            try PythonRuntimeLocator.interpreterURL(bundle: bundle).lastPathComponent,
            "python3.9"
        )
    }

    func testInterpreterURLFallsBackToHostPythonWhenBundledScriptExistsWithoutEmbeddedPython() throws {
        let bundleURL = try makeFakeBundle(includeBootstrapScript: true, includeEmbeddedPython: false)
        let bundle = try XCTUnwrap(Bundle(path: bundleURL.path))

        XCTAssertEqual(try PythonRuntimeLocator.interpreterURL(bundle: bundle).path, "/usr/bin/env")
        XCTAssertEqual(
            try PythonRuntimeLocator.launchArguments(
                scriptURL: bundleURL.appendingPathComponent("Contents/Resources/agentappflow_bootstrap.py"),
                command: "serve",
                additionalArguments: ["--socket", "/tmp/test.sock"],
                bundle: bundle
            ),
            ["python3", bundleURL.appendingPathComponent("Contents/Resources/agentappflow_bootstrap.py").path, "serve", "--socket", "/tmp/test.sock"]
        )
    }

    func testInterpreterURLFallsBackToHostPythonOutsideAppBundle() throws {
        let bundleURL = try makeFakeBundle(includeBootstrapScript: false, includeEmbeddedPython: false)
        let bundle = try XCTUnwrap(Bundle(path: bundleURL.path))

        XCTAssertEqual(try PythonRuntimeLocator.interpreterURL(bundle: bundle).path, "/usr/bin/env")
        XCTAssertNil(PythonRuntimeLocator.launchEnvironment(bundle: bundle)["PYTHONHOME"])
    }

    func testLaunchEnvironmentIncludesRuntimeOverrideWhenProvided() throws {
        let frameworkPath = try makeFakeFramework(executableName: "python3", pythonVersionOutput: "Python 3.11.8")

        let environment = PythonRuntimeLocator.launchEnvironment(runtimeOverridePath: frameworkPath.path)

        XCTAssertEqual(environment["AGENTAPPFLOW_PYTHON_FRAMEWORK_PATH"], frameworkPath.path)
        XCTAssertEqual(
            environment["PYTHONHOME"],
            frameworkPath.appendingPathComponent("Versions/Current").path
        )
        XCTAssertNil(environment["PYTHONPATH"])
    }

    func testLaunchEnvironmentOmitsRuntimeOverrideWhenBlank() {
        let environment = PythonRuntimeLocator.launchEnvironment(runtimeOverridePath: "   ")

        XCTAssertNil(environment["AGENTAPPFLOW_PYTHON_FRAMEWORK_PATH"])
    }

    func testInspectUsesRuntimeOverrideFramework() throws {
        let frameworkPath = try makeFakeFramework(executableName: "python3", pythonVersionOutput: "Python 3.11.8")
        let executableURL = frameworkPath.appendingPathComponent("Versions/Current/bin/python3")

        let inspection = PythonRuntimeLocator.inspect(runtimeOverridePath: frameworkPath.path)

        XCTAssertEqual(inspection.interpreterPath, executableURL.path)
        XCTAssertEqual(inspection.version, "Python 3.11.8")
        XCTAssertEqual(inspection.status, .found)
        XCTAssertEqual(inspection.source, .embedded)
    }

    func testInvalidRuntimeOverrideFallsBackToEmbeddedFramework() throws {
        let bundleURL = try makeFakeBundle(
            includeBootstrapScript: true,
            includeEmbeddedPython: true,
            pythonVersionOutput: "Python 3.11.8"
        )
        let bundle = try XCTUnwrap(Bundle(path: bundleURL.path))

        let inspection = PythonRuntimeLocator.inspect(
            runtimeOverridePath: "/tmp/not-a-framework",
            bundle: bundle
        )
        let environment = PythonRuntimeLocator.hostLaunchEnvironment(
            runtimeOverridePath: "/tmp/not-a-framework",
            bundle: bundle
        )

        XCTAssertEqual(inspection.status, .found)
        XCTAssertEqual(inspection.source, .embedded)
        XCTAssertEqual(inspection.overridePath, "/tmp/not-a-framework")
        XCTAssertNil(environment["AGENTAPPFLOW_PYTHON_FRAMEWORK_PATH"])
        XCTAssertNil(environment["PYTHONHOME"])
    }

    private func makeFakeBundle(
        includeBootstrapScript: Bool,
        includeEmbeddedPython: Bool,
        executableName: String = "python3",
        pythonVersionOutput: String? = nil
    ) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("app")
        let contentsURL = rootURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let frameworksURL = contentsURL.appendingPathComponent("Frameworks", isDirectory: true)

        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: frameworksURL, withIntermediateDirectories: true)

        if includeBootstrapScript {
            try Data().write(to: resourcesURL.appendingPathComponent("agentappflow_bootstrap.py"))
        }

        if includeEmbeddedPython {
            _ = try makeFakeFramework(
                at: frameworksURL,
                executableName: executableName,
                pythonVersionOutput: pythonVersionOutput
            )
        }

        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        return rootURL
    }

    private func makeFakeFramework(
        executableName: String,
        pythonVersionOutput: String? = nil
    ) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Python3.framework", isDirectory: true)
        let frameworkURL = try makeFakeFramework(
            at: rootURL.deletingLastPathComponent(),
            executableName: executableName,
            pythonVersionOutput: pythonVersionOutput
        )

        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL.deletingLastPathComponent())
        }

        return frameworkURL
    }

    @discardableResult
    private func makeFakeFramework(
        at parentURL: URL,
        executableName: String,
        pythonVersionOutput: String? = nil
    ) throws -> URL {
        let frameworkURL = parentURL.appendingPathComponent("Python3.framework", isDirectory: true)
        let versionDirectory = frameworkURL
            .appendingPathComponent("Versions/Current", isDirectory: true)
        let interpreterURL: URL
        if executableName == "python3" {
            interpreterURL = versionDirectory
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("python3")
        } else {
            interpreterURL = versionDirectory
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent(executableName)
        }
        try FileManager.default.createDirectory(
            at: interpreterURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let contents: Data
        if let pythonVersionOutput {
            contents = Data("#!/bin/sh\necho '\(pythonVersionOutput)'\n".utf8)
        } else {
            contents = Data()
        }
        FileManager.default.createFile(atPath: interpreterURL.path, contents: contents)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: interpreterURL.path
        )
        return frameworkURL
    }
}
