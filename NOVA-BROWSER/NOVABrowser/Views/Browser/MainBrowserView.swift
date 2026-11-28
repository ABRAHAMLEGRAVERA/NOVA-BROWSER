import SwiftUI

struct MainBrowserView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isAddressFocused: Bool

    private var effectiveColorScheme: ColorScheme {
        switch viewModel.settings.appearanceMode {
        case .automatic: return systemColorScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var palette: NovaPalette {
        NovaPalette.resolve(
            colorScheme: effectiveColorScheme,
            isIncognito: viewModel.activeTab.isIncognito
        )
    }

    var body: some View {
        GeometryReader { geo in
            let isCompact = geo.size.width < 680

            VStack(spacing: 0) {
                TopToolbarView(
                    viewModel: viewModel,
                    downloadManager: viewModel.downloadManager,
                    palette: palette,
                    viewportWidth: geo.size.width,
                    isAddressFocused: $isAddressFocused
                )

                // Discrete 2pt loading progress bar
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(palette.border.opacity(0.4))
                        .frame(height: 2)

                    if viewModel.activeTab.isLoading {
                        Rectangle()
                            .fill(palette.accent)
                            .frame(
                                width: max(24, geo.size.width * CGFloat(viewModel.activeTab.estimatedProgress)),
                                height: 2
                            )
                    }
                }

                TabStripView(
                    viewModel: viewModel,
                    palette: palette,
                    isCompactWidth: isCompact
                )

                // Main Viewport
                ZStack(alignment: .top) {
                    if viewModel.activeTab.isStartPage {
                        StartPageView(
                            viewModel: viewModel,
                            palette: palette,
                            isIncognito: viewModel.activeTab.isIncognito
                        )
                    } else {
                        WebViewRepresentable(viewModel: viewModel, tab: viewModel.activeTab)
                            .background(palette.canvasBackground)
                    }

                    if let errorMsg = viewModel.activeTab.errorMessage, !viewModel.activeTab.isStartPage {
                        ConnectionErrorView(
                            errorMessage: errorMsg,
                            failedURL: viewModel.activeTab.failedURLString,
                            palette: palette,
                            canGoBack: viewModel.activeTab.canGoBack,
                            onRetry: { viewModel.reloadOrStop() },
                            onBack: { viewModel.goBack() },
                            onHome: { viewModel.goHome() }
                        )
                    }

                    // Active Translation Status Pill
                    if (viewModel.activeTab.isTranslating || viewModel.activeTab.isPageTranslated) && !viewModel.activeTab.isStartPage {
                        translationBanner
                            .padding(.top, 8)
                    }

                    // Save Password Prompt Card
                    if let pending = viewModel.activeTab.pendingCredentialSave, !viewModel.activeTab.isStartPage {
                        saveCredentialBanner(pending)
                            .padding(.horizontal, 16)
                            .padding(.top, (viewModel.activeTab.isPageTranslated || viewModel.activeTab.isTranslating) ? 52 : 10)
                    }

                    if isAddressFocused {
                        Color.black.opacity(0.18)
                            .ignoresSafeArea()
                            .onTapGesture {
                                isAddressFocused = false
                            }

                        AddressSuggestionsView(viewModel: viewModel, palette: palette)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }

                    if let toast = viewModel.toastMessage {
                        VStack {
                            Spacer()
                            Text(toast)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(Color.black.opacity(0.84))
                                .clipShape(Capsule())
                                .padding(.bottom, 24)
                        }
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(palette.canvasBackground)
        }
        .preferredColorScheme(viewModel.resolvedColorScheme)
        .background(keyboardShortcutsLayer)
        .onChange(of: viewModel.focusAddressBarTrigger) { _ in
            isAddressFocused = true
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background || phase == .inactive {
                viewModel.persistTabsSnapshot()
                viewModel.flushPendingSettings()
                viewModel.flushCookiesToDisk(force: true)
            }
        }
        .sheet(isPresented: $viewModel.showTabSwitcher) {
            TabSwitcherView(viewModel: viewModel, palette: palette)
                .preferredColorScheme(viewModel.resolvedColorScheme)
        }
        .sheet(isPresented: $viewModel.showLibrary) {
            LibrarySheetView(viewModel: viewModel)
                .preferredColorScheme(viewModel.resolvedColorScheme)
        }
        .sheet(isPresented: $viewModel.showPasswords) {
            PasswordsSheetView(viewModel: viewModel, passwordStore: viewModel.passwordStore)
                .preferredColorScheme(viewModel.resolvedColorScheme)
        }
        .sheet(isPresented: $viewModel.showDownloads) {
            DownloadsSheetView(viewModel: viewModel, downloadManager: viewModel.downloadManager)
                .preferredColorScheme(viewModel.resolvedColorScheme)
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(viewModel: viewModel)
                .preferredColorScheme(viewModel.resolvedColorScheme)
        }
        .sheet(isPresented: $viewModel.showShortcutEditor) {
            ShortcutEditorSheet(shortcut: viewModel.editingShortcut) { id, title, urlString, colorHex in
                viewModel.saveShortcut(id: id, title: title, urlString: urlString, colorHex: colorHex)
            }
            .preferredColorScheme(viewModel.resolvedColorScheme)
        }
        .sheet(isPresented: $viewModel.showShareSheet) {
            if let fileURL = viewModel.shareFileURL {
                ShareSheetView(activityItems: [fileURL])
            } else if let url = viewModel.activeTab.currentURL {
                ShareSheetView(activityItems: [url])
            }
        }
    }

    private var translationBanner: some View {
        HStack(spacing: 10) {
            if viewModel.activeTab.isTranslating {
                ProgressView()
                    .scaleEffect(0.75)
                Text("Traduciendo página...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(palette.primaryText)
            } else if let langName = viewModel.activeTab.translatedLanguageName {
                Image(systemName: "character.bubble.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(palette.accent)
                Text("Traducido a \(langName)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(palette.primaryText)
                Button("Ver original") {
                    viewModel.restoreOriginalPage()
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(palette.accent)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(palette.chromeBackground)
        .overlay(
            Capsule()
                .stroke(palette.border, lineWidth: 0.8)
        )
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
    }

    private func saveCredentialBanner(_ pending: PendingCredentialSave) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(palette.accent.opacity(0.16))
                    .frame(width: 34, height: 34)
                Image(systemName: "key.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(palette.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("¿Guardar contraseña para \(pending.domain)?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(palette.primaryText)
                    .lineLimit(1)
                Text(pending.username)
                    .font(.system(size: 12))
                    .foregroundColor(palette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button("Ahora no") {
                viewModel.dismissPendingCredential()
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(palette.secondaryText)
            .buttonStyle(.plain)

            Button("Guardar") {
                viewModel.savePendingCredential()
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(palette.accent)
            .foregroundColor(.white)
            .clipShape(Capsule())
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: 520)
        .background(palette.chromeBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.border, lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 4)
    }

    private var keyboardShortcutsLayer: some View {
        Group {
            Button("") { isAddressFocused = true }
                .keyboardShortcut("l", modifiers: .command)
            Button("") { viewModel.closeTab(viewModel.activeTabID) }
                .keyboardShortcut("w", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}
