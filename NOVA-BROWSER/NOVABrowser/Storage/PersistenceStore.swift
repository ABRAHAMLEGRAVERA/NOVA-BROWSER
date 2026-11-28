import Foundation

final class PersistenceStore {
    private let baseDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let saveQueue = DispatchQueue(label: "com.novabrowser.persistence", qos: .utility)

    init(directory: URL? = nil) {
        if let directory = directory {
            self.baseDirectory = directory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.baseDirectory = appSupport.appendingPathComponent("NOVABrowser", isDirectory: true)
        }
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    private var settingsURL: URL { baseDirectory.appendingPathComponent("settings.json") }
    private var bookmarksURL: URL { baseDirectory.appendingPathComponent("bookmarks.json") }
    private var historyURL: URL { baseDirectory.appendingPathComponent("history.json") }
    private var shortcutsURL: URL { baseDirectory.appendingPathComponent("shortcuts.json") }
    private var tabsURL: URL { baseDirectory.appendingPathComponent("tabs_snapshot.json") }

    func loadSettings() -> BrowserSettings {
        load(BrowserSettings.self, from: settingsURL) ?? .default
    }

    func saveSettings(_ settings: BrowserSettings) {
        save(settings, to: settingsURL)
    }

    func loadBookmarks() -> [BookmarkItem] {
        load([BookmarkItem].self, from: bookmarksURL) ?? []
    }

    func saveBookmarks(_ bookmarks: [BookmarkItem]) {
        save(bookmarks, to: bookmarksURL)
    }

    func loadHistory() -> [HistoryEntry] {
        load([HistoryEntry].self, from: historyURL) ?? []
    }

    func saveHistory(_ history: [HistoryEntry]) {
        save(Array(history.prefix(500)), to: historyURL)
    }

    func loadShortcuts() -> [QuickShortcut] {
        load([QuickShortcut].self, from: shortcutsURL) ?? QuickShortcut.defaults
    }

    func saveShortcuts(_ shortcuts: [QuickShortcut]) {
        save(shortcuts, to: shortcutsURL)
    }

    func loadTabsSnapshot() -> PersistedTabsSnapshot? {
        load(PersistedTabsSnapshot.self, from: tabsURL)
    }

    func saveTabsSnapshot(_ snapshot: PersistedTabsSnapshot) {
        // Never persist incognito tabs to disk
        let normalTabs = snapshot.tabs.filter { !$0.isIncognito }
        let safeActiveID = normalTabs.contains(where: { $0.id == snapshot.activeTabID })
            ? snapshot.activeTabID
            : normalTabs.first?.id
        let sanitized = PersistedTabsSnapshot(tabs: normalTabs, activeTabID: safeActiveID)
        save(sanitized, to: tabsURL)
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        saveQueue.sync {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(type, from: data)
        }
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        let localEncoder = encoder
        saveQueue.async {
            guard let data = try? localEncoder.encode(value) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
