import CoreGraphics
import SwiftUI

enum AppTheme {
    enum Colors {
        static func canvasTop(for scheme: ColorScheme) -> Color {
            switch scheme {
            case .dark:
                Color(red: 0.06, green: 0.07, blue: 0.10)
            default:
                Color(red: 0.96, green: 0.96, blue: 0.97)
            }
        }

        static func canvasBottom(for scheme: ColorScheme) -> Color {
            switch scheme {
            case .dark:
                Color(red: 0.02, green: 0.02, blue: 0.05)
            default:
                Color(red: 0.90, green: 0.91, blue: 0.93)
            }
        }

        static func surfaceTint(for scheme: ColorScheme) -> Color {
            scheme == .dark ? .white.opacity(0.02) : .white.opacity(0.40)
        }

        static func elevatedSurfaceTint(for scheme: ColorScheme) -> Color {
            scheme == .dark ? chromeBlue.opacity(0.10) : .white.opacity(0.62)
        }

        static func insetSurfaceTint(for scheme: ColorScheme, emphasized: Bool = false) -> Color {
            switch (scheme, emphasized) {
            case (.dark, true):
                chromeBlue.opacity(0.14)
            case (.dark, false):
                .white.opacity(0.025)
            case (_, true):
                .white.opacity(0.62)
            case (_, false):
                .white.opacity(0.30)
            }
        }

        static func border(for scheme: ColorScheme) -> Color {
            scheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06)
        }

        static func borderStrong(for scheme: ColorScheme) -> Color {
            scheme == .dark ? .white.opacity(0.16) : .black.opacity(0.11)
        }

        static func foregroundPrimary(for scheme: ColorScheme) -> Color {
            scheme == .dark ? .white.opacity(0.97) : Color(red: 0.08, green: 0.09, blue: 0.12)
        }

        static func foregroundSecondary(for scheme: ColorScheme) -> Color {
            scheme == .dark ? .white.opacity(0.64) : .black.opacity(0.54)
        }

        static func primaryFill(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.94) : Color(red: 0.08, green: 0.09, blue: 0.12)
        }

        static func primaryForeground(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color(red: 0.08, green: 0.09, blue: 0.12) : .white
        }

        static func secondaryFill(for scheme: ColorScheme) -> Color {
            scheme == .dark ? .white.opacity(0.06) : .white.opacity(0.70)
        }

        static func secondaryForeground(for scheme: ColorScheme) -> Color {
            foregroundPrimary(for: scheme)
        }

        static func chromeGlow(for scheme: ColorScheme) -> Color {
            scheme == .dark ? chromeBlue.opacity(0.22) : chromeBlue.opacity(0.10)
        }

        static func chromeHighlight(for scheme: ColorScheme) -> LinearGradient {
            LinearGradient(
                colors: [
                    chromeBlue.opacity(scheme == .dark ? 0.20 : 0.10),
                    chromeViolet.opacity(scheme == .dark ? 0.12 : 0.07),
                    chromeTeal.opacity(scheme == .dark ? 0.08 : 0.05),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        static let destructive = Color(red: 0.82, green: 0.24, blue: 0.22)
        static let warning = Color(red: 0.88, green: 0.60, blue: 0.14)
        static let healthy = Color(red: 0.17, green: 0.65, blue: 0.35)
        static let idle = Color(red: 0.44, green: 0.48, blue: 0.55)
        static let chromeBlue = Color(red: 0.34, green: 0.52, blue: 0.98)
        static let chromeViolet = Color(red: 0.50, green: 0.34, blue: 0.82)
        static let chromeTeal = Color(red: 0.21, green: 0.68, blue: 0.71)

        static let trafficRed = Color(red: 1.00, green: 0.37, blue: 0.36)
        static let trafficYellow = Color(red: 1.00, green: 0.76, blue: 0.10)
        static let trafficGreen = Color(red: 0.17, green: 0.83, blue: 0.30)
    }

    enum Typography {
        static func display(_ size: CGFloat = 54) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }

        static func headline(_ size: CGFloat = 28, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }

        static func body(_ size: CGFloat = 15, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }

        static func caption(_ size: CGFloat = 12, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }

        static func mono(_ size: CGFloat = 11, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let compact: CGFloat = 12
        static let md: CGFloat = 14
        static let regular: CGFloat = 16
        static let lg: CGFloat = 18
        static let relaxed: CGFloat = 20
        static let xl: CGFloat = 22
        static let section: CGFloat = 24
        static let xxl: CGFloat = 28
        static let xxxl: CGFloat = 40
    }

    enum Radius {
        static let sm: CGFloat = 12
        static let md: CGFloat = 18
        static let lg: CGFloat = 22
        static let xl: CGFloat = 28
        static let shell: CGFloat = 34
    }

    enum Shadow {
        static func panel(for scheme: ColorScheme) -> Color {
            scheme == .dark ? .black.opacity(0.28) : .black.opacity(0.08)
        }

        static let blur: CGFloat = 28
        static let y: CGFloat = 12
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

    enum Motion {
        static let smooth = Animation.easeInOut(duration: 0.2)
        static let spring = Animation.spring(response: 0.34, dampingFraction: 0.82)
        static let emphasis = Animation.spring(response: 0.42, dampingFraction: 0.78)
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
