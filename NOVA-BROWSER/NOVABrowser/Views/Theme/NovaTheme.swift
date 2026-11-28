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
                chromeBackground: Color(hex: "#1C1B22"),
                canvasBackground: Color(hex: "#100F14"),
                elevatedSurface: Color(hex: "#2B2836"),
                addressBarBackground: Color(hex: "#322E40"),
                border: Color(hex: "#423D54"),
                primaryText: Color(hex: "#F5F5F7"),
                secondaryText: Color(hex: "#AEAEB8"),
                accent: Color(hex: "#BF5AF2"),
                shieldActive: Color(hex: "#30D158"),
                shieldPaused: Color(hex: "#FFD60A"),
                incognitoAccent: Color(hex: "#BF5AF2")
            )
        }

        if colorScheme == .dark {
            return NovaPalette(
                chromeBackground: Color(hex: "#1C1C1E"),
                canvasBackground: Color(hex: "#111113"),
                elevatedSurface: Color(hex: "#2C2C2E"),
                addressBarBackground: Color(hex: "#2C2C2F"),
                border: Color(hex: "#38383A"),
                primaryText: Color(hex: "#FFFFFF"),
                secondaryText: Color(hex: "#98989F"),
                accent: Color(hex: "#0A84FF"),
                shieldActive: Color(hex: "#30D158"),
                shieldPaused: Color(hex: "#FFD60A"),
                incognitoAccent: Color(hex: "#BF5AF2")
            )
        } else {
            return NovaPalette(
                chromeBackground: Color(hex: "#F2F2F7"),
                canvasBackground: Color(hex: "#FFFFFF"),
                elevatedSurface: Color(hex: "#FFFFFF"),
                addressBarBackground: Color(hex: "#E3E3E8"),
                border: Color(hex: "#D1D1D6"),
                primaryText: Color(hex: "#1C1C1E"),
                secondaryText: Color(hex: "#6E6E73"),
                accent: Color(hex: "#007AFF"),
                shieldActive: Color(hex: "#34C759"),
                shieldPaused: Color(hex: "#FF9F0A"),
                incognitoAccent: Color(hex: "#AF52DE")
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
            (a, r, g, b) = (255, 0, 122, 255)
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
                        colors: [Color(hex: "#1C1C1E"), Color(hex: "#0A84FF").opacity(0.65)],
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
