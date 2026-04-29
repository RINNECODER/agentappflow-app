import AppKit
import SwiftUI

struct AppPreferencesView: View {
    @EnvironmentObject private var preferencesStore: AppPreferencesStore
    @EnvironmentObject private var themeController: ThemeController

    var body: some View {
        ZStack {
            AppBackground()

            AppCard(padding: AppTheme.Spacing.xxl, cornerRadius: AppTheme.Radius.xl, interactive: true) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        AppBadge(status: .idle)
                        Text("Preferences")
                            .font(AppTheme.Typography.display(34))
                        Text("Global defaults for appearance, runtime discovery, and how AgentAppFlow behaves before a project-specific contract takes over.")
                            .font(AppTheme.Typography.body(15, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                        PreferencesSectionCard(title: "Appearance", subtitle: "Keep the global shell consistent across all workspaces.") {
                            ThemeModePicker(selection: $themeController.selection)
                        }

                        PreferencesSectionCard(title: "Runtime", subtitle: "Override the embedded Python framework when debugging local bootstrap behavior.") {
                            AppTextField(
                                title: "Python Framework Override",
                                prompt: "/Applications/AgentAppFlow.app/Contents/Frameworks/Python3.framework",
                                text: $preferencesStore.pythonFrameworkOverride,
                                state: preferencesStore.pythonFrameworkOverrideState,
                                usesMonospaceFont: true
                            )

                            Text("Expected format: a framework directory path ending in Python3.framework. Leave blank to use the embedded runtime.")
                                .font(AppTheme.Typography.body(12, weight: .semibold))
                                .foregroundStyle(.secondary)

                            HStack(spacing: AppTheme.Spacing.sm) {
                                AppButton(
                                    "Browse…",
                                    variant: .secondary,
                                    action: choosePythonFrameworkOverride
                                )
                                AppButton(
                                    "Reveal in Finder",
                                    variant: .secondary,
                                    isDisabled: preferencesStore.trimmedPythonFrameworkOverride.isEmpty,
                                    action: revealPythonFrameworkOverride
                                )
                                AppButton(
                                    "Clear Override",
                                    variant: .secondary,
                                    isDisabled: preferencesStore.trimmedPythonFrameworkOverride.isEmpty,
                                    action: clearPythonFrameworkOverride
                                )
                            }
                        }

                        PreferencesSectionCard(title: "Approval Defaults", subtitle: "Define the default posture before project settings override it.") {
                            Picker("Default Approval Mode", selection: $preferencesStore.defaultApprovalMode) {
                                ForEach(ApprovalMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(preferencesStore.defaultApprovalMode.subtitle)
                                .font(AppTheme.Typography.body(13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: 720)
            .padding(AppTheme.Spacing.xxxl)
        }
        .frame(
            minWidth: 760,
            minHeight: 520
        )
    }

    private func choosePythonFrameworkOverride() {
        let panel = NSOpenPanel()
        panel.prompt = "Choose Framework"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = preferencesStore.trimmedPythonFrameworkOverride.isEmpty
            ? nil
            : URL(fileURLWithPath: preferencesStore.trimmedPythonFrameworkOverride)

        if panel.runModal() == .OK, let url = panel.url {
            preferencesStore.pythonFrameworkOverride = url.path
        }
    }

    private func revealPythonFrameworkOverride() {
        let trimmed = preferencesStore.trimmedPythonFrameworkOverride
        guard !trimmed.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: trimmed))
    }

    private func clearPythonFrameworkOverride() {
        preferencesStore.pythonFrameworkOverride = ""
    }
}

private struct PreferencesSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        AppCard(padding: AppTheme.Spacing.lg, cornerRadius: AppTheme.Radius.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(title)
                        .font(AppTheme.Typography.mono(12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(subtitle)
                        .font(AppTheme.Typography.body(13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                content
            }
        }
    }
}
