import SwiftUI

struct ConnectionErrorView: View {
    let errorMessage: String
    let failedURL: String?
    let palette: NovaPalette
    let canGoBack: Bool
    let onRetry: () -> Void
    let onBack: () -> Void
    let onHome: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(palette.elevatedSurface)
                    .frame(width: 68, height: 68)
                    .overlay(
                        Circle()
                            .stroke(palette.border, lineWidth: 1)
                    )

                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(palette.secondaryText)
            }

            VStack(spacing: 6) {
                Text("No se pudo abrir la página")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(palette.primaryText)

                if let failedURL = failedURL, !failedURL.isEmpty {
                    Text(failedURL)
                        .font(.system(size: 13))
                        .foregroundColor(palette.secondaryText)
                        .lineLimit(1)
                }

                Text(errorMessage)
                    .font(.system(size: 14))
                    .foregroundColor(palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .padding(.top, 4)
            }

            HStack(spacing: 12) {
                Button(action: onRetry) {
                    Label("Reintentar", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(palette.accent)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                if canGoBack {
                    Button(action: onBack) {
                        Text("Volver atrás")
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(palette.elevatedSurface)
                            .foregroundColor(palette.primaryText)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(palette.border, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onHome) {
                    Text("Inicio")
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(palette.elevatedSurface)
                        .foregroundColor(palette.primaryText)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(palette.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.canvasBackground)
    }
}
