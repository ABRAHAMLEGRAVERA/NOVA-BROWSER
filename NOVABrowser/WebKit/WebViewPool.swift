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
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
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
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        // Opaque rendering avoids expensive full-screen alpha blending on iPad Air 2 A8X GPU
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
            // Update user scripts for future page loads in live webviews
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

            // Ensure fullscreen detection succeeds on players that check standard or webkit properties
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

            // Prefer native iPad AVPlayerViewController (webkitEnterFullscreen) for video elements and video containers
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

            if (\(perfFlag)) {
                var style = document.createElement('style');
                style.id = 'nova-perf-css';
                style.textContent = [
                    'html, body { scroll-behavior: auto !important; }',
                    'html.__nova-resizing *, html.__nova-resizing *::before, html.__nova-resizing *::after {',
                    '  transition: none !important; animation: none !important;',
                    '}',
                    '#cinematics, #cinematics-container, ytd-watch-flexy #cinematics, #ambient-container, .ytp-ce-element {',
                    '  display: none !important;',
                    '}',
                    'ytd-app, ytm-app, #masthead-container, tp-yt-app-drawer, .mobile-topbar-header {',
                    '  backdrop-filter: none !important; -webkit-backdrop-filter: none !important;',
                    '}',
                    'ytd-rich-item-renderer, ytm-rich-item-renderer, ytm-video-with-context-renderer {',
                    '  transition: none !important; box-shadow: none !important;',
                    '}',
                    'video { transform: translateZ(0); }'
                ].join('\\n');
                (document.head || document.documentElement).appendChild(style);
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

            var host = (location.hostname || '').toLowerCase();
            if (host.indexOf('youtube.com') !== -1) {
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

            // Improve native video fullscreen button compatibility on YouTube mobile/desktop
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
            setTimeout(function() {
                sweepAdContainers();
                reportVideoState();
            }, 1200);
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
