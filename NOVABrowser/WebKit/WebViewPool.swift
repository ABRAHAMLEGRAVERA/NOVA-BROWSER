import Foundation
import WebKit

final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

final class WebTabRuntime {
    let tabID: UUID
    let isIncognito: Bool
    let webView: WKWebView
    let coordinator: WebViewCoordinator
    var lastUsedAt: Date
    var hasLoadedInitialURL: Bool = false

    init(
        tabID: UUID,
        isIncognito: Bool,
        webView: WKWebView,
        coordinator: WebViewCoordinator,
        lastUsedAt: Date = Date()
    ) {
        self.tabID = tabID
        self.isIncognito = isIncognito
        self.webView = webView
        self.coordinator = coordinator
        self.lastUsedAt = lastUsedAt
    }

    func tearDown() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.configuration.userContentController.removeAllUserScripts()
        webView.configuration.userContentController.removeAllContentRuleLists()
        coordinator.invalidateObservers()
    }
}

@MainActor
final class WebViewPool {
    static let maxLiveWebViewsForiPadAir2 = 4

    private var runtimes: [UUID: WebTabRuntime] = [:]
    private var incognitoDataStore: WKWebsiteDataStore = .nonPersistent()
    private var memoryWarningObserver: NSObjectProtocol?

    init() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.evictBackgroundWebViews(keepingActiveID: nil)
            }
        }
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func runtime(for tabID: UUID) -> WebTabRuntime? {
        runtimes[tabID]
    }

    func getOrCreateRuntime(
        for tab: BrowserTab,
        adBlockerRuleList: WKContentRuleList?,
        adBlockerEnabled: Bool,
        isWhitelisted: Bool,
        coordinatorFactory: (UUID) -> WebViewCoordinator
    ) -> WebTabRuntime {
        if let existing = runtimes[tab.id] {
            existing.lastUsedAt = Date()
            return existing
        }

        evictIfNeeded(excluding: tab.id)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = tab.isIncognito ? incognitoDataStore : .default()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webpagePrefs = WKWebpagePreferences()
        webpagePrefs.allowsContentJavaScript = true
        webpagePrefs.preferredContentMode = tab.isDesktopMode ? .desktop : .recommended
        config.defaultWebpagePreferences = webpagePrefs

        let coordinator = coordinatorFactory(tab.id)
        let userContent = WKUserContentController()
        userContent.add(WeakScriptMessageHandler(delegate: coordinator), name: "novaTracker")
        userContent.addUserScript(Self.makeShieldHelperUserScript())

        if adBlockerEnabled, !isWhitelisted, let ruleList = adBlockerRuleList {
            userContent.add(ruleList)
        }
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        if tab.isDesktopMode {
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15"
        }
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        coordinator.attachObservers(to: webView)

        let runtime = WebTabRuntime(
            tabID: tab.id,
            isIncognito: tab.isIncognito,
            webView: webView,
            coordinator: coordinator
        )
        runtimes[tab.id] = runtime
        return runtime
    }

    func updateContentRuleList(
        _ ruleList: WKContentRuleList?,
        enabled: Bool,
        tabs: [BrowserTab],
        isWhitelistedHost: (String?) -> Bool
    ) {
        for (tabID, runtime) in runtimes {
            let controller = runtime.webView.configuration.userContentController
            controller.removeAllContentRuleLists()
            guard enabled, let ruleList = ruleList else { continue }
            let tab = tabs.first(where: { $0.id == tabID })
            if !isWhitelistedHost(tab?.currentHost) {
                controller.add(ruleList)
            }
        }
    }

    func removeRuntime(for tabID: UUID, remainingIncognitoCount: Int) {
        if let runtime = runtimes.removeValue(forKey: tabID) {
            runtime.tearDown()
        }
        if remainingIncognitoCount == 0 {
            incognitoDataStore = .nonPersistent()
        }
    }

    func removeAllRuntimes() {
        for (_, runtime) in runtimes {
            runtime.tearDown()
        }
        runtimes.removeAll()
        incognitoDataStore = .nonPersistent()
    }

    func evictBackgroundWebViews(keepingActiveID activeID: UUID?) {
        let candidates = runtimes.values
            .filter { $0.tabID != activeID }
            .sorted { $0.lastUsedAt < $1.lastUsedAt }

        // On memory pressure, keep at most 1 active webview
        for candidate in candidates {
            candidate.tearDown()
            runtimes.removeValue(forKey: candidate.tabID)
        }
    }

    private func evictIfNeeded(excluding activeID: UUID) {
        while runtimes.count >= Self.maxLiveWebViewsForiPadAir2 {
            let oldest = runtimes.values
                .filter { $0.tabID != activeID }
                .min { $0.lastUsedAt < $1.lastUsedAt }
            guard let victim = oldest else { break }
            victim.tearDown()
            runtimes.removeValue(forKey: victim.tabID)
        }
    }

    private static func makeShieldHelperUserScript() -> WKUserScript {
        let js = """
        (function() {
            if (window.__novaShieldInjected) return;
            window.__novaShieldInjected = true;

            function reportBlocked(count) {
                try {
                    if (count > 0 && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.novaTracker) {
                        window.webkit.messageHandlers.novaTracker.postMessage({ type: 'blocked', count: count });
                    }
                } catch (e) {}
            }

            function sweepAdContainers() {
                var selectors = [
                    'ins.adsbygoogle',
                    '[id^="div-gpt-ad"]',
                    '.OUTBRAIN',
                    '.taboola-widget',
                    'ytd-ad-slot-renderer',
                    'ytd-promoted-sparkles-web-renderer',
                    'ytd-display-ad-renderer',
                    'ytm-promoted-sparkles-web-renderer',
                    '.ytp-ad-overlay-container'
                ];
                var count = 0;
                for (var i = 0; i < selectors.length; i++) {
                    var nodes = document.querySelectorAll(selectors[i]);
                    for (var j = 0; j < nodes.length; j++) {
                        var el = nodes[j];
                        if (!el.dataset.novaCounted) {
                            el.dataset.novaCounted = '1';
                            el.style.setProperty('display', 'none', 'important');
                            count++;
                        }
                    }
                }
                if (count > 0) reportBlocked(count);
            }

            var host = (location.hostname || '').toLowerCase();
            if (host.indexOf('youtube.com') !== -1) {
                setInterval(function() {
                    try {
                        var skipBtn = document.querySelector('.ytp-ad-skip-button, .ytp-skip-ad-button, .ytp-ad-skip-button-modern');
                        if (skipBtn) {
                            skipBtn.click();
                            reportBlocked(1);
                        }
                        var overlayClose = document.querySelector('.ytp-ad-overlay-close-button');
                        if (overlayClose) {
                            overlayClose.click();
                            reportBlocked(1);
                        }
                    } catch (e) {}
                }, 900);
            }

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', sweepAdContainers, { once: true });
            } else {
                sweepAdContainers();
            }
            setTimeout(sweepAdContainers, 1800);
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }
}
