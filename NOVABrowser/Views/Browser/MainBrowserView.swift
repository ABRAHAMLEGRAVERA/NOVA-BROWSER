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
            let isCompact = geo.size.width < 700

            VStack(spacing: 0) {
                TopToolbarView(
                    viewModel: viewModel,
                    downloadManager: viewModel.downloadManager,
                    palette: palette,
                    isCompactWidth: isCompact,
                    isAddressFocused: $isAddressFocused
                )

                // Discrete 2pt loading progress bar
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(palette.border.opacity(0.45))
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

                TabStripView(viewModel: viewModel, palette: palette)

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
                            .id(viewModel.activeTabID)
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
                                .background(Color.black.opacity(0.82))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
