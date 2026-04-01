import SwiftUI

struct WindowTrafficDots: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.36)).frame(width: 14, height: 14)
            Circle().fill(Color(red: 1.0, green: 0.76, blue: 0.10)).frame(width: 14, height: 14)
            Circle().fill(Color(red: 0.17, green: 0.83, blue: 0.30)).frame(width: 14, height: 14)
        }
        .frame(height: 14)
    }
}

struct ThemeModePicker: View {
    @Binding var selection: AppearanceMode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppearanceMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Image(systemName: symbolName(for: mode))
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(
                            selection == mode
                                ? (colorScheme == .dark ? Color.black : Color.white)
                                : Color.primary
                        )
                        .frame(width: 30, height: 30)
                        .background(modeFill(for: mode))
                }
                .buttonStyle(.plain)
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
                    ? (colorScheme == .dark ? Color.white : Color.black)
                    : (colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? (colorScheme == .dark ? Color.white : Color.black)
                            : (colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)),
                        lineWidth: 1
                    )
            )
    }
}
