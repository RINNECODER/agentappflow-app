import AppKit
import SwiftUI
import XCTest
@testable import AgentAppFlow

final class DesignSystemComponentTests: XCTestCase {
    func testDesignSystemGalleryRendersInBothColorSchemes() throws {
        let lightData = try snapshotData(
            of: DesignSystemGallery(),
            size: CGSize(width: 960, height: 760),
            scheme: .light
        )
        let darkData = try snapshotData(
            of: DesignSystemGallery(),
            size: CGSize(width: 960, height: 760),
            scheme: .dark
        )

        XCTAssertFalse(lightData.isEmpty)
        XCTAssertFalse(darkData.isEmpty)
        XCTAssertNotEqual(lightData, darkData, "Light and dark gallery renders should differ.")
    }

    func testDisabledButtonRendersDifferentlyFromEnabledButton() throws {
        let enabledData = try snapshotData(
            of: AppButton("Continue", variant: .primary, action: {}),
            size: CGSize(width: 220, height: 80),
            scheme: .light
        )
        let disabledData = try snapshotData(
            of: AppButton("Continue", variant: .primary, isDisabled: true, action: {}),
            size: CGSize(width: 220, height: 80),
            scheme: .light
        )

        XCTAssertNotEqual(enabledData, disabledData, "Disabled buttons should have a distinct visual treatment.")
    }

    func testAppButtonMeetsMinimumTapTarget() {
        let size = fittingSize(
            of: AppButton("Continue", variant: .primary, action: {})
        )

        XCTAssertGreaterThanOrEqual(size.height, AppTheme.Layout.minimumTapTarget)
        XCTAssertGreaterThanOrEqual(size.width, AppTheme.Layout.minimumTapTarget)
    }

    func testThemeModePickerMeetsMinimumTapTarget() {
        let size = fittingSize(of: ThemeModePickerHarness())

        XCTAssertGreaterThanOrEqual(size.height, AppTheme.Layout.minimumTapTarget)
    }
}

private struct DesignSystemGallery: View {
    @State private var repoPath = "/Users/example/AgentAppFlow"
    @State private var description = "Mac-first local AI orchestration with guarded repo writes."
    @State private var appearanceMode: AppearanceMode = .system

    var body: some View {
        ZStack {
            AppBackground()

            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                AppCard {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("AgentAppFlow Design System")
                            .font(AppTheme.Typography.display(34))
                        Text("Foundation snapshot for buttons, badges, text inputs, and surfaces.")
                            .font(AppTheme.Typography.body(15, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ThemeModePicker(selection: $appearanceMode)
                    }
                }

                HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
                    AppCard {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                            Text("Buttons")
                                .font(AppTheme.Typography.mono(12, weight: .black))
                                .textCase(.uppercase)
                            HStack(spacing: AppTheme.Spacing.sm) {
                                AppButton("Primary", variant: .primary, action: {})
                                AppButton("Secondary", variant: .secondary, action: {})
                                AppButton("Ghost", variant: .ghost, action: {})
                                AppButton("Delete", variant: .destructive, action: {})
                            }
                            AppButton("Loading", variant: .primary, isLoading: true, action: {})
                        }
                    }

                    AppCard {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                            Text("Status")
                                .font(AppTheme.Typography.mono(12, weight: .black))
                                .textCase(.uppercase)
                            HStack(spacing: AppTheme.Spacing.sm) {
                                AppBadge(status: .healthy)
                                AppBadge(status: .warning)
                                AppBadge(status: .error)
                                AppBadge(status: .idle)
                            }
                            AppDivider()
                            HStack(spacing: AppTheme.Spacing.sm) {
                                AppIcon(systemName: "sparkles", size: 18)
                                AppSpacer(AppTheme.Spacing.sm, axis: .horizontal)
                                Text("Icons share a single wrapper.")
                                    .font(AppTheme.Typography.body(14, weight: .semibold))
                            }
                        }
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("Inputs")
                            .font(AppTheme.Typography.mono(12, weight: .black))
                            .textCase(.uppercase)
                        AppTextField(
                            title: "Repository",
                            prompt: "Repository path",
                            text: $repoPath,
                            state: .valid("Path detected"),
                            usesMonospaceFont: true
                        )
                        AppTextArea(
                            title: "Project Brief",
                            prompt: "Describe the project context",
                            text: $description,
                            state: .warning("Keep the summary concise and repo-specific"),
                            minHeight: 120,
                            maxHeight: 140
                        )
                    }
                }
            }
            .padding(AppTheme.Spacing.xxxl)
        }
        .frame(width: 960, height: 760)
    }
}

private struct ThemeModePickerHarness: View {
    @State private var selection: AppearanceMode = .system

    var body: some View {
        ThemeModePicker(selection: $selection)
    }
}

private func fittingSize<V: View>(of view: V) -> CGSize {
    let hostingView = NSHostingView(rootView: view)
    hostingView.layoutSubtreeIfNeeded()
    return hostingView.fittingSize
}

private func snapshotData<V: View>(
    of view: V,
    size: CGSize,
    scheme: ColorScheme
) throws -> Data {
    let hostingView = NSHostingView(
        rootView: view
            .environment(\.colorScheme, scheme)
            .frame(width: size.width, height: size.height)
    )
    hostingView.frame = CGRect(origin: .zero, size: size)
    hostingView.layoutSubtreeIfNeeded()

    guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
        XCTFail("Failed to create bitmap for snapshot rendering.")
        return Data()
    }

    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        XCTFail("Failed to encode snapshot as PNG.")
        return Data()
    }

    return pngData
}
