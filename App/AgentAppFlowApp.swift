import SwiftUI

@main
struct AgentAppFlowApp: App {
    @StateObject private var themeController = ThemeController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeController)
                .preferredColorScheme(themeController.selection.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(
            width: AppTheme.Layout.defaultWindowSize.width,
            height: AppTheme.Layout.defaultWindowSize.height
        )
        .windowResizability(.contentMinSize)
    }
}
