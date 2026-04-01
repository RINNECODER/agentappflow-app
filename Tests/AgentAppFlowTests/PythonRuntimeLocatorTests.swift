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

    private func makeFakeBundle(
        includeBootstrapScript: Bool,
        includeEmbeddedPython: Bool,
        executableName: String = "python3"
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
            let versionDirectory = frameworksURL
                .appendingPathComponent("Python3.framework/Versions/Current", isDirectory: true)
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
            FileManager.default.createFile(atPath: interpreterURL.path, contents: Data())
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: interpreterURL.path
            )
        }

        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        return rootURL
    }
}
