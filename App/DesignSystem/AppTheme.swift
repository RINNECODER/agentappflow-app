import CoreGraphics
import SwiftUI

enum AppTheme {
    enum Colors {
        static func canvasTop(for scheme: ColorScheme) -> Color {
            switch scheme {
            case .dark:
                Color(red: 0.18, green: 0.18, blue: 0.20)
            default:
                Color(red: 0.92, green: 0.93, blue: 0.95)
            }
        }

        static func canvasBottom(for scheme: ColorScheme) -> Color {
            switch scheme {
            case .dark:
                Color(red: 0.10, green: 0.10, blue: 0.12)
            default:
                Color(red: 0.82, green: 0.84, blue: 0.88)
            }
        }

        static func surfaceTint(for scheme: ColorScheme) -> Color {
            scheme == .dark ? .white.opacity(0.05) : .white.opacity(0.22)
        }

        static func elevatedSurfaceTint(for scheme: ColorScheme) -> Color {
            scheme == .dark ? .white.opacity(0.08) : .white.opacity(0.30)
        }

        static func insetSurfaceTint(for scheme: ColorScheme, emphasized: Bool = false) -> Color {
            switch (scheme, emphasized) {
            case (.dark, true):
                .white.opacity(0.10)
            case (.dark, false):
                .white.opacity(0.04)
            case (_, true):
                .white.opacity(0.38)
            case (_, false):
                .white.opacity(0.20)
            }
        }

        static func border(for scheme: ColorScheme) -> Color {
            scheme == .dark ? .white.opacity(0.12) : .black.opacity(0.08)
        }

        static func borderStrong(for scheme: ColorScheme) -> Color {
            scheme == .dark ? .white.opacity(0.20) : .black.opacity(0.14)
        }

        static func foregroundPrimary(for scheme: ColorScheme) -> Color {
            scheme == .dark ? .white : .black
        }

        static func foregroundSecondary(for scheme: ColorScheme) -> Color {
            scheme == .dark ? .white.opacity(0.72) : .black.opacity(0.60)
        }

        static func primaryFill(for scheme: ColorScheme) -> Color {
            scheme == .dark ? .white : .black
        }

        static func primaryForeground(for scheme: ColorScheme) -> Color {
            scheme == .dark ? .black : .white
        }

        static func secondaryFill(for scheme: ColorScheme) -> Color {
            scheme == .dark ? .white.opacity(0.08) : .white.opacity(0.42)
        }

        static func secondaryForeground(for scheme: ColorScheme) -> Color {
            foregroundPrimary(for: scheme)
        }

        static let destructive = Color(red: 0.82, green: 0.24, blue: 0.22)
        static let warning = Color(red: 0.88, green: 0.60, blue: 0.14)
        static let healthy = Color(red: 0.17, green: 0.65, blue: 0.35)
        static let idle = Color(red: 0.44, green: 0.48, blue: 0.55)

        static let trafficRed = Color(red: 1.00, green: 0.37, blue: 0.36)
        static let trafficYellow = Color(red: 1.00, green: 0.76, blue: 0.10)
        static let trafficGreen = Color(red: 0.17, green: 0.83, blue: 0.30)
    }

    enum Typography {
        static func display(_ size: CGFloat = 54) -> Font {
            .system(size: size, weight: .black, design: .rounded)
        }

        static func headline(_ size: CGFloat = 28, weight: Font.Weight = .black) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }

        static func body(_ size: CGFloat = 15, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight, design: .default)
        }

        static func caption(_ size: CGFloat = 12, weight: Font.Weight = .bold) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }

        static func mono(_ size: CGFloat = 11, weight: Font.Weight = .bold) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 18
        static let xl: CGFloat = 22
        static let xxl: CGFloat = 28
        static let xxxl: CGFloat = 40
    }

    enum Radius {
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 26
        static let shell: CGFloat = 32
    }

    enum Shadow {
        static func panel(for scheme: ColorScheme) -> Color {
            .black.opacity(scheme == .dark ? 0.28 : 0.12)
        }

        static let blur: CGFloat = 24
        static let y: CGFloat = 10
    }

    enum Layout {
        static let minWindowSize = CGSize(width: 820, height: 620)
        static let defaultWindowSize = CGSize(width: 1320, height: 860)
        static let controlCenterSidebarWidth: CGFloat = 286
        static let controlCenterMinSize = CGSize(width: 1200, height: 820)
        static let setupMinSize = CGSize(width: 560, height: 520)
        static let buttonHeight: CGFloat = 46
        static let controlHeight: CGFloat = 54
        static let minimumTapTarget: CGFloat = 44
    }
}

extension Font {
    static func brutalHero(_ size: CGFloat) -> Font {
        AppTheme.Typography.display(size)
    }

    static func brutalTitle(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        AppTheme.Typography.headline(size, weight: weight)
    }

    static func brutalBody(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        AppTheme.Typography.body(size, weight: weight)
    }

    static func brutalMeta(_ size: CGFloat = 11, weight: Font.Weight = .bold) -> Font {
        AppTheme.Typography.mono(size, weight: weight)
    }
}
