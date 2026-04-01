import AppKit
import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedInitialSetup") private var hasCompletedInitialSetup = false
    @AppStorage("workspaceSnapshot") private var workspaceSnapshotData = ""

    var body: some View {
        Group {
            if let workspaceSnapshot {
                ControlCenterView(
                    snapshot: workspaceSnapshot,
                    resetInitialSetup: resetInitialSetup
                )
            } else {
                FirstRunSetupView(
                    completeInitialSetup: completeInitialSetup
                )
            }
        }
        .background(WindowConfigurator())
    }

    private var workspaceSnapshot: WorkspaceSnapshot? {
        guard hasCompletedInitialSetup else {
            return nil
        }
        return WorkspaceSnapshot.decode(from: workspaceSnapshotData)
    }

    private func completeInitialSetup(with snapshot: WorkspaceSnapshot) {
        workspaceSnapshotData = snapshot.encoded() ?? ""
        hasCompletedInitialSetup = true
    }

    private func resetInitialSetup() {
        hasCompletedInitialSetup = false
        workspaceSnapshotData = ""
    }
}

struct AgentAppFlowBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: baseColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.12 : 0.40),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 40,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.05 : 0.22),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 40,
                endRadius: 520
            )

            Circle()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.20))
                .frame(width: 300, height: 300)
                .blur(radius: 120)
                .offset(x: -260, y: -220)

            Circle()
                .fill(Color.black.opacity(colorScheme == .dark ? 0.24 : 0.10))
                .frame(width: 380, height: 380)
                .blur(radius: 150)
                .offset(x: 300, y: 220)

            Rectangle()
                .fill(.ultraThinMaterial)

            LinearGradient(
                colors: [
                    Color.black.opacity(colorScheme == .dark ? 0.30 : 0.10),
                    Color.clear,
                    Color.black.opacity(colorScheme == .dark ? 0.34 : 0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(colorScheme == .dark ? 0.34 : 0.14)
                ],
                center: .center,
                startRadius: 220,
                endRadius: 980
            )
        }
        .ignoresSafeArea()
    }

    private var baseColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.18, green: 0.18, blue: 0.20),
                Color(red: 0.10, green: 0.10, blue: 0.12)
            ]
        }

        return [
            Color(red: 0.92, green: 0.93, blue: 0.95),
            Color(red: 0.82, green: 0.84, blue: 0.88)
        ]
    }
}

struct GlassSurface: View {
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
                        Color.white.opacity(
                            colorScheme == .dark ? tintOpacityDark : tintOpacityLight
                        )
                    )
            )
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindowIfNeeded(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindowIfNeeded(for: nsView)
        }
    }

    private func configureWindowIfNeeded(for view: NSView) {
        guard let window = view.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
    }
}
