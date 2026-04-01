import SwiftUI

enum AppButtonVariant {
    case primary
    case secondary
    case ghost
    case destructive
}

enum AppBadgeStatus: String, CaseIterable {
    case healthy
    case warning
    case error
    case idle

    var label: String {
        rawValue.capitalized
    }
}

enum AppFieldState: Equatable {
    case normal
    case valid(String? = nil)
    case warning(String)
    case error(String)

    var message: String? {
        switch self {
        case .warning(let message), .error(let message):
            message
        case .valid(let message):
            message
        case .normal:
            nil
        }
    }
}

struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppTheme.Colors.canvasTop(for: colorScheme),
                    AppTheme.Colors.canvasBottom(for: colorScheme),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [.white.opacity(colorScheme == .dark ? 0.12 : 0.40), .clear],
                center: .topLeading,
                startRadius: AppTheme.Spacing.xxxl,
                endRadius: 520
            )

            RadialGradient(
                colors: [.white.opacity(colorScheme == .dark ? 0.05 : 0.22), .clear],
                center: .bottomTrailing,
                startRadius: AppTheme.Spacing.xxxl,
                endRadius: 520
            )

            Circle()
                .fill(.white.opacity(colorScheme == .dark ? 0.06 : 0.20))
                .frame(width: 300, height: 300)
                .blur(radius: 120)
                .offset(x: -260, y: -220)

            Circle()
                .fill(.black.opacity(colorScheme == .dark ? 0.24 : 0.10))
                .frame(width: 380, height: 380)
                .blur(radius: 150)
                .offset(x: 300, y: 220)

            Rectangle()
                .fill(.ultraThinMaterial)

            LinearGradient(
                colors: [
                    .black.opacity(colorScheme == .dark ? 0.30 : 0.10),
                    .clear,
                    .black.opacity(colorScheme == .dark ? 0.34 : 0.12),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [.clear, .black.opacity(colorScheme == .dark ? 0.34 : 0.14)],
                center: .center,
                startRadius: 220,
                endRadius: 980
            )
        }
        .ignoresSafeArea()
    }
}

struct AppGlassSurface: View {
    let cornerRadius: CGFloat
    var material: Material = .thinMaterial
    var tintOpacityDark: Double = 0.05
    var tintOpacityLight: Double = 0.28

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(material)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        .white.opacity(colorScheme == .dark ? tintOpacityDark : tintOpacityLight)
                    )
            )
    }
}

struct AppCard<Content: View>: View {
    var padding: CGFloat = AppTheme.Spacing.xl
    var cornerRadius: CGFloat = AppTheme.Radius.lg
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(AppTheme.Colors.surfaceTint(for: colorScheme))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(AppTheme.Colors.border(for: colorScheme), lineWidth: 1)
        )
        .shadow(
            color: AppTheme.Shadow.panel(for: colorScheme),
            radius: AppTheme.Shadow.blur,
            x: 0,
            y: AppTheme.Shadow.y
        )
    }
}

struct AppInsetSurface: View {
    var emphasized: Bool = false
    var cornerRadius: CGFloat = AppTheme.Radius.md

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.thinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.Colors.insetSurfaceTint(for: colorScheme, emphasized: emphasized))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        emphasized ? AppTheme.Colors.primaryFill(for: colorScheme) : AppTheme.Colors.border(for: colorScheme),
                        lineWidth: emphasized ? 1.5 : 1
                    )
            )
    }
}

struct AppButton<Label: View>: View {
    let variant: AppButtonVariant
    let isLoading: Bool
    let isDisabled: Bool
    let accessibilityLabel: String?
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    init(
        variant: AppButtonVariant = .primary,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.variant = variant
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.label = label
    }

    init(
        _ title: String,
        variant: AppButtonVariant = .primary,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) where Label == Text {
        self.init(
            variant: variant,
            isLoading: isLoading,
            isDisabled: isDisabled,
            accessibilityLabel: accessibilityLabel,
            action: action
        ) {
            Text(title)
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                label()
                    .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .buttonStyle(AppButtonStyle(variant: variant))
        .disabled(isDisabled || isLoading)
        .modifier(OptionalAccessibilityLabel(label: accessibilityLabel))
    }
}

private struct OptionalAccessibilityLabel: ViewModifier {
    let label: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let label, !label.isEmpty {
            content.accessibilityLabel(label)
        } else {
            content
        }
    }
}

struct AppButtonStyle: ButtonStyle {
    let variant: AppButtonVariant

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.Typography.headline(14, weight: .black))
            .foregroundStyle(foregroundColor)
            .frame(minWidth: AppTheme.Layout.minimumTapTarget)
            .frame(height: AppTheme.Layout.buttonHeight)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg - 2, style: .continuous)
                    .fill(backgroundFill(configuration: configuration))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg - 2, style: .continuous)
                            .fill(backgroundTint)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg - 2, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .opacity(opacity(configuration: configuration))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isEnabled)
    }

    private func backgroundFill(configuration: Configuration) -> AnyShapeStyle {
        let pressedOpacity = configuration.isPressed ? 0.82 : 1.0

        switch variant {
        case .primary:
            return AnyShapeStyle(
                AppTheme.Colors.primaryFill(for: colorScheme)
                    .opacity(isEnabled ? pressedOpacity : 0.28)
            )
        case .secondary:
            if isEnabled {
                return AnyShapeStyle(.thinMaterial)
            } else {
                return AnyShapeStyle(
                    AppTheme.Colors.secondaryFill(for: colorScheme)
                        .opacity(colorScheme == .dark ? 0.55 : 0.85)
                )
            }
        case .ghost:
            if isEnabled {
                return AnyShapeStyle(.clear)
            } else {
                return AnyShapeStyle(
                    AppTheme.Colors.secondaryFill(for: colorScheme)
                        .opacity(colorScheme == .dark ? 0.18 : 0.42)
                )
            }
        case .destructive:
            return AnyShapeStyle(
                AppTheme.Colors.destructive
                    .opacity(isEnabled ? pressedOpacity : 0.30)
            )
        }
    }

    private var backgroundTint: Color {
        guard isEnabled else {
            return colorScheme == .dark ? .white.opacity(0.03) : .white.opacity(0.18)
        }

        switch variant {
        case .primary, .destructive, .ghost:
            return Color.clear
        case .secondary:
            return colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.24)
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary:
            AppTheme.Colors.primaryForeground(for: colorScheme).opacity(isEnabled ? 1 : 0.72)
        case .secondary, .ghost:
            AppTheme.Colors.secondaryForeground(for: colorScheme).opacity(isEnabled ? 1 : 0.46)
        case .destructive:
            Color.white.opacity(isEnabled ? 1 : 0.72)
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primary:
            AppTheme.Colors.primaryFill(for: colorScheme).opacity(isEnabled ? 1 : 0.24)
        case .secondary:
            AppTheme.Colors.border(for: colorScheme).opacity(isEnabled ? 1 : 0.55)
        case .ghost:
            AppTheme.Colors.borderStrong(for: colorScheme).opacity(isEnabled ? 1 : 0.42)
        case .destructive:
            AppTheme.Colors.destructive.opacity(isEnabled ? 1 : 0.34)
        }
    }

    private func opacity(configuration: Configuration) -> Double {
        switch (isEnabled, configuration.isPressed) {
        case (false, _):
            0.78
        case (true, true):
            0.78
        case (true, false):
            1
        }
    }
}

struct AppBadge: View {
    let status: AppBadgeStatus

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(status.label)
                .font(AppTheme.Typography.caption())
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(
            Capsule()
                .fill(.thinMaterial)
                .overlay(
                    Capsule()
                        .fill(AppTheme.Colors.insetSurfaceTint(for: colorScheme))
                )
        )
        .overlay(
            Capsule()
                .strokeBorder(AppTheme.Colors.border(for: colorScheme), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch status {
        case .healthy:
            AppTheme.Colors.healthy
        case .warning:
            AppTheme.Colors.warning
        case .error:
            AppTheme.Colors.destructive
        case .idle:
            AppTheme.Colors.idle
        }
    }

    private var foregroundColor: Color {
        AppTheme.Colors.foregroundPrimary(for: colorScheme)
    }
}

struct AppTextField: View {
    let title: String?
    let prompt: String
    @Binding var text: String
    var state: AppFieldState = .normal
    var usesMonospaceFont = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            if let title {
                Text(title)
                    .font(AppTheme.Typography.mono())
                    .foregroundStyle(AppTheme.Colors.foregroundSecondary(for: colorScheme))
                    .textCase(.uppercase)
            }

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(
                    usesMonospaceFont
                        ? AppTheme.Typography.mono(15, weight: .medium)
                        : AppTheme.Typography.headline(18, weight: .black)
                )
                .foregroundStyle(AppTheme.Colors.foregroundPrimary(for: colorScheme))
                .padding(.horizontal, AppTheme.Spacing.lg)
                .frame(height: AppTheme.Layout.controlHeight)
                .background(
                    AppInsetSurface(emphasized: isEmphasized, cornerRadius: AppTheme.Radius.xl - 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.xl - 4, style: .continuous)
                        .strokeBorder(stateColor, lineWidth: stateBorderWidth)
                )

            if let message = state.message {
                Text(message)
                    .font(AppTheme.Typography.body(13, weight: .semibold))
                    .foregroundStyle(stateColor)
            }
        }
    }

    private var isEmphasized: Bool {
        switch state {
        case .normal:
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            true
        }
    }

    private var stateColor: Color {
        switch state {
        case .normal:
            AppTheme.Colors.border(for: colorScheme)
        case .valid:
            AppTheme.Colors.healthy
        case .warning:
            AppTheme.Colors.warning
        case .error:
            AppTheme.Colors.destructive
        }
    }

    private var stateBorderWidth: CGFloat {
        switch state {
        case .normal:
            0
        default:
            1.5
        }
    }
}

struct AppTextArea: View {
    let title: String?
    let prompt: String
    @Binding var text: String
    var state: AppFieldState = .normal
    var minHeight: CGFloat = 112
    var maxHeight: CGFloat = 168

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            if let title {
                Text(title)
                    .font(AppTheme.Typography.mono())
                    .foregroundStyle(AppTheme.Colors.foregroundSecondary(for: colorScheme))
                    .textCase(.uppercase)
            }

            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .font(AppTheme.Typography.body(16, weight: .semibold))
                .frame(minHeight: minHeight, maxHeight: maxHeight, alignment: .topLeading)
                .padding(AppTheme.Spacing.lg)
                .background(
                    AppInsetSurface(emphasized: isEmphasized, cornerRadius: AppTheme.Radius.xl)
                )
                .overlay(alignment: .topLeading) {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(prompt)
                            .font(AppTheme.Typography.body(15, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.foregroundSecondary(for: colorScheme).opacity(0.9))
                            .padding(.horizontal, AppTheme.Spacing.xl)
                            .padding(.vertical, AppTheme.Spacing.xl - 2)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                        .strokeBorder(stateColor, lineWidth: stateBorderWidth)
                )

            if let message = state.message {
                Text(message)
                    .font(AppTheme.Typography.body(13, weight: .semibold))
                    .foregroundStyle(stateColor)
            }
        }
    }

    private var isEmphasized: Bool {
        switch state {
        case .normal:
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            true
        }
    }

    private var stateColor: Color {
        switch state {
        case .normal:
            AppTheme.Colors.border(for: colorScheme)
        case .valid:
            AppTheme.Colors.healthy
        case .warning:
            AppTheme.Colors.warning
        case .error:
            AppTheme.Colors.destructive
        }
    }

    private var stateBorderWidth: CGFloat {
        switch state {
        case .normal:
            0
        default:
            1.5
        }
    }
}

struct AppDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(AppTheme.Colors.border(for: colorScheme))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

struct AppSpacer: View {
    enum Axis {
        case horizontal
        case vertical
    }

    let axis: Axis
    let amount: CGFloat

    init(_ amount: CGFloat, axis: Axis = .vertical) {
        self.axis = axis
        self.amount = amount
    }

    var body: some View {
        Color.clear
            .frame(
                width: axis == .horizontal ? amount : nil,
                height: axis == .vertical ? amount : nil
            )
            .fixedSize()
    }
}

struct AppIcon: View {
    let systemName: String
    var size: CGFloat = 18
    var weight: Font.Weight = .black
    var color: Color?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color ?? AppTheme.Colors.foregroundPrimary(for: colorScheme))
            .frame(minWidth: AppTheme.Layout.minimumTapTarget, minHeight: AppTheme.Layout.minimumTapTarget)
    }
}

struct BrutalInset: View {
    var selected = false

    var body: some View {
        AppInsetSurface(emphasized: selected)
    }
}
