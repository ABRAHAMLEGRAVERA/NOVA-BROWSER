import Foundation
import UIKit
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
        forceDarkWebPages: Bool,
        videoPerformanceMode: Bool,
        coordinatorFactory: (UUID) -> WebViewCoordinator
    ) -> WebTabRuntime {
        if let existing = runtimes[tab.id] {
            existing.lastUsedAt = Date()
            return existing
        }

        evictIfNeeded(excluding: tab.id)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = tab.isIncognito ? incognitoDataStore : .default()
        // Present standard Safari identifier so search engines & sites do not treat NOVA as an unbranded bot WebView
        config.applicationNameForUserAgent = "Version/15.6 Safari/605.1.15"
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        // Preserve native inline/full-screen playback while avoiding unnecessary autoplay restrictions.
        config.mediaTypesRequiringUserActionForPlayback = []
        config.suppressesIncrementalRendering = false
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        if #available(iOS 15.4, *) {
            config.preferences.isElementFullscreenEnabled = true
        }

        let webpagePrefs = WKWebpagePreferences()
        webpagePrefs.allowsContentJavaScript = true
        webpagePrefs.preferredContentMode = tab.isDesktopMode ? .desktop : .recommended
        config.defaultWebpagePreferences = webpagePrefs

        let coordinator = coordinatorFactory(tab.id)
        let weakHandler = WeakScriptMessageHandler(delegate: coordinator)
        let userContent = WKUserContentController()
        userContent.add(weakHandler, name: "novaTracker")
        userContent.add(weakHandler, name: "novaVideo")
        userContent.add(weakHandler, name: "novaPageEvent")
        userContent.addUserScript(Self.makeVideoAndFullscreenEarlyScript(videoPerformanceMode: videoPerformanceMode))
        userContent.addUserScript(Self.makeShieldAndVideoEndScript(
            forceDarkWebPages: forceDarkWebPages,
            videoPerformanceMode: videoPerformanceMode
        ))

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
        // Keep the legacy iPad renderer responsive and avoid extra transparent compositing layers.
        webView.scrollView.delaysContentTouches = false
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        // Opaque rendering eliminates full-screen alpha-blending overhead on iPad Air 2 A8X GPU
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
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

    func applyForceDarkMode(_ enabled: Bool) {
        let js = Self.forceDarkModeToggleJS(enabled: enabled)
        for (_, runtime) in runtimes {
            let controller = runtime.webView.configuration.userContentController
            let currentScripts = controller.userScripts
            let kept = currentScripts.filter { !$0.source.contains("window.__novaDarkScript") }
            controller.removeAllUserScripts()
            for script in kept {
                controller.addUserScript(script)
            }
            controller.addUserScript(
                WKUserScript(
                    source: "window.__novaDarkScript = true; \(js)",
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: false
                )
            )
            runtime.webView.evaluateJavaScript(js, completionHandler: nil)
        }
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

    private static func makeVideoAndFullscreenEarlyScript(videoPerformanceMode: Bool) -> WKUserScript {
        let perfFlag = videoPerformanceMode ? "true" : "false"
        let js = """
        (function() {
            if (window.__novaVideoEarly) return;
            window.__novaVideoEarly = true;

            try {
                if (typeof Document !== 'undefined') {
                    if (!document.fullscreenEnabled) {
                        Object.defineProperty(Document.prototype, 'fullscreenEnabled', {
                            get: function() { return true; },
                            configurable: true
                        });
                    }
                    if (!document.webkitFullscreenEnabled) {
                        Object.defineProperty(Document.prototype, 'webkitFullscreenEnabled', {
                            get: function() { return true; },
                            configurable: true
                        });
                    }
                }
            } catch (e) {}

            function findBestVideo(root) {
                var base = root && root.tagName === 'VIDEO' ? root : null;
                if (base) return base;
                var scope = (root && root.querySelectorAll) ? root : document;
                var videos = scope.querySelectorAll('video');
                if (!videos || videos.length === 0) {
                    videos = document.querySelectorAll('video');
                }
                var best = null;
                var bestScore = -1;
                for (var i = 0; i < videos.length; i++) {
                    var v = videos[i];
                    var rect = v.getBoundingClientRect();
                    var area = rect.width * rect.height;
                    var score = (!v.paused ? 10000000 : 0) + (v.readyState > 0 ? 100000 : 0) + area;
                    if (score > bestScore) {
                        bestScore = score;
                        best = v;
                    }
                }
                return best;
            }

            var origReqFS = Element.prototype.requestFullscreen || Element.prototype.webkitRequestFullscreen;
            function novaEnterFullscreen() {
                var target = this;
                var video = findBestVideo(target);
                if (video && typeof video.webkitEnterFullscreen === 'function' && video.webkitSupportsFullscreen !== false) {
                    try {
                        video.webkitEnterFullscreen();
                        return Promise.resolve();
                    } catch (err) {}
                }
                if (typeof origReqFS === 'function') {
                    try {
                        var res = origReqFS.apply(target, arguments);
                        if (res && typeof res.catch === 'function') {
                            return res.catch(function() {
                                var v = findBestVideo(target);
                                if (v && typeof v.webkitEnterFullscreen === 'function') {
                                    v.webkitEnterFullscreen();
                                }
                            });
                        }
                        return res;
                    } catch (e) {
                        var v2 = findBestVideo(target);
                        if (v2 && typeof v2.webkitEnterFullscreen === 'function') {
                            v2.webkitEnterFullscreen();
                            return Promise.resolve();
                        }
                    }
                }
                return Promise.resolve();
            }

            try {
                Element.prototype.requestFullscreen = novaEnterFullscreen;
                Element.prototype.webkitRequestFullscreen = novaEnterFullscreen;
            } catch (e) {}

            window.__novaEnterVideoFullscreen = function() {
                var v = findBestVideo(document);
                if (!v) return false;
                if (typeof v.webkitEnterFullscreen === 'function') {
                    try {
                        v.webkitEnterFullscreen();
                        return true;
                    } catch (e) {}
                }
                if (typeof v.requestFullscreen === 'function') {
                    v.requestFullscreen();
                    return true;
                }
                return false;
            };

            if (\(perfFlag)) {
                var resizeTimer = null;
                function snapLayoutOnRotate() {
                    var docEl = document.documentElement;
                    if (!docEl) return;
                    docEl.classList.add('__nova-resizing');
                    clearTimeout(resizeTimer);
                    resizeTimer = setTimeout(function() {
                        docEl.classList.remove('__nova-resizing');
                    }, 220);
                }
                window.addEventListener('orientationchange', snapLayoutOnRotate, { passive: true });
                window.addEventListener('resize', snapLayoutOnRotate, { passive: true });
            }
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    private static func makeShieldAndVideoEndScript(
        forceDarkWebPages: Bool,
        videoPerformanceMode: Bool
    ) -> WKUserScript {
        let perfFlag = videoPerformanceMode ? "true" : "false"
        let darkJS = forceDarkModeToggleJS(enabled: forceDarkWebPages)
        let js = """
        (function() {
            if (window.__novaShieldInjected) return;
            window.__novaShieldInjected = true;

            function postTracker(count) {
                try {
                    if (count > 0 && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.novaTracker) {
                        window.webkit.messageHandlers.novaTracker.postMessage({ type: 'blocked', count: count });
                    }
                } catch (e) {}
            }

            function reportVideoState() {
                try {
                    if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.novaVideo) return;
                    var videos = document.querySelectorAll('video');
                    var hasVideo = videos.length > 0;
                    var directURL = null;
                    for (var i = 0; i < videos.length; i++) {
                        var v = videos[i];
                        var src = v.currentSrc || v.src || '';
                        if (!src) {
                            var sourceEl = v.querySelector('source[src]');
                            if (sourceEl) src = sourceEl.src || '';
                        }
                        if (src && src.indexOf('http') === 0 && src.indexOf('blob:') !== 0) {
                            var lower = src.toLowerCase();
                            if (lower.indexOf('.mp4') !== -1 || lower.indexOf('.m4v') !== -1 || lower.indexOf('.mov') !== -1 || lower.indexOf('.webm') !== -1 || lower.indexOf('mime=video') !== -1) {
                                directURL = src;
                                break;
                            }
                        }
                    }
                    window.webkit.messageHandlers.novaVideo.postMessage({
                        hasVideo: hasVideo,
                        directURL: directURL
                    });
                } catch (e) {}
            }

            function checkBraveWasmBlock() {
                try {
                    var h = (location.hostname || '').toLowerCase();
                    if (h !== 'search.brave.com') return;
                    var text = (document.body && document.body.innerText) ? document.body.innerText : '';
                    if (text.indexOf('WebAssembly 2.0') !== -1) {
                        var params = new URLSearchParams(location.search || '');
                        var q = params.get('q') || '';
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.novaPageEvent) {
                            window.webkit.messageHandlers.novaPageEvent.postMessage({
                                type: 'braveWasmBlocked',
                                query: q
                            });
                        }
                    }
                } catch (e) {}
            }

            if (\(perfFlag)) {
                var style = document.createElement('style');
                style.id = 'nova-perf-css';
                style.textContent = [
                    'html, body { scroll-behavior: auto !important; }',
                    'html.__nova-resizing *, html.__nova-resizing *::before, html.__nova-resizing *::after {',
                    '  transition: none !important; animation: none !important;',
                    '}',
                    '#cinematics, #cinematics-container, ytd-watch-flexy #cinematics, #ambient-container, .ytp-ce-element, ytd-moving-thumbnail-renderer {',
                    '  display: none !important;',
                    '}',
                    'ytd-app, ytm-app, #masthead-container, tp-yt-app-drawer, .mobile-topbar-header {',
                    '  backdrop-filter: none !important; -webkit-backdrop-filter: none !important;',
                    '}',
                    'ytd-rich-item-renderer, ytm-rich-item-renderer, ytm-video-with-context-renderer, ytd-compact-video-renderer {',
                    '  transition: none !important; box-shadow: none !important;',
                    '}',
                    'video { transform: translateZ(0); }'
                ].join('\\n');
                (document.head || document.documentElement).appendChild(style);
            }

            var host = (location.hostname || '').toLowerCase();
            var isYouTube = (host.indexOf('youtube.com') !== -1) && (window.top === window.self);

            function setupYouTubeAppUI() {
                if (!isYouTube) return;

                if (!document.getElementById('nova-yt-app-css')) {
                    var ytStyle = document.createElement('style');
                    ytStyle.id = 'nova-yt-app-css';
                    ytStyle.textContent = [
                        // Keep top bar clean: only 3-line menu + YouTube logo + search bar
                        'ytd-masthead #end, ytd-masthead #voice-search-button, ytd-masthead ytd-topbar-menu-button-renderer, ytd-masthead ytd-notification-topbar-button-renderer, ytd-masthead #avatar-btn {',
                        '  display: none !important;',
                        '}',
                        'ytd-masthead #center { max-width: 580px !important; margin: 0 auto !important; }',
                        'ytm-mobile-topbar-renderer .mobile-topbar-header-endpoint + *, ytm-mobile-topbar-renderer button[aria-label*="Cuenta"], ytm-mobile-topbar-renderer button[aria-label*="Account"], ytm-mobile-topbar-renderer ytm-topbar-menu-button-renderer {',
                        '  display: none !important;',
                        '}',
                        // Hide fixed mini-sidebar on desktop YouTube so iPad 9.7" gains horizontal room (drawer via 3-line menu still works)
                        'html[data-nova-yt-bar="1"] ytd-mini-guide-renderer { display: none !important; }',
                        'html[data-nova-yt-bar="1"] ytd-page-manager { margin-left: 0 !important; padding-bottom: 54px !important; }',
                        'html[data-nova-yt-bar="1"] ytm-app { padding-bottom: 54px !important; }',
                        // Hide YouTube mobile native pivot bar if present so we have one clean unified bar
                        'html[data-nova-yt-bar="1"] ytm-pivot-bar-renderer { display: none !important; }',
                        // SHORTS MODE: remove top search/logo/header completely and expand Short above compact bottom bar
                        'html[data-nova-yt-mode="shorts"], html[data-nova-yt-mode="shorts"] ytd-app { --ytd-masthead-height: 0px !important; --ytd-toolbar-height: 0px !important; }',
                        'html[data-nova-yt-mode="shorts"] #masthead-container, html[data-nova-yt-mode="shorts"] ytd-masthead, html[data-nova-yt-mode="shorts"] ytm-mobile-topbar-renderer, html[data-nova-yt-mode="shorts"] #header {',
                        '  display: none !important; height: 0 !important; min-height: 0 !important;',
                        '}',
                        'html[data-nova-yt-mode="shorts"] ytd-page-manager, html[data-nova-yt-mode="shorts"] #page-manager {',
                        '  margin-top: 0 !important; padding-top: 0 !important; padding-bottom: 48px !important;',
                        '}',
                        'html[data-nova-yt-mode="shorts"] ytd-shorts, html[data-nova-yt-mode="shorts"] #shorts-container {',
                        '  height: calc(100vh - 48px) !important; max-height: calc(100vh - 48px) !important; padding-top: 0 !important;',
                        '}',
                        // Bottom app-like navigation bar (Inicio, Shorts, Suscripciones, Tú)
                        '#nova-yt-bottom-bar {',
                        '  position: fixed; left: 0; right: 0; bottom: 0; z-index: 2147483000;',
                        '  height: calc(48px + env(safe-area-inset-bottom));',
                        '  padding-bottom: env(safe-area-inset-bottom);',
                        '  display: flex; align-items: center; justify-content: space-around;',
                        '  background: rgba(15, 15, 18, 0.96); color: #f1f5f9;',
                        '  border-top: 1px solid rgba(255, 255, 255, 0.12);',
                        '  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;',
                        '  user-select: none; -webkit-user-select: none;',
                        '}',
                        'html:not([dark]):not([data-nova-dark="1"]) #nova-yt-bottom-bar {',
                        '  background: rgba(255, 255, 255, 0.97); color: #0f172a;',
                        '  border-top: 1px solid rgba(15, 23, 42, 0.12);',
                        '}',
                        '#nova-yt-bottom-bar.nova-hidden { display: none !important; }',
                        '.nova-yt-tab {',
                        '  flex: 1; height: 48px; border: none; background: transparent; color: inherit;',
                        '  display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 2px;',
                        '  opacity: 0.68; cursor: pointer; padding: 0 6px; -webkit-tap-highlight-color: transparent;',
                        '}',
                        '.nova-yt-tab.active { opacity: 1; color: #ff2d2d; font-weight: 600; }',
                        'html:not([dark]):not([data-nova-dark="1"]) .nova-yt-tab.active { color: #dc2626; }',
                        '.nova-yt-tab svg { width: 20px; height: 20px; display: block; fill: currentColor; }',
                        '.nova-yt-tab span { font-size: 10px; line-height: 12px; letter-spacing: 0.01em; }'
                    ].join('\\n');
                    (document.head || document.documentElement).appendChild(ytStyle);
                }

                function ensureBottomBar() {
                    if (document.getElementById('nova-yt-bottom-bar')) return;
                    if (!document.body) return;

                    var bar = document.createElement('nav');
                    bar.id = 'nova-yt-bottom-bar';
                    bar.setAttribute('aria-label', 'Navegación de YouTube');

                    var tabs = [
                        {
                            key: 'home',
                            label: 'Inicio',
                            href: '/',
                            svg: '<svg viewBox="0 0 24 24"><path d="M12 3.2 3 10.4V21h6v-6h6v6h6V10.4L12 3.2z"/></svg>'
                        },
                        {
                            key: 'shorts',
                            label: 'Shorts',
                            href: '/shorts',
                            svg: '<svg viewBox="0 0 24 24"><path d="M16.7 5.2c1.2.7 1.6 2.2.9 3.4l-1.1 1.9 1.4.8c1.2.7 1.6 2.2.9 3.4l-2.6 4.4c-.7 1.2-2.2 1.6-3.4.9l-5.5-3.2c-1.2-.7-1.6-2.2-.9-3.4l1.1-1.9-1.4-.8c-1.2-.7-1.6-2.2-.9-3.4l2.6-4.4c.7-1.2 2.2-1.6 3.4-.9l5.5 3.2zM10 9.5v5l4.5-2.5L10 9.5z"/></svg>'
                        },
                        {
                            key: 'subs',
                            label: 'Suscripciones',
                            href: '/feed/subscriptions',
                            svg: '<svg viewBox="0 0 24 24"><path d="M4 6h16v2H4V6zm2-4h12v2H6V2zm14 8H4c-1.1 0-2 .9-2 2v8c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2v-8c0-1.1-.9-2-2-2zm-10 9v-6l5.5 3-5.5 3z"/></svg>'
                        },
                        {
                            key: 'you',
                            label: 'Tú',
                            href: '/feed/you',
                            svg: '<svg viewBox="0 0 24 24"><path d="M12 12c2.7 0 4.8-2.1 4.8-4.8S14.7 2.4 12 2.4 7.2 4.5 7.2 7.2 9.3 12 12 12zm0 2.4c-3.2 0-9.6 1.6-9.6 4.8V21h19.2v-1.8c0-3.2-6.4-4.8-9.6-4.8z"/></svg>'
                        }
                    ];

                    function navigateYouTubeSPA(targetHref) {
                        var selectors = [];
                        if (targetHref === '/') {
                            selectors = ['a#endpoint[href="/"]', 'ytd-mini-guide-entry-renderer a[href="/"]', 'a[title="Inicio"]', 'a[title="Home"]'];
                        } else if (targetHref === '/shorts') {
                            selectors = ['a#endpoint[href="/shorts"]', 'ytd-mini-guide-entry-renderer a[title="Shorts"]', 'a[title="Shorts"]'];
                        } else if (targetHref === '/feed/subscriptions') {
                            selectors = ['a#endpoint[href="/feed/subscriptions"]', 'a[title="Suscripciones"]', 'a[title="Subscriptions"]'];
                        } else {
                            selectors = ['a#endpoint[href="/feed/you"]', 'a#endpoint[href="/feed/library"]', 'a[title="Tú"]', 'a[title="You"]'];
                        }
                        for (var i = 0; i < selectors.length; i++) {
                            var link = document.querySelector(selectors[i]);
                            if (link) {
                                link.click();
                                setTimeout(syncYouTubeMode, 120);
                                return;
                            }
                        }
                        location.href = targetHref;
                    }

                    for (var i = 0; i < tabs.length; i++) {
                        (function(t) {
                            var btn = document.createElement('button');
                            btn.type = 'button';
                            btn.className = 'nova-yt-tab';
                            btn.dataset.ytTab = t.key;
                            btn.innerHTML = t.svg + '<span>' + t.label + '</span>';
                            btn.addEventListener('click', function() {
                                navigateYouTubeSPA(t.href);
                            });
                            bar.appendChild(btn);
                        })(tabs[i]);
                    }
                    document.body.appendChild(bar);
                }

                function syncYouTubeMode() {
                    ensureBottomBar();
                    var root = document.documentElement;
                    var path = (location.pathname || '/').toLowerCase();
                    var isShorts = path.indexOf('/shorts') === 0;
                    var isWatch = path.indexOf('/watch') === 0;

                    var mode = isShorts ? 'shorts' : (isWatch ? 'watch' : 'browse');
                    root.setAttribute('data-nova-yt-mode', mode);

                    var bar = document.getElementById('nova-yt-bottom-bar');
                    if (isWatch) {
                        root.removeAttribute('data-nova-yt-bar');
                        if (bar) bar.classList.add('nova-hidden');
                    } else {
                        root.setAttribute('data-nova-yt-bar', '1');
                        if (bar) bar.classList.remove('nova-hidden');
                    }

                    if (bar) {
                        var activeKey = 'home';
                        if (isShorts) activeKey = 'shorts';
                        else if (path.indexOf('/feed/subscriptions') === 0) activeKey = 'subs';
                        else if (path.indexOf('/feed/you') === 0 || path.indexOf('/feed/library') === 0 || path.indexOf('/feed/history') === 0 || path.indexOf('/playlist') === 0) activeKey = 'you';

                        var btns = bar.querySelectorAll('.nova-yt-tab');
                        for (var i = 0; i < btns.length; i++) {
                            if (btns[i].dataset.ytTab === activeKey) {
                                btns[i].classList.add('active');
                            } else {
                                btns[i].classList.remove('active');
                            }
                        }
                    }
                }

                syncYouTubeMode();
                window.addEventListener('yt-navigate-finish', syncYouTubeMode);
                window.addEventListener('popstate', syncYouTubeMode);

                var lastHref = location.href;
                setInterval(function() {
                    if (location.href !== lastHref) {
                        lastHref = location.href;
                        syncYouTubeMode();
                        setTimeout(reportVideoState, 350);
                    }
                }, 450);
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
                if (count > 0) postTracker(count);
            }

            if (isYouTube) {
                if (document.body) {
                    setupYouTubeAppUI();
                } else {
                    document.addEventListener('DOMContentLoaded', setupYouTubeAppUI);
                }

                var ytScheduled = false;
                function checkYouTubeAds() {
                    ytScheduled = false;
                    try {
                        var skipBtn = document.querySelector('.ytp-ad-skip-button, .ytp-skip-ad-button, .ytp-ad-skip-button-modern');
                        if (skipBtn && skipBtn.offsetParent !== null) {
                            skipBtn.click();
                            postTracker(1);
                        }
                        var overlayClose = document.querySelector('.ytp-ad-overlay-close-button');
                        if (overlayClose) {
                            overlayClose.click();
                            postTracker(1);
                        }
                    } catch (e) {}
                }
                var observer = new MutationObserver(function() {
                    if (!ytScheduled) {
                        ytScheduled = true;
                        setTimeout(checkYouTubeAds, 350);
                    }
                });
                if (document.body) {
                    observer.observe(document.body, { childList: true, subtree: true });
                }
            }

            document.addEventListener('click', function(e) {
                var btn = e.target && e.target.closest ? e.target.closest('.ytp-fullscreen-button, .fullscreen-icon, .ytm-fullscreen-button, button[aria-label*="Pantalla completa"], button[aria-label*="pantalla completa"], button[aria-label*="Full screen"], button[aria-label*="Fullscreen"]') : null;
                if (!btn) return;
                setTimeout(function() {
                    var inFS = !!(document.fullscreenElement || document.webkitFullscreenElement);
                    if (!inFS && typeof window.__novaEnterVideoFullscreen === 'function') {
                        window.__novaEnterVideoFullscreen();
                    }
                }, 140);
            }, true);

            window.__novaDarkScript = true;
            \(darkJS)

            sweepAdContainers();
            reportVideoState();
            checkBraveWasmBlock();
            setTimeout(function() {
                sweepAdContainers();
                reportVideoState();
                checkBraveWasmBlock();
            }, 900);
            document.addEventListener('loadedmetadata', reportVideoState, true);
            document.addEventListener('playing', reportVideoState, true);
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }

    static func forceDarkModeToggleJS(enabled: Bool) -> String {
        let flag = enabled ? "true" : "false"
        return """
        (function() {
            var enable = \(flag);
            var existing = document.getElementById('nova-force-dark-css');
            var root = document.documentElement;
            if (!root) return;
            var host = (location.hostname || '').toLowerCase();
            var isDesktopYT = host.indexOf('youtube.com') !== -1 && !!document.querySelector('ytd-app');

            if (!enable) {
                if (existing) existing.remove();
                root.removeAttribute('data-nova-dark');
                if (root.dataset.novaYtDark === '1') {
                    root.removeAttribute('dark');
                    root.style.colorScheme = '';
                    delete root.dataset.novaYtDark;
                }
                return;
            }

            if (isDesktopYT) {
                if (existing) existing.remove();
                root.removeAttribute('data-nova-dark');
                root.setAttribute('dark', 'true');
                root.style.colorScheme = 'dark';
                root.dataset.novaYtDark = '1';
                return;
            }

            if (!existing) {
                var style = document.createElement('style');
                style.id = 'nova-force-dark-css';
                style.textContent = [
                    'html[data-nova-dark="1"] { color-scheme: dark !important; background: #111318 !important; filter: invert(0.92) hue-rotate(180deg) !important; }',
                    'html[data-nova-dark="1"] img, html[data-nova-dark="1"] video, html[data-nova-dark="1"] picture, html[data-nova-dark="1"] canvas, html[data-nova-dark="1"] iframe, html[data-nova-dark="1"] .ytm-media-item-thumbnail-renderer, html[data-nova-dark="1"] [style*="background-image"] { filter: invert(1) hue-rotate(180deg) !important; }'
                ].join('\\n');
                (document.head || root).appendChild(style);
            }
            root.setAttribute('data-nova-dark', '1');
        })();
        """
    }
}
