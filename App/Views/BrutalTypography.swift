import SwiftUI

extension Font {
    static func brutalHero(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default)
    }

    static func brutalTitle(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func brutalBody(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func brutalMeta(_ size: CGFloat = 11, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
