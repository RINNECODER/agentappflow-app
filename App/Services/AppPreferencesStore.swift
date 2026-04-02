import Foundation

private enum PythonFrameworkOverrideValidator {
    static func fieldState(for rawValue: String) -> AppFieldState {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .normal
        }

        let url = URL(fileURLWithPath: trimmed, isDirectory: true)
        guard url.lastPathComponent == "Python3.framework" || url.lastPathComponent == "Python.framework" else {
            return .warning("Use the framework directory path ending in Python3.framework.")
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDirectory) else {
            return .warning("The override path does not exist on disk yet.")
        }

        guard isDirectory.boolValue else {
            return .error("The override must point to a framework directory, not a file.")
        }

        return .valid("Framework path looks valid")
    }
}

@MainActor
final class AppPreferencesStore: ObservableObject {
    @Published var pythonFrameworkOverride: String {
        didSet {
            defaults.set(pythonFrameworkOverride, forKey: pythonFrameworkOverrideKey)
        }
    }

    @Published var defaultApprovalMode: ApprovalMode {
        didSet {
            defaults.set(defaultApprovalMode.rawValue, forKey: defaultApprovalModeKey)
        }
    }

    var trimmedPythonFrameworkOverride: String {
        pythonFrameworkOverride.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var pythonFrameworkOverrideState: AppFieldState {
        PythonFrameworkOverrideValidator.fieldState(for: pythonFrameworkOverride)
    }

    private let defaults: UserDefaults
    private let pythonFrameworkOverrideKey: String
    private let defaultApprovalModeKey: String

    init(
        defaults: UserDefaults = .standard,
        pythonFrameworkOverrideKey: String = "pythonFrameworkOverride",
        defaultApprovalModeKey: String = "defaultApprovalMode"
    ) {
        self.defaults = defaults
        self.pythonFrameworkOverrideKey = pythonFrameworkOverrideKey
        self.defaultApprovalModeKey = defaultApprovalModeKey
        self.pythonFrameworkOverride = defaults.string(forKey: pythonFrameworkOverrideKey) ?? ""
        self.defaultApprovalMode = ApprovalMode(
            rawValue: defaults.string(forKey: defaultApprovalModeKey) ?? ApprovalMode.observe.rawValue
        ) ?? .observe
    }
}
