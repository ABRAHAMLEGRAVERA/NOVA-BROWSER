import Combine
import Foundation
import SwiftUI
import WebKit

enum LibrarySection: String, CaseIterable, Identifiable {
    case bookmarks = "Favoritos"
    case history = "Historial"

    var id: String { rawValue }
}

@MainActor
final class BrowserViewModel: ObservableObject {
    @Published var tabs: [BrowserTab] = []
    @Published var activeTabID: UUID
    @Published var addressBarText: String = ""
    @Published var isEditingAddressBar: Bool = false
    @Published var focusAddressBarTrigger: Int = 0

    @Published var bookmarks: [BookmarkItem] = []
    @Published var history: [HistoryEntry] = []
    @Published var shortcuts: [QuickShortcut] = []
    @Published var settings: BrowserSettings

    @Published var showTabSwitcher: Bool = false
    @Published var showLibrary: Bool = false
    @Published var libraryInitialTab: LibrarySection = .bookmarks
    @Published var showSettings: Bool = false
    @Published var showAdBlockPopover: Bool = false
    @Published var showShareSheet: Bool = false
    @Published var shareFileURL: URL? = nil
    @Published var showDownloads: Bool = false
    @Published var showShortcutEditor: Bool = false
    @Published var editingShortcut: QuickShortcut? = nil
    @Published var toastMessage: String? = nil

    let adBlocker: AdBlockerEngine
    let webViewPool: WebViewPool
    let downloadManager: DownloadManager
    private let store: PersistenceStore
    private var cancellables = Set<AnyCancellable>()
    private var toastDismissWorkItem: DispatchWorkItem?

    init(store: PersistenceStore = PersistenceStore()) {
        self.store = store
        self.adBlocker = AdBlockerEngine()
        self.webViewPool = WebViewPool()
        self.downloadManager = DownloadManager()

        let loadedSettings = store.loadSettings()
        self.settings = loadedSettings
        self.bookmarks = store.loadBookmarks()
        self.history = store.loadHistory()
        self.shortcuts = store.loadShortcuts()

        if loadedSettings.restoreTabsOnLaunch,
           let snapshot = store.loadTabsSnapshot(),
           !snapshot.tabs.isEmpty {
            self.tabs = snapshot.tabs
            self.activeTabID = snapshot.activeTabID ?? snapshot.tabs[0].id
        } else {
            let initialTab = BrowserTab(
                title: "Inicio",
                urlString: loadedSettings.homePageMode == .customURL ? loadedSettings.customHomeURLString : nil,
                isDesktopMode: loadedSettings.defaultDesktopMode
            )
            self.tabs = [initialTab]
            self.activeTabID = initialTab.id
        }

        syncAddressBarToActiveTab()
        observeAdBlocker()
        adBlocker.prepareInitialRules(
            enabled: loadedSettings.adBlockerEnabled,
            whitelistedDomains: loadedSettings.whitelistedDomains
        )
    }

    var activeTab: BrowserTab {
        if let found = tabs.first(where: { $0.id == activeTabID }) {
            return found
        }
        return tabs[0]
    }

    var activeTabIndex: Int {
        tabs.firstIndex(where: { $0.id == activeTabID }) ?? 0
    }

    var normalTabsCount: Int {
        tabs.filter { !$0.isIncognito }.count
    }

    var incognitoTabsCount: Int {
        tabs.filter { $0.isIncognito }.count
    }

    var isCurrentPageBookmarked: Bool {
        guard let urlString = activeTab.urlString else { return false }
        return bookmarks.contains { $0.urlString == urlString }
    }

    var isCurrentSiteWhitelisted: Bool {
        adBlocker.isDomainWhitelisted(activeTab.currentHost, whitelistedDomains: settings.whitelistedDomains)
    }

    var resolvedColorScheme: ColorScheme? {
        switch settings.appearanceMode {
        case .automatic: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private func observeAdBlocker() {
        adBlocker.$compiledRuleList
            .receive(on: RunLoop.main)
            .sink { [weak self] ruleList in
                guard let self = self else { return }
                self.webViewPool.updateContentRuleList(
                    ruleList,
                    enabled: self.settings.adBlockerEnabled,
                    tabs: self.tabs,
                    isWhitelistedHost: { host in
                        self.adBlocker.isDomainWhitelisted(host, whitelistedDomains: self.settings.whitelistedDomains)
                    }
                )
            }
            .store(in: &cancellables)
    }

    // MARK: - WebView Runtime

    func ensureRuntime(for tab: BrowserTab) -> WebTabRuntime {
        let isWhitelisted = adBlocker.isDomainWhitelisted(tab.currentHost, whitelistedDomains: settings.whitelistedDomains)
        return webViewPool.getOrCreateRuntime(
            for: tab,
            adBlockerRuleList: adBlocker.compiledRuleList,
            adBlockerEnabled: settings.adBlockerEnabled,
            isWhitelisted: isWhitelisted,
            forceDarkWebPages: settings.forceDarkWebPages,
            videoPerformanceMode: settings.videoPerformanceMode
        ) { [weak self] tabID in
            guard let self = self else {
                fatalError("BrowserViewModel deallocated unexpectedly")
            }
            return WebViewCoordinator(tabID: tabID, viewModel: self, adBlockFilter: self.adBlocker.quickFilter)
        }
    }

    // MARK: - Navigation

    func submitAddressOrSearch(_ input: String) {
        isEditingAddressBar = false
        guard let url = URLResolver.resolveInput(input, searchEngine: settings.searchEngine) else {
            return
        }
        navigate(to: url, in: activeTabID)
    }

    func navigate(to url: URL, in targetTabID: UUID? = nil) {
        let tabID = targetTabID ?? activeTabID
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }

        tabs[idx].urlString = url.absoluteString
        tabs[idx].errorMessage = nil
        tabs[idx].failedURLString = nil
        tabs[idx].isLoading = true
        tabs[idx].estimatedProgress = 0.08
        tabs[idx].lastAccessedAt = Date()
        if tabs[idx].title == "Inicio" {
            tabs[idx].title = URLResolver.displayTitle(for: url, pageTitle: nil)
        }

        if tabID == activeTabID && !isEditingAddressBar {
            addressBarText = url.absoluteString
        }

        if let runtime = webViewPool.runtime(for: tabID) {
            runtime.hasLoadedInitialURL = true
            runtime.webView.load(URLRequest(url: url))
        }
        persistTabsSnapshot()
    }

    func goBack() {
        guard let runtime = webViewPool.runtime(for: activeTabID) else { return }
        if runtime.webView.canGoBack {
            runtime.webView.goBack()
        } else if !activeTab.isStartPage {
            goToStartPageInActiveTab()
        }
    }

    func goForward() {
        guard let runtime = webViewPool.runtime(for: activeTabID) else { return }
        if runtime.webView.canGoForward {
            runtime.webView.goForward()
        }
    }

    func reloadOrStop() {
        guard !activeTab.isStartPage else { return }
        if let runtime = webViewPool.runtime(for: activeTabID) {
            if activeTab.isLoading {
                runtime.webView.stopLoading()
                tabs[activeTabIndex].isLoading = false
                tabs[activeTabIndex].estimatedProgress = 0
            } else if activeTab.errorMessage != nil,
                      let failed = activeTab.failedURLString,
                      let url = URL(string: failed) {
                navigate(to: url, in: activeTabID)
            } else {
                tabs[activeTabIndex].errorMessage = nil
                runtime.webView.reload()
            }
        } else if let url = activeTab.currentURL {
            navigate(to: url, in: activeTabID)
        }
    }

    func goHome() {
        isEditingAddressBar = false
        switch settings.homePageMode {
        case .novaStart:
            goToStartPageInActiveTab()
        case .customURL:
            if let url = URLResolver.resolveInput(settings.customHomeURLString, searchEngine: settings.searchEngine) {
                navigate(to: url, in: activeTabID)
            } else {
                goToStartPageInActiveTab()
            }
        }
    }

    private func goToStartPageInActiveTab() {
        let idx = activeTabIndex
        webViewPool.runtime(for: activeTabID)?.webView.stopLoading()
        webViewPool.removeRuntime(for: activeTabID, remainingIncognitoCount: incognitoTabsCount)
        tabs[idx].urlString = nil
        tabs[idx].title = "Inicio"
        tabs[idx].isLoading = false
        tabs[idx].estimatedProgress = 0
        tabs[idx].canGoBack = false
        tabs[idx].canGoForward = false
        tabs[idx].errorMessage = nil
        tabs[idx].failedURLString = nil
        tabs[idx].hasVideoOnPage = false
        tabs[idx].detectedVideoURLString = nil
        addressBarText = ""
        persistTabsSnapshot()
    }

    func toggleDesktopMode() {
        let idx = activeTabIndex
        tabs[idx].isDesktopMode.toggle()
        let isDesktop = tabs[idx].isDesktopMode

        if let runtime = webViewPool.runtime(for: activeTabID) {
            runtime.webView.customUserAgent = isDesktop
                ? "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15"
                : nil
            if !activeTab.isStartPage {
                runtime.webView.reload()
            }
        }
        showToast(isDesktop ? "Modo escritorio activado" : "Modo iPad predeterminado")
        persistTabsSnapshot()
    }

    func requestAddressBarFocus() {
        focusAddressBarTrigger += 1
    }

    func toggleForceDarkWebPages() {
        settings.forceDarkWebPages.toggle()
        store.saveSettings(settings)
        webViewPool.applyForceDarkMode(settings.forceDarkWebPages)
        showToast(settings.forceDarkWebPages ? "Modo oscuro web activado" : "Modo oscuro web desactivado")
    }

    func setForceDarkWebPages(_ enabled: Bool) {
        settings.forceDarkWebPages = enabled
        store.saveSettings(settings)
        webViewPool.applyForceDarkMode(enabled)
    }

    func triggerNativeVideoFullscreen() {
        guard let runtime = webViewPool.runtime(for: activeTabID) else {
            showToast("Abre un vídeo primero")
            return
        }
        runtime.webView.evaluateJavaScript("window.__novaEnterVideoFullscreen ? window.__novaEnterVideoFullscreen() : false;") { [weak self] result, _ in
            Task { @MainActor in
                let ok = (result as? Bool) ?? false
                if !ok {
                    self?.showToast("No se detectó ningún vídeo reproducible en esta página")
                }
            }
        }
    }

    func downloadDetectedVideo() {
        guard let raw = activeTab.detectedVideoURLString, let url = URL(string: raw) else {
            showToast("Este vídeo usa streaming protegido o fragmentado")
            return
        }
        let suggested = "\(URLResolver.normalizeDomainString(activeTab.currentHost ?? "video"))-\(Int(Date().timeIntervalSince1970)).mp4"
        downloadManager.startDirectDownload(url: url, suggestedFilename: suggested)
        showDownloads = true
        showToast("Descarga iniciada")
    }

    func handleStartedWKDownload(_ download: WKDownload, url: URL?) {
        downloadManager.attachWKDownload(download, initialURL: url)
        showToast("Descargando archivo...")
    }

    func handleVideoDetection(tabID: UUID, hasVideo: Bool, directURLString: String?) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[idx].hasVideoOnPage = hasVideo
        tabs[idx].detectedVideoURLString = directURLString
    }

    // MARK: - Tabs

    func createNewTab(url: URL? = nil, isIncognito: Bool = false, select: Bool = true) {
        let initialURL: String?
        if let url = url {
            initialURL = url.absoluteString
        } else if settings.homePageMode == .customURL && !isIncognito {
            initialURL = URLResolver.resolveInput(settings.customHomeURLString, searchEngine: settings.searchEngine)?.absoluteString
        } else {
            initialURL = nil
        }

        let resolvedURL = initialURL.flatMap { URL(string: $0) }
        let newTab = BrowserTab(
            title: initialURL == nil ? (isIncognito ? "Incógnito" : "Inicio") : URLResolver.displayTitle(for: resolvedURL, pageTitle: nil),
            urlString: initialURL,
            isIncognito: isIncognito,
            isDesktopMode: settings.defaultDesktopMode
        )
        tabs.append(newTab)
        if select {
            activeTabID = newTab.id
            isEditingAddressBar = false
            syncAddressBarToActiveTab()
        }
        persistTabsSnapshot()
    }

    func openLinkInNewTab(url: URL, inheritIncognitoFrom sourceTabID: UUID) {
        let isIncognito = tabs.first(where: { $0.id == sourceTabID })?.isIncognito ?? false
        createNewTab(url: url, isIncognito: isIncognito, select: true)
    }

    func selectTab(_ tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[idx].lastAccessedAt = Date()
        activeTabID = tabID
        isEditingAddressBar = false
        syncAddressBarToActiveTab()
        persistTabsSnapshot()
    }

    func closeTab(_ tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let wasActive = (tabID == activeTabID)
        tabs.remove(at: idx)

        let remainingIncognito = tabs.filter { $0.isIncognito }.count
        webViewPool.removeRuntime(for: tabID, remainingIncognitoCount: remainingIncognito)

        if tabs.isEmpty {
            let replacement = BrowserTab(title: "Inicio", isDesktopMode: settings.defaultDesktopMode)
            tabs = [replacement]
            activeTabID = replacement.id
        } else if wasActive {
            let nextIndex = min(idx, tabs.count - 1)
            activeTabID = tabs[nextIndex].id
        }

        isEditingAddressBar = false
        syncAddressBarToActiveTab()
        persistTabsSnapshot()
    }

    func closeAllIncognitoTabs() {
        let incognitoIDs = tabs.filter { $0.isIncognito }.map { $0.id }
        for id in incognitoIDs {
            webViewPool.removeRuntime(for: id, remainingIncognitoCount: 0)
        }
        tabs.removeAll { $0.isIncognito }
        if tabs.isEmpty {
            let replacement = BrowserTab(title: "Inicio", isDesktopMode: settings.defaultDesktopMode)
            tabs = [replacement]
            activeTabID = replacement.id
        } else if !tabs.contains(where: { $0.id == activeTabID }) {
            activeTabID = tabs[0].id
        }
        syncAddressBarToActiveTab()
        persistTabsSnapshot()
        showToast("Pestañas privadas cerradas")
    }

    func closeAllTabs() {
        webViewPool.removeAllRuntimes()
        let fresh = BrowserTab(title: "Inicio", isDesktopMode: settings.defaultDesktopMode)
        tabs = [fresh]
        activeTabID = fresh.id
        isEditingAddressBar = false
        syncAddressBarToActiveTab()
        persistTabsSnapshot()
    }

    func syncAddressBarToActiveTab() {
        addressBarText = activeTab.urlString ?? ""
    }

    // MARK: - Coordinator Callbacks

    func shouldBlockNavigation(url: URL, currentHost: String?, isMainFrame: Bool) -> Bool {
        // Never block top-level user URL bar loads if the user explicitly typed a site,
        // but block known ad-redirect & third-party ad subframes.
        if isMainFrame && currentHost == nil {
            return false
        }
        return adBlocker.shouldBlockNavigationURL(
            url,
            currentHost: currentHost,
            whitelistedDomains: settings.whitelistedDomains,
            enabled: settings.adBlockerEnabled
        )
    }

    func shouldBlockPopup(url: URL?, sourceHost: String?) -> Bool {
        adBlocker.shouldBlockPopupURL(
            url,
            sourceHost: sourceHost,
            whitelistedDomains: settings.whitelistedDomains,
            enabled: settings.adBlockerEnabled
        )
    }

    func recordBlockedItems(tabID: UUID, count: Int) {
        guard count > 0 else { return }
        if let idx = tabs.firstIndex(where: { $0.id == tabID }) {
            tabs[idx].blockedCount += count
        }
        settings.totalBlockedLifetime += count
        store.saveSettings(settings)
    }

    func handleWebViewTitleChange(tabID: UUID?, title: String?) {
        guard let tabID = tabID, let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        if let clean = title?.trimmingCharacters(in: .whitespacesAndNewlines), !clean.isEmpty {
            tabs[idx].title = clean
        }
    }

    func handleWebViewURLChange(tabID: UUID?, url: URL?) {
        guard let tabID = tabID, let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        guard let url = url else { return }
        let abs = url.absoluteString
        if abs != "about:blank" {
            tabs[idx].urlString = abs
            if tabID == activeTabID && !isEditingAddressBar {
                addressBarText = abs
            }
        }
    }

    func handleWebViewProgress(tabID: UUID?, progress: Double) {
        guard let tabID = tabID, let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[idx].estimatedProgress = progress
    }

    func handleWebViewLoading(tabID: UUID?, isLoading: Bool) {
        guard let tabID = tabID, let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[idx].isLoading = isLoading
        if !isLoading {
            tabs[idx].estimatedProgress = 0
        }
    }

    func handleWebViewHistoryFlags(tabID: UUID?, canGoBack: Bool, canGoForward: Bool) {
        guard let tabID = tabID, let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[idx].canGoBack = canGoBack
        tabs[idx].canGoForward = canGoForward
    }

    func handleDidStartNavigation(tabID: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[idx].errorMessage = nil
        tabs[idx].failedURLString = nil
        tabs[idx].hasVideoOnPage = false
        tabs[idx].detectedVideoURLString = nil
        tabs[idx].isLoading = true
    }

    func handleDidFinishNavigation(tabID: UUID, url: URL?, title: String?) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[idx].isLoading = false
        tabs[idx].estimatedProgress = 0
        tabs[idx].errorMessage = nil

        if let url = url, url.absoluteString != "about:blank" {
            tabs[idx].urlString = url.absoluteString
            tabs[idx].title = URLResolver.displayTitle(for: url, pageTitle: title)
            if tabID == activeTabID && !isEditingAddressBar {
                addressBarText = url.absoluteString
            }
            if !tabs[idx].isIncognito {
                recordHistory(title: tabs[idx].title, urlString: url.absoluteString)
            }
        }

        // Re-apply content rules in case the site host changed onto/off a whitelist domain
        if let runtime = webViewPool.runtime(for: tabID) {
            let controller = runtime.webView.configuration.userContentController
            controller.removeAllContentRuleLists()
            let whitelisted = adBlocker.isDomainWhitelisted(
                tabs[idx].currentHost,
                whitelistedDomains: settings.whitelistedDomains
            )
            if settings.adBlockerEnabled && !whitelisted, let ruleList = adBlocker.compiledRuleList {
                controller.add(ruleList)
            }
        }

        persistTabsSnapshot()
    }

    func handleDidFailNavigation(tabID: UUID, message: String, failedURLString: String?) {
        guard let idx = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        tabs[idx].isLoading = false
        tabs[idx].estimatedProgress = 0
        tabs[idx].errorMessage = message
        tabs[idx].failedURLString = failedURLString ?? tabs[idx].urlString
    }

    // MARK: - Bookmarks

    func toggleBookmarkForActiveTab() {
        guard let urlString = activeTab.urlString, !urlString.isEmpty else { return }
        if let existingIdx = bookmarks.firstIndex(where: { $0.urlString == urlString }) {
            bookmarks.remove(at: existingIdx)
            store.saveBookmarks(bookmarks)
            showToast("Eliminado de favoritos")
        } else {
            let item = BookmarkItem(title: activeTab.title, urlString: urlString)
            bookmarks.insert(item, at: 0)
            store.saveBookmarks(bookmarks)
            showToast("Guardado en favoritos")
        }
    }

    func addBookmark(title: String, urlString: String) {
        guard let url = URLResolver.resolveInput(urlString, searchEngine: settings.searchEngine) else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = BookmarkItem(
            title: cleanTitle.isEmpty ? URLResolver.displayTitle(for: url, pageTitle: nil) : cleanTitle,
            urlString: url.absoluteString
        )
        bookmarks.insert(item, at: 0)
        store.saveBookmarks(bookmarks)
    }

    func updateBookmark(_ bookmark: BookmarkItem, title: String, urlString: String) {
        guard let idx = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        if let resolved = URLResolver.resolveInput(urlString, searchEngine: settings.searchEngine) {
            bookmarks[idx].urlString = resolved.absoluteString
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty {
            bookmarks[idx].title = cleanTitle
        }
        store.saveBookmarks(bookmarks)
    }

    func deleteBookmark(_ bookmark: BookmarkItem) {
        bookmarks.removeAll { $0.id == bookmark.id }
        store.saveBookmarks(bookmarks)
    }

    // MARK: - History

    private func recordHistory(title: String, urlString: String) {
        if let first = history.first, first.urlString == urlString {
            history[0].title = title
            history[0].visitedAt = Date()
        } else {
            history.insert(HistoryEntry(title: title, urlString: urlString), at: 0)
            if history.count > 500 {
                history.removeLast(history.count - 500)
            }
        }
        store.saveHistory(history)
    }

    func deleteHistoryEntry(_ entry: HistoryEntry) {
        history.removeAll { $0.id == entry.id }
        store.saveHistory(history)
    }

    func clearHistory() {
        history.removeAll()
        store.saveHistory(history)
        showToast("Historial borrado")
    }

    // MARK: - Privacy & Cookies

    func clearCookies() {
        PrivacyDataManager.clearCookies { [weak self] in
            self?.showToast("Cookies eliminadas")
        }
    }

    func clearAllBrowsingData() {
        clearHistory()
        PrivacyDataManager.clearAllBrowsingData { [weak self] in
            self?.showToast("Cookies, caché e historial borrados")
        }
    }

    // MARK: - Shortcuts

    func saveShortcut(id: UUID?, title: String, urlString: String, colorHex: String) {
        guard let resolved = URLResolver.resolveInput(urlString, searchEngine: settings.searchEngine) else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? (resolved.host ?? "Sitio") : cleanTitle

        if let id = id, let idx = shortcuts.firstIndex(where: { $0.id == id }) {
            shortcuts[idx].title = finalTitle
            shortcuts[idx].urlString = resolved.absoluteString
            shortcuts[idx].colorHex = colorHex
        } else {
            shortcuts.append(QuickShortcut(title: finalTitle, urlString: resolved.absoluteString, colorHex: colorHex))
        }
        store.saveShortcuts(shortcuts)
    }

    func deleteShortcut(_ shortcut: QuickShortcut) {
        shortcuts.removeAll { $0.id == shortcut.id }
        store.saveShortcuts(shortcuts)
    }

    // MARK: - AdBlocker & Settings

    func setAdBlockerEnabled(_ enabled: Bool) {
        settings.adBlockerEnabled = enabled
        store.saveSettings(settings)
        adBlocker.setEnabled(enabled, whitelistedDomains: settings.whitelistedDomains)
        webViewPool.updateContentRuleList(
            adBlocker.compiledRuleList,
            enabled: enabled,
            tabs: tabs,
            isWhitelistedHost: { host in
                self.adBlocker.isDomainWhitelisted(host, whitelistedDomains: self.settings.whitelistedDomains)
            }
        )
        if !activeTab.isStartPage {
            webViewPool.runtime(for: activeTabID)?.webView.reload()
        }
    }

    func toggleWhitelistForActiveSite() {
        guard let host = activeTab.currentHost else { return }
        let normalized = URLResolver.normalizeDomainString(host)
        if isCurrentSiteWhitelisted {
            removeWhitelistDomain(normalized)
            showToast("Protección activada en \(normalized)")
        } else {
            addWhitelistDomain(normalized)
            showToast("Bloqueador pausado en \(normalized)")
        }
        if !activeTab.isStartPage {
            webViewPool.runtime(for: activeTabID)?.webView.reload()
        }
    }

    func addWhitelistDomain(_ rawDomain: String) {
        let normalized = URLResolver.normalizeDomainString(rawDomain)
        guard !normalized.isEmpty, FilterListParser.isValidASCIIHostname(normalized) else { return }
        if !settings.whitelistedDomains.contains(normalized) {
            settings.whitelistedDomains.append(normalized)
            settings.whitelistedDomains.sort()
            store.saveSettings(settings)
            adBlocker.updateWhitelist(settings.whitelistedDomains, enabled: settings.adBlockerEnabled)
        }
    }

    func removeWhitelistDomain(_ domain: String) {
        let normalized = URLResolver.normalizeDomainString(domain)
        settings.whitelistedDomains.removeAll {
            URLResolver.normalizeDomainString($0) == normalized
        }
        store.saveSettings(settings)
        adBlocker.updateWhitelist(settings.whitelistedDomains, enabled: settings.adBlockerEnabled)
    }

    func refreshAdBlockerList() {
        adBlocker.refreshRemoteFilterList(
            whitelistedDomains: settings.whitelistedDomains,
            enabled: settings.adBlockerEnabled
        )
    }

    func updateSettings(_ mutate: (inout BrowserSettings) -> Void) {
        mutate(&settings)
        store.saveSettings(settings)
    }

    // MARK: - Persistence & Toast

    func persistTabsSnapshot() {
        store.saveTabsSnapshot(PersistedTabsSnapshot(tabs: tabs, activeTabID: activeTabID))
    }

    func showToast(_ message: String) {
        toastDismissWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            toastMessage = message
        }
        let workItem = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: 0.2)) {
                self?.toastMessage = nil
            }
        }
        toastDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: workItem)
    }
}
