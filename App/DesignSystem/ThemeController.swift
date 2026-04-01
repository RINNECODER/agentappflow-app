import Foundation

final class ThemeController: ObservableObject {
    @Published var selection: AppearanceMode {
        didSet {
            defaults.set(selection.rawValue, forKey: storageKey)
        }
    }

    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "selectedAppearanceMode"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.selection = AppearanceMode(
            rawValue: defaults.string(forKey: storageKey) ?? AppearanceMode.system.rawValue
        ) ?? .system
    }
}
