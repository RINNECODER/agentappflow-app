import SwiftUI

struct NavigationShell<Sidebar: View, MainContent: View>: View {
    let sidebarWidth: CGFloat
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let mainContent: MainContent

    init(
        sidebarWidth: CGFloat = AppTheme.Layout.controlCenterSidebarWidth,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder mainContent: () -> MainContent
    ) {
        self.sidebarWidth = sidebarWidth
        self.sidebar = sidebar()
        self.mainContent = mainContent()
    }

    var body: some View {
        ZStack {
            AppBackground()

            HStack(spacing: AppTheme.Spacing.lg) {
                sidebar
                    .frame(width: sidebarWidth)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                        mainContent
                    }
                    .padding(AppTheme.Spacing.xl)
                    .padding(.top, AppTheme.Spacing.xxxl)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.xl - 2)
            .padding(.top, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.xl - 2)
        }
    }
}
