import SwiftUI

struct AdBlockerPopoverView: View {
    @ObservedObject var viewModel: BrowserViewModel
    let palette: NovaPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: viewModel.settings.adBlockerEnabled ? "checkmark.shield.fill" : "shield.slash.fill")
                    .font(.system(size: 24))
                    .foregroundColor(statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Escudo NOVA")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(palette.primaryText)

                    Text(statusSubtitle)
                        .font(.system(size: 12))
                        .foregroundColor(palette.secondaryText)
                }
                Spacer()
            }

            Divider()

            HStack(spacing: 16) {
                statBox(value: "\(viewModel.activeTab.blockedCount)", label: "En esta pestaña")
                statBox(value: "\(viewModel.settings.totalBlockedLifetime)", label: "Total acumulado")
            }

            if let host = viewModel.activeTab.currentHost {
                Toggle(isOn: Binding(
                    get: { !viewModel.isCurrentSiteWhitelisted },
                    set: { _ in
                        viewModel.toggleWhitelistForActiveSite()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Proteger \(host)")
                            .font(.system(size: 14, weight: .medium))
                        Text("Desactívalo si un sitio falla o no reproduce vídeo")
                            .font(.system(size: 11))
                            .foregroundColor(palette.secondaryText)
                    }
                }
                .disabled(!viewModel.settings.adBlockerEnabled)
            }

            Toggle(isOn: Binding(
                get: { viewModel.settings.adBlockerEnabled },
                set: { newValue in
                    viewModel.setAdBlockerEnabled(newValue)
                }
            )) {
                Text("Bloqueador global activo")
                    .font(.system(size: 14, weight: .medium))
            }

            Text("WebKit filtra peticiones de red en segundo plano; el contador refleja popups, redirecciones y bloques detectables en la página.")
                .font(.system(size: 11))
                .foregroundColor(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(compiledRulesSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(palette.secondaryText)

                Spacer()

                Button("Ajustes") {
                    viewModel.showAdBlockPopover = false
                    viewModel.showSettings = true
                }
                .font(.system(size: 13, weight: .semibold))
            }
        }
        .padding(18)
        .frame(width: 330)
    }

    private var statusColor: Color {
        if !viewModel.settings.adBlockerEnabled {
            return palette.secondaryText
        }
        return viewModel.isCurrentSiteWhitelisted ? palette.shieldPaused : palette.shieldActive
    }

    private var statusSubtitle: String {
        if !viewModel.settings.adBlockerEnabled {
            return "Bloqueador desactivado globalmente"
        }
        if viewModel.isCurrentSiteWhitelisted {
            return "Pausado en este sitio (excepción)"
        }
        return "Bloqueando anuncios, rastreadores y popups"
    }

    private var compiledRulesSummary: String {
        switch viewModel.adBlocker.status {
        case .ready(let count):
            return "\(count) reglas activas"
        case .compiling:
            return "Compilando reglas..."
        case .disabled:
            return "Desactivado"
        case .idle:
            return "Preparando..."
        case .error:
            return "Usando protección básica"
        }
    }

    private func statBox(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(palette.primaryText)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(palette.addressBarBackground.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
