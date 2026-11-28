import Foundation
import WebKit
import CryptoKit

final class AdBlockQuickFilter {
    private let lock = NSLock()
    private var enabled: Bool = true
    private var whitelistedDomains: [String] = []
    private var blockedDomainSet: Set<String> = []

    func update(enabled: Bool? = nil, whitelistedDomains: [String]? = nil, blockedDomains: Set<String>? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let enabled = enabled { self.enabled = enabled }
        if let whitelistedDomains = whitelistedDomains { self.whitelistedDomains = whitelistedDomains }
        if let blockedDomains = blockedDomains { self.blockedDomainSet = blockedDomains }
    }

    func appendBlockedDomains(_ domains: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        self.blockedDomainSet.formUnion(domains)
    }

    func shouldBlockNavigationURL(_ url: URL, currentHost: String?, isMainFrame: Bool) -> Bool {
        if isMainFrame && currentHost == nil {
            return false
        }
        lock.lock()
        let isEnabled = enabled
        let whitelist = whitelistedDomains
        let domainSet = blockedDomainSet
        lock.unlock()

        guard isEnabled else { return false }
        if Self.isDomainWhitelisted(currentHost, whitelistedDomains: whitelist) {
            return false
        }
        guard let targetHost = url.host?.lowercased() else { return false }
        if FilterListParser.isProtectedVideoDomain(targetHost) {
            return false
        }
        return Self.matchesBlockedDomainSet(targetHost, domainSet: domainSet)
    }

    func shouldBlockPopupURL(_ url: URL?, sourceHost: String?) -> Bool {
        lock.lock()
        let isEnabled = enabled
        let whitelist = whitelistedDomains
        let domainSet = blockedDomainSet
        lock.unlock()

        guard isEnabled else { return false }
        if Self.isDomainWhitelisted(sourceHost, whitelistedDomains: whitelist) {
            return false
        }
        guard let url = url, let host = url.host?.lowercased() else {
            return false
        }
        if FilterListParser.isProtectedVideoDomain(host) {
            return false
        }
        if Self.matchesBlockedDomainSet(host, domainSet: domainSet) {
            return true
        }
        let lowerPath = url.absoluteString.lowercased()
        let adPathTokens = ["/popunder", "/adclick", "doubleclick.net", "popads.net", "propellerads"]
        return adPathTokens.contains { lowerPath.contains($0) }
    }

    private static func isDomainWhitelisted(_ host: String?, whitelistedDomains: [String]) -> Bool {
        guard let host = host else { return false }
        let normalized = URLResolver.normalizeDomainString(host)
        return whitelistedDomains.contains { item in
            let w = URLResolver.normalizeDomainString(item)
            return normalized == w || normalized.hasSuffix(".\(w)")
        }
    }

    private static func matchesBlockedDomainSet(_ host: String, domainSet: Set<String>) -> Bool {
        let clean = URLResolver.normalizeDomainString(host)
        if domainSet.contains(clean) { return true }
        // Match an explicitly blocked parent domain, but never use a guessed public suffix.
        // This prevents unrelated hosts sharing the same last two labels from being blocked.
        return domainSet.contains { blocked in
            clean == blocked || clean.hasSuffix(".\(blocked)")
        }
    }
}

@MainActor
final class AdBlockerEngine: ObservableObject {
    @Published private(set) var status: AdBlockerStatus = .idle
    @Published private(set) var compiledRuleList: WKContentRuleList?
    @Published private(set) var metadata: FilterListMetadata = .initial
    @Published private(set) var isUpdatingList: Bool = false
    @Published private(set) var lastUpdateMessage: String?

    let quickFilter = AdBlockQuickFilter()

    private var baseRules: [ContentBlockerRule] = []
    private var remoteRules: [ContentBlockerRule] = []
    private var blockedDomainSet: Set<String> = []
    private var activeCompilationHash: String?

    private let cacheDirectory: URL
    private var remoteRulesFileURL: URL {
        cacheDirectory.appendingPathComponent("remote_rules.json")
    }
    private var metadataFileURL: URL {
        cacheDirectory.appendingPathComponent("filter_metadata.json")
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.cacheDirectory = appSupport.appendingPathComponent("NOVABrowser/AdBlocker", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        loadBundledResources()
        loadCachedRemoteRules()
    }

    func prepareInitialRules(enabled: Bool, whitelistedDomains: [String]) {
        quickFilter.update(enabled: enabled, whitelistedDomains: whitelistedDomains, blockedDomains: blockedDomainSet)
        guard enabled else {
            compiledRuleList = nil
            status = .disabled
            return
        }
        compileOrLookupRules(whitelistedDomains: whitelistedDomains)
    }

    func updateWhitelist(_ whitelistedDomains: [String], enabled: Bool) {
        quickFilter.update(enabled: enabled, whitelistedDomains: whitelistedDomains)
        guard enabled else {
            compiledRuleList = nil
            status = .disabled
            return
        }
        compileOrLookupRules(whitelistedDomains: whitelistedDomains)
    }

    func setEnabled(_ enabled: Bool, whitelistedDomains: [String]) {
        quickFilter.update(enabled: enabled, whitelistedDomains: whitelistedDomains)
        if enabled {
            compileOrLookupRules(whitelistedDomains: whitelistedDomains)
        } else {
            compiledRuleList = nil
            status = .disabled
        }
    }

    func isDomainWhitelisted(_ host: String?, whitelistedDomains: [String]) -> Bool {
        guard let host = host else { return false }
        let normalized = URLResolver.normalizeDomainString(host)
        return whitelistedDomains.contains { item in
            let w = URLResolver.normalizeDomainString(item)
            return normalized == w || normalized.hasSuffix(".\(w)")
        }
    }

    func shouldBlockNavigationURL(_ url: URL, currentHost: String?, whitelistedDomains: [String], enabled: Bool) -> Bool {
        quickFilter.update(enabled: enabled, whitelistedDomains: whitelistedDomains, blockedDomains: blockedDomainSet)
        return quickFilter.shouldBlockNavigationURL(url, currentHost: currentHost, isMainFrame: false)
    }

    func shouldBlockPopupURL(_ url: URL?, sourceHost: String?, whitelistedDomains: [String], enabled: Bool) -> Bool {
        quickFilter.update(enabled: enabled, whitelistedDomains: whitelistedDomains, blockedDomains: blockedDomainSet)
        return quickFilter.shouldBlockPopupURL(url, sourceHost: sourceHost)
    }

    func refreshRemoteFilterList(whitelistedDomains: [String], enabled: Bool) {
        guard !isUpdatingList else { return }
        guard let sourceURL = URL(string: metadata.sourceURLString) else {
            lastUpdateMessage = "URL de lista de filtros no válida."
            return
        }

        isUpdatingList = true
        lastUpdateMessage = nil

        var request = URLRequest(url: sourceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 18)
        request.setValue("NOVABrowser/1.0 (iPadOS)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                Task { @MainActor in
                    self.isUpdatingList = false
                    self.lastUpdateMessage = "Sin conexión al actualizar (\(error.localizedDescription)). Se mantienen las reglas locales."
                }
                return
            }

            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let data = data,
                  let text = String(data: data, encoding: .utf8) else {
                Task { @MainActor in
                    self.isUpdatingList = false
                    self.lastUpdateMessage = "No se pudo descargar la lista. Se mantienen las reglas locales."
                }
                return
            }

            let parsed = FilterListParser.parseEasyListToWebKitRules(text)
            guard !parsed.rules.isEmpty else {
                Task { @MainActor in
                    self.isUpdatingList = false
                    self.lastUpdateMessage = "La lista descargada no contenía reglas válidas."
                }
                return
            }

            Task { @MainActor in
                self.remoteRules = parsed.rules
                self.blockedDomainSet.formUnion(parsed.adDomains)
                self.quickFilter.appendBlockedDomains(parsed.adDomains)
                self.metadata.lastUpdated = Date()
                self.metadata.usingBundledFallback = false
                self.saveCachedRemoteRules()
                self.isUpdatingList = false
                self.lastUpdateMessage = "Lista actualizada (\(parsed.rules.count) reglas adicionales)."
                if enabled {
                    self.compileOrLookupRules(whitelistedDomains: whitelistedDomains)
                }
            }
        }.resume()
    }

    private func loadBundledResources() {
        if let url = Bundle.main.url(forResource: "default_blocklist", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([ContentBlockerRule].self, from: data) {
            baseRules = decoded
        }

        if let domainsURL = Bundle.main.url(forResource: "ad_domains", withExtension: "txt"),
           let text = try? String(contentsOf: domainsURL, encoding: .utf8) {
            let domains = text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            blockedDomainSet.formUnion(domains)
        }
    }

    private func loadCachedRemoteRules() {
        if let metaData = try? Data(contentsOf: metadataFileURL),
           let decodedMeta = try? JSONDecoder().decode(FilterListMetadata.self, from: metaData) {
            metadata = decodedMeta
        }

        if let data = try? Data(contentsOf: remoteRulesFileURL),
           let decoded = try? JSONDecoder().decode([ContentBlockerRule].self, from: data) {
            remoteRules = decoded
        }
    }

    private func saveCachedRemoteRules() {
        if let data = try? JSONEncoder().encode(remoteRules) {
            try? data.write(to: remoteRulesFileURL, options: .atomic)
        }
        if let metaData = try? JSONEncoder().encode(metadata) {
            try? metaData.write(to: metadataFileURL, options: .atomic)
        }
    }

    private func compileOrLookupRules(whitelistedDomains: [String]) {
        status = .compiling

        let capturedBase = baseRules
        let capturedRemote = remoteRules
        let capturedWhitelist = whitelistedDomains

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let built = try FilterListParser.buildFinalEncodedJSON(
                    baseRules: capturedBase,
                    extraRules: capturedRemote,
                    whitelistedDomains: capturedWhitelist
                )
                guard let encodedString = String(data: built.data, encoding: .utf8) else {
                    throw NSError(domain: "NOVABrowser.AdBlock", code: 1, userInfo: [NSLocalizedDescriptionKey: "Error al codificar reglas."])
                }

                let digest = SHA256.hash(data: built.data)
                let hashHex = digest.map { String(format: "%02x", $0) }.joined()
                let identifier = "nova-shield-\(hashHex.prefix(20))"

                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if self.activeCompilationHash == identifier, let current = self.compiledRuleList {
                        self.status = .ready(ruleCount: built.ruleCount)
                        self.compiledRuleList = current
                        return
                    }

                    WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: identifier) { existingList, _ in
                        if let existingList = existingList {
                            Task { @MainActor in
                                self.activeCompilationHash = identifier
                                self.compiledRuleList = existingList
                                self.metadata.compiledRuleCount = built.ruleCount
                                self.status = .ready(ruleCount: built.ruleCount)
                            }
                            return
                        }

                        WKContentRuleListStore.default().compileContentRuleList(
                            forIdentifier: identifier,
                            encodedContentRuleList: encodedString
                        ) { compiledList, error in
                            Task { @MainActor in
                                if let compiledList = compiledList {
                                    self.activeCompilationHash = identifier
                                    self.compiledRuleList = compiledList
                                    self.metadata.compiledRuleCount = built.ruleCount
                                    self.status = .ready(ruleCount: built.ruleCount)
                                } else {
                                    self.compileBundledFallback(whitelistedDomains: capturedWhitelist, originalError: error)
                                }
                            }
                        }
                    }
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.status = .error("No se pudieron compilar las reglas: \(error.localizedDescription)")
                }
            }
        }
    }

    private func compileBundledFallback(whitelistedDomains: [String], originalError: Error?) {
        let capturedBase = baseRules
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let built = try? FilterListParser.buildFinalEncodedJSON(
                baseRules: capturedBase,
                extraRules: [],
                whitelistedDomains: whitelistedDomains
            ),
                  let encodedString = String(data: built.data, encoding: .utf8) else {
                Task { @MainActor [weak self] in
                    self?.status = .error(originalError?.localizedDescription ?? "Error al compilar bloqueador")
                }
                return
            }

            let digest = SHA256.hash(data: built.data)
            let hashHex = digest.map { String(format: "%02x", $0) }.joined()
            let identifier = "nova-shield-base-\(hashHex.prefix(16))"

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: identifier,
                    encodedContentRuleList: encodedString
                ) { compiledList, fallbackError in
                    Task { @MainActor in
                        if let compiledList = compiledList {
                            self.activeCompilationHash = identifier
                            self.compiledRuleList = compiledList
                            self.metadata.compiledRuleCount = built.ruleCount
                            self.metadata.usingBundledFallback = true
                            self.status = .ready(ruleCount: built.ruleCount)
                        } else {
                            self.status = .error(fallbackError?.localizedDescription ?? "Error en WebKit ContentRuleList")
                        }
                    }
                }
            }
        }
    }
}
