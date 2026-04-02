import SwiftUI

struct WindowTrafficDots: View {
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs + 2) {
            Circle().fill(AppTheme.Colors.trafficRed).frame(width: 12, height: 12)
            Circle().fill(AppTheme.Colors.trafficYellow).frame(width: 12, height: 12)
            Circle().fill(AppTheme.Colors.trafficGreen).frame(width: 12, height: 12)
        }
        .frame(height: 12)
        .opacity(0.88)
    }
}

struct ThemeModePicker: View {
    @Binding var selection: AppearanceMode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            ForEach(AppearanceMode.allCases) { mode in
                Button {
                    withAnimation(AppTheme.Motion.spring) {
                        selection = mode
                    }
                } label: {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        AppIcon(systemName: symbolName(for: mode), size: 12)
                            .foregroundStyle(
                                selection == mode
                                    ? AppTheme.Colors.primaryForeground(for: colorScheme)
                                    : AppTheme.Colors.foregroundPrimary(for: colorScheme)
                            )
                            .frame(minWidth: 18, minHeight: 18)

                        Text(mode.displayName)
                            .font(AppTheme.Typography.body(13, weight: .semibold))
                            .foregroundStyle(
                                selection == mode
                                    ? AppTheme.Colors.primaryForeground(for: colorScheme)
                                    : AppTheme.Colors.foregroundPrimary(for: colorScheme)
                            )
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .frame(height: AppTheme.Layout.minimumTapTarget)
                        .background(modeFill(for: mode))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.displayName)
                .scaleEffect(selection == mode ? 1 : 0.98)
                .animation(AppTheme.Motion.smooth, value: selection == mode)
            }
        }
        .padding(AppTheme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .fill(AppTheme.Colors.secondaryFill(for: colorScheme).opacity(colorScheme == .dark ? 0.52 : 0.80))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .strokeBorder(AppTheme.Colors.border(for: colorScheme), lineWidth: 1)
        )
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
                    : AppTheme.Colors.secondaryFill(for: colorScheme).opacity(colorScheme == .dark ? 0.3 : 0.35)
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
