import SwiftUI

struct TopToolbarView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @ObservedObject var downloadManager: DownloadManager
    let palette: NovaPalette
    let viewportWidth: CGFloat
    @FocusState.Binding var isAddressFocused: Bool

    private var isNarrowSplit: Bool { viewportWidth < 500 }
    private var isMediumSplit: Bool { viewportWidth < 720 }

    var body: some View {
        HStack(spacing: isNarrowSplit ? 4 : 8) {
            // Left Safari-style navigation cluster
            HStack(spacing: isNarrowSplit ? 0 : 2) {
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

                if !isNarrowSplit {
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
            }

            // Center Safari-style pill address & search bar
            HStack(spacing: 7) {
                Button {
                    viewModel.showAdBlockPopover.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: shieldIconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(shieldColor)

                        if viewModel.activeTab.blockedCount > 0 && viewModel.settings.adBlockerEnabled && !isNarrowSplit {
                            Text("\(viewModel.activeTab.blockedCount)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(shieldColor)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(shieldColor.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Estado del bloqueador de anuncios")
                .popover(isPresented: $viewModel.showAdBlockPopover) {
                    AdBlockerPopoverView(viewModel: viewModel, palette: palette)
                }

                if viewModel.activeTab.isIncognito {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(palette.incognitoAccent)
                } else if let url = viewModel.activeTab.currentURL, !isAddressFocused {
                    Image(systemName: url.scheme == "https" ? "lock.fill" : "exclamationmark.triangle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(url.scheme == "https" ? palette.secondaryText : palette.shieldPaused)
                }

                TextField(
                    isNarrowSplit ? "Buscar o URL" : "Buscar en Google o escribir URL",
                    text: $viewModel.addressBarText
                )
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
            .frame(maxWidth: 540)
            .background(palette.addressBarBackground)
            .overlay(
                Capsule()
                    .stroke(isAddressFocused ? palette.accent : palette.border.opacity(0.8), lineWidth: isAddressFocused ? 1.5 : 0.6)
            )
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)

            // Right utility controls
            HStack(spacing: isNarrowSplit ? 0 : 2) {
                if !viewModel.activeTab.isStartPage && viewModel.activeTab.hasVideoOnPage {
                    ToolbarIconButton(
                        systemName: "pip.enter",
                        accessibilityLabel: "Ventana flotante (Picture in Picture)",
                        isEnabled: true,
                        tintOverride: palette.accent,
                        palette: palette
                    ) {
                        viewModel.triggerPictureInPicture()
                    }

                    if !isNarrowSplit {
                        ToolbarIconButton(
                            systemName: "arrow.up.left.and.arrow.down.right",
                            accessibilityLabel: "Vídeo en pantalla completa",
                            isEnabled: true,
                            palette: palette
                        ) {
                            viewModel.triggerNativeVideoFullscreen()
                        }
                    }
                }

                if !isNarrowSplit && !viewModel.activeTab.isStartPage {
                    translateMenuButton
                }

                if !isMediumSplit {
                    ToolbarIconButton(
                        systemName: viewModel.settings.forceDarkWebPages ? "moon.fill" : "moon",
                        accessibilityLabel: "Forzar modo oscuro en páginas web",
                        isEnabled: true,
                        tintOverride: viewModel.settings.forceDarkWebPages ? palette.accent : nil,
                        palette: palette
                    ) {
                        viewModel.toggleForceDarkWebPages()
                    }
                }

                if !isNarrowSplit {
                    downloadsButton
                }

                // Tab switcher counter
                Button {
                    viewModel.showTabSwitcher = true
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(palette.primaryText.opacity(0.78), lineWidth: 1.4)
                            .frame(width: 20, height: 20)

                        Text("\(viewModel.tabs.count)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(palette.primaryText)
                    }
                    .frame(width: 32, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mostrar pestañas (\(viewModel.tabs.count))")

                // Safari-style overflow Menu (Passwords, Translate, Share, Desktop mode, Settings)
                Menu {
                    if !viewModel.activeTab.isStartPage {
                        Button {
                            viewModel.toggleBookmarkForActiveTab()
                        } label: {
                            Label(
                                viewModel.isCurrentPageBookmarked ? "Quitar favorito" : "Añadir a favoritos",
                                systemImage: viewModel.isCurrentPageBookmarked ? "star.fill" : "star"
                            )
                        }

                        if viewModel.activeTab.isPageTranslated {
                            Button {
                                viewModel.restoreOriginalPage()
                            } label: {
                                Label("Ver página original", systemImage: "arrow.uturn.backward")
                            }
                        } else {
                            Button {
                                viewModel.translateActivePage(to: viewModel.settings.defaultTranslationLanguage)
                            } label: {
                                Label(
                                    "Traducir a \(viewModel.settings.defaultTranslationLanguage.displayName)",
                                    systemImage: "character.bubble"
                                )
                            }
                        }

                        if !viewModel.matchingCredentialsForActiveTab.isEmpty {
                            ForEach(viewModel.matchingCredentialsForActiveTab) { cred in
                                Button {
                                    viewModel.fillCredential(cred)
                                } label: {
                                    Label("Rellenar (\(cred.username))", systemImage: "key.fill")
                                }
                            }
                        }

                        Button {
                            viewModel.toggleDesktopMode()
                        } label: {
                            Label(
                                viewModel.activeTab.isDesktopMode ? "Usar versión iPad" : "Versión de escritorio",
                                systemImage: viewModel.activeTab.isDesktopMode ? "ipad" : "desktopcomputer"
                            )
                        }

                        if viewModel.activeTab.currentURL != nil {
                            Button {
                                viewModel.shareFileURL = nil
                                viewModel.showShareSheet = true
                            } label: {
                                Label("Compartir página", systemImage: "square.and.arrow.up")
                            }
                        }

                        Button {
                            viewModel.goHome()
                        } label: {
                            Label("Ir al inicio", systemImage: "house")
                        }

                        Divider()
                    }

                    Button {
                        viewModel.toggleForceDarkWebPages()
                    } label: {
                        Label(
                            viewModel.settings.forceDarkWebPages ? "Desactivar modo oscuro web" : "Modo oscuro en webs",
                            systemImage: viewModel.settings.forceDarkWebPages ? "moon.fill" : "moon"
                        )
                    }

                    Button {
                        viewModel.libraryInitialTab = .bookmarks
                        viewModel.showLibrary = true
                    } label: {
                        Label("Favoritos e historial", systemImage: "book")
                    }

                    Button {
                        viewModel.showPasswords = true
                    } label: {
                        Label("Contraseñas guardadas", systemImage: "key")
                    }

                    Button {
                        viewModel.showDownloads = true
                    } label: {
                        Label("Descargas", systemImage: "arrow.down.circle")
                    }

                    Divider()

                    Button {
                        viewModel.showSettings = true
                    } label: {
                        Label("Ajustes de NOVA", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(palette.primaryText.opacity(0.88))
                        .frame(width: 32, height: 34)
                }
                .accessibilityLabel("Más opciones")
            }
        }
        .padding(.horizontal, isNarrowSplit ? 6 : 12)
        .frame(height: 50)
        .background(palette.chromeBackground)
    }

    private var translateMenuButton: some View {
        Menu {
            if viewModel.activeTab.isPageTranslated {
                Button {
                    viewModel.restoreOriginalPage()
                } label: {
                    Label("Ver idioma original", systemImage: "arrow.uturn.backward")
                }
                Divider()
            }

            ForEach(TranslationLanguage.allCases) { lang in
                Button {
                    viewModel.translateActivePage(to: lang)
                } label: {
                    if viewModel.activeTab.translatedLanguageName == lang.displayName {
                        Label("Traducido a \(lang.displayName)", systemImage: "checkmark")
                    } else {
                        Text("Traducir a \(lang.displayName)")
                    }
                }
            }
        } label: {
            Group {
                if viewModel.activeTab.isTranslating {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: viewModel.activeTab.isPageTranslated ? "character.bubble.fill" : "character.bubble")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(viewModel.activeTab.isPageTranslated ? palette.accent : palette.primaryText.opacity(0.88))
                }
            }
            .frame(width: 32, height: 34)
        }
        .accessibilityLabel("Traducir página")
    }

    private var downloadsButton: some View {
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
                    .frame(width: 32, height: 34)

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
                .frame(width: 32, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
}
