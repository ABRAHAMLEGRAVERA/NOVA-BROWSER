import SwiftUI

struct NovaPalette {
    let chromeBackground: Color
    let canvasBackground: Color
    let elevatedSurface: Color
    let addressBarBackground: Color
    let border: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let shieldActive: Color
    let shieldPaused: Color
    let incognitoAccent: Color

    static func resolve(colorScheme: ColorScheme, isIncognito: Bool) -> NovaPalette {
        if isIncognito {
            return NovaPalette(
                chromeBackground: Color(hex: "#15121F"),
                canvasBackground: Color(hex: "#0E0C15"),
                elevatedSurface: Color(hex: "#1E1A2D"),
                addressBarBackground: Color(hex: "#262138"),
                border: Color(hex: "#332C4A"),
                primaryText: Color(hex: "#F3F2F7"),
                secondaryText: Color(hex: "#A59EC0"),
                accent: Color(hex: "#8B5CF6"),
                shieldActive: Color(hex: "#34D399"),
                shieldPaused: Color(hex: "#FBBF24"),
                incognitoAccent: Color(hex: "#A78BFA")
            )
        }

        if colorScheme == .dark {
            return NovaPalette(
                chromeBackground: Color(hex: "#10131A"),
                canvasBackground: Color(hex: "#0A0C10"),
                elevatedSurface: Color(hex: "#181C26"),
                addressBarBackground: Color(hex: "#1E2330"),
                border: Color(hex: "#282F40"),
                primaryText: Color(hex: "#F3F4F6"),
                secondaryText: Color(hex: "#94A3B8"),
                accent: Color(hex: "#4F8BFF"),
                shieldActive: Color(hex: "#34D399"),
                shieldPaused: Color(hex: "#FBBF24"),
                incognitoAccent: Color(hex: "#8B5CF6")
            )
        } else {
            return NovaPalette(
                chromeBackground: Color(hex: "#F3F5F8"),
                canvasBackground: Color(hex: "#F8FAFC"),
                elevatedSurface: Color(hex: "#FFFFFF"),
                addressBarBackground: Color(hex: "#E8ECF2"),
                border: Color(hex: "#DCE2EC"),
                primaryText: Color(hex: "#111827"),
                secondaryText: Color(hex: "#64748B"),
                accent: Color(hex: "#2563EB"),
                shieldActive: Color(hex: "#059669"),
                shieldPaused: Color(hex: "#D97706"),
                incognitoAccent: Color(hex: "#7C3AED")
            )
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 37, 99, 235)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }
}

struct NovaStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) * 0.48
        let inner = outer * 0.28
        var path = Path()
        for i in 0..<8 {
            let angle = (Double(i) * .pi / 4.0) - (.pi / 2.0)
            let radius = (i % 2 == 0) ? outer : inner
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

struct NovaEmblemView: View {
    var size: CGFloat = 44
    var accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#0F172A"), Color(hex: "#1E1B4B")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            NovaStarShape()
                .fill(
                    LinearGradient(
                        colors: [Color.white, accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.72, height: size * 0.72)
        }
    }
}
