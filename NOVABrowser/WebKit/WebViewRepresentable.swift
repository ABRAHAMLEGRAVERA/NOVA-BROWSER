import SwiftUI
import UIKit
import WebKit

final class WebViewHostContainer: UIView {
    weak var currentWebView: WKWebView?

    func display(webView: WKWebView) {
        if currentWebView === webView { return }
        currentWebView?.removeFromSuperview()
        currentWebView = webView

        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
}

final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let tabID: UUID
    private weak var viewModel: BrowserViewModel?
    private let adBlockFilter: AdBlockQuickFilter

    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var progressObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    private var canGoBackObservation: NSKeyValueObservation?
    private var canGoForwardObservation: NSKeyValueObservation?

    init(tabID: UUID, viewModel: BrowserViewModel, adBlockFilter: AdBlockQuickFilter) {
        self.tabID = tabID
        self.viewModel = viewModel
        self.adBlockFilter = adBlockFilter
        super.init()
    }

    deinit {
        invalidateObservers()
    }

    func attachObservers(to webView: WKWebView) {
        invalidateObservers()
        let currentTabID = self.tabID

        titleObservation = webView.observe(\.title, options: [.new]) { [weak self] view, _ in
            let title = view.title
            Task { @MainActor in
                self?.viewModel?.handleWebViewTitleChange(tabID: currentTabID, title: title)
            }
        }

        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] view, _ in
            let url = view.url
            Task { @MainActor in
                self?.viewModel?.handleWebViewURLChange(tabID: currentTabID, url: url)
            }
        }

        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
            let progress = view.estimatedProgress
            Task { @MainActor in
                self?.viewModel?.handleWebViewProgress(tabID: currentTabID, progress: progress)
            }
        }

        loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
            let isLoading = view.isLoading
            Task { @MainActor in
                self?.viewModel?.handleWebViewLoading(tabID: currentTabID, isLoading: isLoading)
            }
        }

        canGoBackObservation = webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
            let canBack = view.canGoBack
            let canFwd = view.canGoForward
            Task { @MainActor in
                self?.viewModel?.handleWebViewHistoryFlags(tabID: currentTabID, canGoBack: canBack, canGoForward: canFwd)
            }
        }

        canGoForwardObservation = webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
            let canBack = view.canGoBack
            let canFwd = view.canGoForward
            Task { @MainActor in
                self?.viewModel?.handleWebViewHistoryFlags(tabID: currentTabID, canGoBack: canBack, canGoForward: canFwd)
            }
        }
    }

    func invalidateObservers() {
        titleObservation?.invalidate()
        urlObservation?.invalidate()
        progressObservation?.invalidate()
        loadingObservation?.invalidate()
        canGoBackObservation?.invalidate()
        canGoForwardObservation?.invalidate()

        titleObservation = nil
        urlObservation = nil
        progressObservation = nil
        loadingObservation = nil
        canGoBackObservation = nil
        canGoForwardObservation = nil
    }

    // MARK: - WKScriptMessageHandler
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "novaTracker",
              let body = message.body as? [String: Any],
              let count = body["count"] as? Int,
              count > 0 else {
            return
        }
        let currentTabID = self.tabID
        Task { @MainActor in
            self.viewModel?.recordBlockedItems(tabID: currentTabID, count: count)
        }
    }

    // MARK: - WKNavigationDelegate
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // Handle external schemes (mailto:, tel:, etc.) safely
        if !URLResolver.isWebScheme(url) {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            decisionHandler(.cancel)
            return
        }

        let currentTabID = self.tabID
        let currentHost = webView.url?.host
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if adBlockFilter.shouldBlockNavigationURL(url, currentHost: currentHost, isMainFrame: isMainFrame) {
            Task { @MainActor in
                self.viewModel?.recordBlockedItems(tabID: currentTabID, count: 1)
            }
            decisionHandler(.cancel)
            return
        }

        // If targetFrame is nil (e.g. target="_blank"), open in a new tab inside NOVA Browser
        if navigationAction.targetFrame == nil {
            Task { @MainActor in
                self.viewModel?.openLinkInNewTab(url: url, inheritIncognitoFrom: currentTabID)
            }
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let currentTabID = self.tabID
        Task { @MainActor in
            self.viewModel?.handleDidStartNavigation(tabID: currentTabID)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let currentTabID = self.tabID
        let title = webView.title
        let url = webView.url
        Task { @MainActor in
            self.viewModel?.handleDidFinishNavigation(tabID: currentTabID, url: url, title: title)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadError(error, failingURL: webView.url)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadError(error, failingURL: webView.url)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Recover gracefully if WebKit process crashes on low RAM on iPad Air 2
        webView.reload()
    }

    private func handleLoadError(_ error: Error, failingURL: URL?) {
        let nsError = error as NSError
        // Ignore expected cancellations (user stopped loading or fast redirect)
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        // Ignore WebKit frame load interrupted by policy change (e.g. opening new tab or download)
        if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 {
            return
        }
        let failedString = (nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String) ?? failingURL?.absoluteString
        let message = error.localizedDescription
        let currentTabID = self.tabID
        Task { @MainActor in
            self.viewModel?.handleDidFailNavigation(tabID: currentTabID, message: message, failedURLString: failedString)
        }
    }

    // MARK: - WKUIDelegate
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let targetURL = navigationAction.request.url
        let sourceHost = webView.url?.host
        let currentTabID = self.tabID

        if adBlockFilter.shouldBlockPopupURL(targetURL, sourceHost: sourceHost) {
            Task { @MainActor in
                self.viewModel?.recordBlockedItems(tabID: currentTabID, count: 1)
            }
            return nil
        }

        if let url = targetURL, url.absoluteString != "about:blank" {
            Task { @MainActor in
                self.viewModel?.openLinkInNewTab(url: url, inheritIncognitoFrom: currentTabID)
            }
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        presentAlert(title: frame.request.url?.host ?? "NOVA Browser", message: message, style: .alert, completion: {
            completionHandler()
        })
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let presenter = topMostViewController() else {
            completionHandler(false)
            return
        }
        let alert = UIAlertController(title: frame.request.url?.host ?? "Confirmar", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in completionHandler(true) })
        presenter.present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        guard let presenter = topMostViewController() else {
            completionHandler(nil)
            return
        }
        let alert = UIAlertController(title: frame.request.url?.host ?? "Entrada", message: prompt, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = defaultText
        }
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        presenter.present(alert, animated: true)
    }

    private func presentAlert(title: String, message: String, style: UIAlertController.Style, completion: @escaping () -> Void) {
        guard let presenter = topMostViewController() else {
            completion()
            return
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: style)
        alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in completion() })
        presenter.present(alert, animated: true)
    }

    private func topMostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let root = scenes.first(where: { $0.activationState == .foregroundActive })?.windows.first(where: { $0.isKeyWindow })?.rootViewController
            ?? scenes.first?.windows.first?.rootViewController
        var current = root
        while let presented = current?.presentedViewController {
            current = presented
        }
        return current
    }
}

struct WebViewRepresentable: UIViewRepresentable {
    @ObservedObject var viewModel: BrowserViewModel
    let tab: BrowserTab

    func makeUIView(context: Context) -> WebViewHostContainer {
        WebViewHostContainer()
    }

    func updateUIView(_ uiView: WebViewHostContainer, context: Context) {
        let runtime = viewModel.ensureRuntime(for: tab)
        uiView.display(webView: runtime.webView)

        if !runtime.hasLoadedInitialURL, let url = tab.currentURL {
            runtime.hasLoadedInitialURL = true
            var request = URLRequest(url: url)
            request.cachePolicy = .useProtocolCachePolicy
            runtime.webView.load(request)
        }
    }
}
