import Foundation

enum SearchEngine: String, CaseIterable, Codable, Identifiable {
    case google = "google"

    var id: String { rawValue }

    var displayName: String {
        "Google"
    }

    var shortName: String {
        "Google"
    }

    init(from decoder: Decoder) throws {
        _ = try? decoder.singleValueContainer().decode(String.self)
        self = .google
    }

    func searchURL(for query: String) -> URL? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://www.google.com/search?q=\(encoded)")
    }
}

enum TranslationLanguage: String, CaseIterable, Codable, Identifiable {
    case spanish = "es"
    case english = "en"
    case portuguese = "pt"
    case french = "fr"
    case italian = "it"
    case german = "de"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spanish: return "Español"
        case .english: return "Inglés"
        case .portuguese: return "Portugués"
        case .french: return "Francés"
        case .italian: return "Italiano"
        case .german: return "Alemán"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Codable, Identifiable {
    case automatic = "automatic"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "Automático"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        }
    }
}

enum HomePageMode: String, CaseIterable, Codable, Identifiable {
    case novaStart = "nova_start"
    case customURL = "custom_url"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .novaStart: return "Página de inicio NOVA"
        case .customURL: return "URL personalizada"
        }
    }
}

struct PendingCredentialSave: Equatable {
    let domain: String
    let username: String
    let password: String
}

struct BrowserTab: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var urlString: String?
    var isIncognito: Bool
    var isDesktopMode: Bool
    var isLoading: Bool
    var estimatedProgress: Double
    var canGoBack: Bool
    var canGoForward: Bool
    var errorMessage: String?
    var failedURLString: String?
    var blockedCount: Int
    var hasVideoOnPage: Bool
    var detectedVideoURLString: String?
    var isPageTranslated: Bool
    var translatedLanguageName: String?
    var isTranslating: Bool
    var pendingCredentialSave: PendingCredentialSave?
    var lastAccessedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "Inicio",
        urlString: String? = nil,
        isIncognito: Bool = false,
        isDesktopMode: Bool = false,
        isLoading: Bool = false,
        estimatedProgress: Double = 0,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        errorMessage: String? = nil,
        failedURLString: String? = nil,
        blockedCount: Int = 0,
        hasVideoOnPage: Bool = false,
        detectedVideoURLString: String? = nil,
        isPageTranslated: Bool = false,
        translatedLanguageName: String? = nil,
        isTranslating: Bool = false,
        pendingCredentialSave: PendingCredentialSave? = nil,
        lastAccessedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.isIncognito = isIncognito
        self.isDesktopMode = isDesktopMode
        self.isLoading = isLoading
        self.estimatedProgress = estimatedProgress
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.errorMessage = errorMessage
        self.failedURLString = failedURLString
        self.blockedCount = blockedCount
        self.hasVideoOnPage = hasVideoOnPage
        self.detectedVideoURLString = detectedVideoURLString
        self.isPageTranslated = isPageTranslated
        self.translatedLanguageName = translatedLanguageName
        self.isTranslating = isTranslating
        self.pendingCredentialSave = pendingCredentialSave
        self.lastAccessedAt = lastAccessedAt
    }

    var isStartPage: Bool {
        urlString == nil || urlString?.isEmpty == true
    }

    var currentURL: URL? {
        guard let urlString = urlString, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }

    var currentHost: String? {
        currentURL?.host?.lowercased()
    }

    enum CodingKeys: String, CodingKey {
        case id, title, urlString, isIncognito, isDesktopMode, lastAccessedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        urlString = try container.decodeIfPresent(String.self, forKey: .urlString)
        isIncognito = try container.decodeIfPresent(Bool.self, forKey: .isIncognito) ?? false
        isDesktopMode = try container.decodeIfPresent(Bool.self, forKey: .isDesktopMode) ?? false
        lastAccessedAt = try container.decodeIfPresent(Date.self, forKey: .lastAccessedAt) ?? Date()
        isLoading = false
        estimatedProgress = 0
        canGoBack = false
        canGoForward = false
        errorMessage = nil
        failedURLString = nil
        blockedCount = 0
        hasVideoOnPage = false
        detectedVideoURLString = nil
        isPageTranslated = false
        translatedLanguageName = nil
        isTranslating = false
        pendingCredentialSave = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(urlString, forKey: .urlString)
        try container.encode(isIncognito, forKey: .isIncognito)
        try container.encode(isDesktopMode, forKey: .isDesktopMode)
        try container.encode(lastAccessedAt, forKey: .lastAccessedAt)
    }
}

struct BookmarkItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var urlString: String
    var createdAt: Date

    init(id: UUID = UUID(), title: String, urlString: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.createdAt = createdAt
    }

    var host: String {
        URL(string: urlString)?.host ?? urlString
    }
}

struct HistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var urlString: String
    var visitedAt: Date

    init(id: UUID = UUID(), title: String, urlString: String, visitedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.visitedAt = visitedAt
    }

    var host: String {
        URL(string: urlString)?.host ?? urlString
    }
}

struct QuickShortcut: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var urlString: String
    var colorHex: String

    init(id: UUID = UUID(), title: String, urlString: String, colorHex: String = "#2563EB") {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.colorHex = colorHex
    }

    var host: String {
        URL(string: urlString)?.host?.replacingOccurrences(of: "www.", with: "") ?? urlString
    }

    var monogram: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first {
            return String(first).uppercased()
        }
        return "N"
    }

    static let defaults: [QuickShortcut] = [
        QuickShortcut(title: "YouTube", urlString: "https://www.youtube.com", colorHex: "#DC2626"),
        QuickShortcut(title: "Google", urlString: "https://www.google.com", colorHex: "#2563EB"),
        QuickShortcut(title: "Wikipedia", urlString: "https://es.wikipedia.org", colorHex: "#475569"),
        QuickShortcut(title: "Vimeo", urlString: "https://vimeo.com", colorHex: "#0284C7"),
        QuickShortcut(title: "GitHub", urlString: "https://github.com", colorHex: "#1E293B"),
        QuickShortcut(title: "Traductor", urlString: "https://translate.google.com", colorHex: "#0D9488")
    ]
}

struct BrowserSettings: Codable, Equatable {
    var searchEngine: SearchEngine
    var appearanceMode: AppearanceMode
    var homePageMode: HomePageMode
    var customHomeURLString: String
    var defaultDesktopMode: Bool
    var restoreTabsOnLaunch: Bool
    var adBlockerEnabled: Bool
    var forceDarkWebPages: Bool
    var videoPerformanceMode: Bool
    var autoSavePasswords: Bool
    var defaultTranslationLanguage: TranslationLanguage
    var whitelistedDomains: [String]
    var totalBlockedLifetime: Int

    enum CodingKeys: String, CodingKey {
        case searchEngine, appearanceMode, homePageMode, customHomeURLString,
             defaultDesktopMode, restoreTabsOnLaunch, adBlockerEnabled,
             forceDarkWebPages, videoPerformanceMode, autoSavePasswords,
             defaultTranslationLanguage, whitelistedDomains, totalBlockedLifetime
    }

    init(
        searchEngine: SearchEngine,
        appearanceMode: AppearanceMode,
        homePageMode: HomePageMode,
        customHomeURLString: String,
        defaultDesktopMode: Bool,
        restoreTabsOnLaunch: Bool,
        adBlockerEnabled: Bool,
        forceDarkWebPages: Bool,
        videoPerformanceMode: Bool,
        autoSavePasswords: Bool,
        defaultTranslationLanguage: TranslationLanguage,
        whitelistedDomains: [String],
        totalBlockedLifetime: Int
    ) {
        self.searchEngine = searchEngine
        self.appearanceMode = appearanceMode
        self.homePageMode = homePageMode
        self.customHomeURLString = customHomeURLString
        self.defaultDesktopMode = defaultDesktopMode
        self.restoreTabsOnLaunch = restoreTabsOnLaunch
        self.adBlockerEnabled = adBlockerEnabled
        self.forceDarkWebPages = forceDarkWebPages
        self.videoPerformanceMode = videoPerformanceMode
        self.autoSavePasswords = autoSavePasswords
        self.defaultTranslationLanguage = defaultTranslationLanguage
        self.whitelistedDomains = whitelistedDomains
        self.totalBlockedLifetime = totalBlockedLifetime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        searchEngine = (try? c.decode(SearchEngine.self, forKey: .searchEngine)) ?? .google
        appearanceMode = (try? c.decode(AppearanceMode.self, forKey: .appearanceMode)) ?? .automatic
        homePageMode = (try? c.decode(HomePageMode.self, forKey: .homePageMode)) ?? .novaStart
        customHomeURLString = (try? c.decode(String.self, forKey: .customHomeURLString)) ?? "https://www.google.com"
        defaultDesktopMode = (try? c.decode(Bool.self, forKey: .defaultDesktopMode)) ?? false
        restoreTabsOnLaunch = (try? c.decode(Bool.self, forKey: .restoreTabsOnLaunch)) ?? true
        adBlockerEnabled = (try? c.decode(Bool.self, forKey: .adBlockerEnabled)) ?? true
        forceDarkWebPages = (try? c.decode(Bool.self, forKey: .forceDarkWebPages)) ?? false
        videoPerformanceMode = (try? c.decode(Bool.self, forKey: .videoPerformanceMode)) ?? true
        autoSavePasswords = (try? c.decode(Bool.self, forKey: .autoSavePasswords)) ?? true
        defaultTranslationLanguage = (try? c.decode(TranslationLanguage.self, forKey: .defaultTranslationLanguage)) ?? .spanish
        whitelistedDomains = (try? c.decode([String].self, forKey: .whitelistedDomains)) ?? []
        totalBlockedLifetime = (try? c.decode(Int.self, forKey: .totalBlockedLifetime)) ?? 0
    }

    static let `default` = BrowserSettings(
        searchEngine: .google,
        appearanceMode: .automatic,
        homePageMode: .novaStart,
        customHomeURLString: "https://www.google.com",
        defaultDesktopMode: false,
        restoreTabsOnLaunch: true,
        adBlockerEnabled: true,
        forceDarkWebPages: false,
        videoPerformanceMode: true,
        autoSavePasswords: true,
        defaultTranslationLanguage: .spanish,
        whitelistedDomains: [],
        totalBlockedLifetime: 0
    )
}

struct PersistedTabsSnapshot: Codable {
    var tabs: [BrowserTab]
    var activeTabID: UUID?
}
