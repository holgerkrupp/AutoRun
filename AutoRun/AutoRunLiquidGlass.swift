import SwiftUI

struct AutoRunLiquidGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Ellipse()
                .fill(Color.cyan.opacity(colorScheme == .dark ? 0.24 : 0.16))
                .frame(width: 360, height: 280)
                .blur(radius: 90)
                .offset(x: -150, y: -160)

            Ellipse()
                .fill(Color.indigo.opacity(colorScheme == .dark ? 0.24 : 0.12))
                .frame(width: 320, height: 280)
                .blur(radius: 110)
                .offset(x: 170, y: -10)

            Ellipse()
                .fill(Color.mint.opacity(colorScheme == .dark ? 0.18 : 0.14))
                .frame(width: 360, height: 300)
                .blur(radius: 120)
                .offset(x: 10, y: 240)
        }
        .overlay {
            Color.white.opacity(colorScheme == .dark ? 0.035 : 0.12)
        }
        .ignoresSafeArea()
    }

    private var backgroundColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.025, green: 0.06, blue: 0.12),
                Color(red: 0.05, green: 0.15, blue: 0.19),
                Color(red: 0.15, green: 0.20, blue: 0.29)
            ]
        }

        return [
            Color(red: 0.90, green: 0.96, blue: 1.00),
            Color(red: 0.83, green: 0.94, blue: 0.94),
            Color(red: 0.91, green: 0.89, blue: 0.98)
        ]
    }
}

private struct AutoRunGlassPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let tint: Color

    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                .regular.tint(tint.opacity(colorScheme == .dark ? 0.18 : 0.12)),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.10), radius: 24, y: 12)
    }
}

extension View {
    func autoRunGlassPanel(tint: Color = .white) -> some View {
        modifier(AutoRunGlassPanelModifier(tint: tint))
    }
}
