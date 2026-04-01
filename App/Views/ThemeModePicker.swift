import SwiftUI

struct WindowTrafficDots: View {
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs + 2) {
            Circle().fill(AppTheme.Colors.trafficRed).frame(width: 14, height: 14)
            Circle().fill(AppTheme.Colors.trafficYellow).frame(width: 14, height: 14)
            Circle().fill(AppTheme.Colors.trafficGreen).frame(width: 14, height: 14)
        }
        .frame(height: 14)
    }
}

struct ThemeModePicker: View {
    @Binding var selection: AppearanceMode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            ForEach(AppearanceMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    AppIcon(systemName: symbolName(for: mode), size: 12)
                        .foregroundStyle(
                            selection == mode
                                ? AppTheme.Colors.primaryForeground(for: colorScheme)
                                : AppTheme.Colors.foregroundPrimary(for: colorScheme)
                        )
                        .frame(width: AppTheme.Layout.minimumTapTarget, height: AppTheme.Layout.minimumTapTarget)
                        .background(modeFill(for: mode))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.displayName)
            }
        }
    }

    private func symbolName(for mode: AppearanceMode) -> String {
        switch mode {
        case .system:
            "circle.lefthalf.filled"
        case .light:
            "sun.max.fill"
        case .dark:
            "moon.fill"
        }
    }

    @ViewBuilder
    private func modeFill(for mode: AppearanceMode) -> some View {
        let isSelected = selection == mode
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                isSelected
                    ? AppTheme.Colors.primaryFill(for: colorScheme)
                    : AppTheme.Colors.secondaryFill(for: colorScheme).opacity(colorScheme == .dark ? 1 : 0.92)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? AppTheme.Colors.primaryFill(for: colorScheme)
                            : AppTheme.Colors.border(for: colorScheme),
                        lineWidth: 1
                    )
            )
    }
}
