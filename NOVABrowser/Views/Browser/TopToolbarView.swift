import SwiftUI

struct TopToolbarView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var downloadManager: DownloadManager
    let palette: NovaPalette
    let isCompactWidth: Bool
    @FocusState.Binding var isAddressFocused: Bool

    var body: some View {
        HStack(spacing: isCompactWidth ? 5 : 8) {
            // Left navigation controls
            HStack(spacing: 2) {
                ToolbarIconButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "Atrás",
                    isEnabled: viewModel.activeTab.canGoBack || !viewModel.activeTab.isStartPage,
                    palette: palette
                ) {
                    viewModel.goBack()
                }
                .keyboardShortcut("[", modifiers: .command)

                ToolbarIconButton(
                    systemName: "chevron.right",
                    accessibilityLabel: "Adelante",
                    isEnabled: viewModel.activeTab.canGoForward,
                    palette: palette
                ) {
                    viewModel.goForward()
                }
                .keyboardShortcut("]", modifiers: .command)

                ToolbarIconButton(
                    systemName: "house",
                    accessibilityLabel: "Inicio",
                    isEnabled: true,
                    palette: palette
                ) {
                    viewModel.goHome()
                }

                ToolbarIconButton(
                    systemName: "book",
                    accessibilityLabel: "Favoritos e historial",
                    isEnabled: true,
                    palette: palette
                ) {
                    viewModel.libraryInitialTab = .bookmarks
                    viewModel.showLibrary = true
                }
            }

            // Center integrated address & search bar
            HStack(spacing: 8) {
                Button {
                    viewModel.showAdBlockPopover.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: shieldIconName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(shieldColor)

                        if viewModel.activeTab.blockedCount > 0 && viewModel.settings.adBlockerEnabled {
                            Text("\(viewModel.activeTab.blockedCount)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(shieldColor)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(shieldColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Estado del bloqueador de anuncios")
                .popover(isPresented: $viewModel.showAdBlockPopover) {
                    AdBlockerPopoverView(viewModel: viewModel, palette: palette)
                }

                if viewModel.activeTab.isIncognito {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(palette.incognitoAccent)
                } else if let url = viewModel.activeTab.currentURL, !isAddressFocused {
                    Image(systemName: url.scheme == "https" ? "lock.fill" : "exclamationmark.triangle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(url.scheme == "https" ? palette.secondaryText : palette.shieldPaused)
                }

                TextField("Buscar en \(viewModel.settings.searchEngine.shortName) o escribir URL", text: $viewModel.addressBarText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(palette.primaryText)
                    .keyboardType(.webSearch)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .submitLabel(.go)
                    .focused($isAddressFocused)
                    .onChange(of: isAddressFocused) { focused in
                        viewModel.isEditingAddressBar = focused
                        if !focused {
                            viewModel.syncAddressBarToActiveTab()
                        }
                    }
                    .onSubmit {
                        viewModel.submitAddressOrSearch(viewModel.addressBarText)
                    }

                if isAddressFocused && !viewModel.addressBarText.isEmpty {
                    Button {
                        viewModel.addressBarText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(palette.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Borrar texto")
                } else if !viewModel.activeTab.isStartPage {
                    Button {
                        viewModel.reloadOrStop()
                    } label: {
                        Image(systemName: viewModel.activeTab.isLoading ? "xmark" : "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(palette.secondaryText)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("r", modifiers: .command)
                    .accessibilityLabel(viewModel.activeTab.isLoading ? "Detener carga" : "Recargar página")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .frame(maxWidth: 560)
            .background(palette.addressBarBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isAddressFocused ? palette.accent : palette.border, lineWidth: isAddressFocused ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(maxWidth: .infinity)

            // Right utility controls
            HStack(spacing: 2) {
                if !viewModel.activeTab.isStartPage {
                    if viewModel.activeTab.hasVideoOnPage {
                        ToolbarIconButton(
                            systemName: "arrow.up.left.and.arrow.down.right",
                            accessibilityLabel: "Vídeo en pantalla completa",
                            isEnabled: true,
                            tintOverride: palette.accent,
                            palette: palette
                        ) {
                            viewModel.triggerNativeVideoFullscreen()
                        }
                    }

                    ToolbarIconButton(
                        systemName: "translate",
                        accessibilityLabel: "Traducir página al español",
                        isEnabled: viewModel.activeTab.currentURL != nil,
                        tintOverride: palette.accent,
                        palette: palette
                    ) {
                        if let pageURL = viewModel.activeTab.currentURL,
                           let encodedURL = pageURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                           let translateURL = URL(string: "https://translate.google.com/translate?sl=auto&tl=es&u=\(encodedURL)") {
                            viewModel.createNewTab(url: translateURL, isIncognito: viewModel.activeTab.isIncognito)
                        }
                    }

                    ToolbarIconButton(
                        systemName: viewModel.isCurrentPageBookmarked ? "star.fill" : "star",
                        accessibilityLabel: viewModel.isCurrentPageBookmarked ? "Quitar favorito" : "Añadir a favoritos",
                        isEnabled: true,
                        tintOverride: viewModel.isCurrentPageBookmarked ? Color(hex: "#F59E0B") : nil,
                        palette: palette
                    ) {
                        viewModel.toggleBookmarkForActiveTab()
                    }

                    if !isCompactWidth {
                        ToolbarIconButton(
                            systemName: viewModel.activeTab.isDesktopMode ? "desktopcomputer" : "ipad",
                            accessibilityLabel: "Alternar versión de escritorio",
                            isEnabled: true,
                            tintOverride: viewModel.activeTab.isDesktopMode ? palette.accent : nil,
                            palette: palette
                        ) {
                            viewModel.toggleDesktopMode()
                        }
                    }

                    ToolbarIconButton(
                        systemName: "square.and.arrow.up",
                        accessibilityLabel: "Compartir página",
                        isEnabled: viewModel.activeTab.currentURL != nil,
                        palette: palette
                    ) {
                        viewModel.shareFileURL = nil
                        viewModel.showShareSheet = true
                    }
                }

                // Force Dark Web Pages toggle
                ToolbarIconButton(
                    systemName: viewModel.settings.forceDarkWebPages ? "moon.fill" : "moon",
                    accessibilityLabel: "Forzar modo oscuro en páginas web",
                    isEnabled: true,
                    tintOverride: viewModel.settings.forceDarkWebPages ? palette.accent : nil,
                    palette: palette
                ) {
                    viewModel.toggleForceDarkWebPages()
                }

                // Downloads button with active badge
                Button {
                    viewModel.showDownloads = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: viewModel.activeTab.detectedVideoURLString != nil ? "arrow.down.circle.fill" : "arrow.down.circle")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(
                                (downloadManager.activeDownloadsCount > 0 || viewModel.activeTab.detectedVideoURLString != nil)
                                    ? palette.accent
                                    : palette.primaryText.opacity(0.88)
                            )
                            .frame(width: 34, height: 34)

                        if downloadManager.activeDownloadsCount > 0 {
                            Text("\(downloadManager.activeDownloadsCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(palette.accent)
                                .clipShape(Capsule())
                                .offset(x: 2, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Descargas")

                ToolbarIconButton(
                    systemName: "plus",
                    accessibilityLabel: "Nueva pestaña",
                    isEnabled: true,
                    palette: palette
                ) {
                    viewModel.createNewTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button {
                    viewModel.showTabSwitcher = true
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(palette.primaryText.opacity(0.75), lineWidth: 1.5)
                            .frame(width: 21, height: 21)

                        Text("\(viewModel.tabs.count)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(palette.primaryText)
                    }
                    .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mostrar pestañas (\(viewModel.tabs.count))")

                ToolbarIconButton(
                    systemName: "gearshape",
                    accessibilityLabel: "Ajustes",
                    isEnabled: true,
                    palette: palette
                ) {
                    viewModel.showSettings = true
                }
            }
        }
        .padding(.horizontal, isCompactWidth ? 8 : 12)
        .frame(height: 52)
        .background(palette.chromeBackground)
    }

    private var shieldIconName: String {
        if !viewModel.settings.adBlockerEnabled {
            return "shield.slash"
        }
        return viewModel.isCurrentSiteWhitelisted ? "shield.lefthalf.filled" : "checkmark.shield.fill"
    }

    private var shieldColor: Color {
        if !viewModel.settings.adBlockerEnabled {
            return palette.secondaryText
        }
        return viewModel.isCurrentSiteWhitelisted ? palette.shieldPaused : palette.shieldActive
    }
}

private struct ToolbarIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let isEnabled: Bool
    var tintOverride: Color? = nil
    let palette: NovaPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(
                    isEnabled
                        ? (tintOverride ?? palette.primaryText.opacity(0.88))
                        : palette.secondaryText.opacity(0.35)
                )
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
}
