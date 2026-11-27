import XCTest
@testable import NOVABrowser

final class NOVABrowserTests: XCTestCase {
    func testURLResolverParsesDirectDomainsAndSearchQueries() {
        let domainURL = URLResolver.resolveInput("youtube.com", searchEngine: .google)
        XCTAssertEqual(domainURL?.absoluteString, "https://youtube.com")

        let explicitURL = URLResolver.resolveInput("http://192.168.1.1:8080/status", searchEngine: .google)
        XCTAssertEqual(explicitURL?.absoluteString, "http://192.168.1.1:8080/status")

        let googleSearchURL = URLResolver.resolveInput("swift wkwebview ipad", searchEngine: .google)
        XCTAssertEqual(googleSearchURL?.host, "www.google.com")
        XCTAssertTrue(googleSearchURL?.query?.contains("swift%20wkwebview%20ipad") == true)

        let braveSearchURL = URLResolver.resolveInput("swift wkwebview ipad", searchEngine: .brave)
        XCTAssertEqual(braveSearchURL?.host, "search.brave.com")
        XCTAssertTrue(braveSearchURL?.query?.contains("swift%20wkwebview%20ipad") == true)
    }

    func testBrowserSettingsDecodesLegacySearchEngineSafely() throws {
        let legacyJSON = """
        {
          "searchEngine": "duckduckgo",
          "appearanceMode": "dark"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BrowserSettings.self, from: legacyJSON)
        XCTAssertEqual(decoded.searchEngine, .google)
        XCTAssertEqual(decoded.appearanceMode, .dark)
        XCTAssertTrue(decoded.videoPerformanceMode)
    }

    func testFilterListParserProtectsYouTubeAndParsesEasyList() throws {
        let sampleEasyList = """
        ! Comment line
        [Adblock Plus 2.0]
        ||doubleclick.net^$third-party
        ||googlevideo.com^
        ||popads.net^
        ##.ad-banner
        example.com##div:has(.ad)
        """

        let parsed = FilterListParser.parseEasyListToWebKitRules(sampleEasyList)
        XCTAssertTrue(parsed.adDomains.contains("doubleclick.net"))
        XCTAssertTrue(parsed.adDomains.contains("popads.net"))
        // Protected video domain must never be added to blocking rules
        XCTAssertFalse(parsed.adDomains.contains("googlevideo.com"))
        // Unsupported :has() CSS selector must be skipped so WebKit compilation never fails
        XCTAssertFalse(parsed.rules.contains { $0.action.selector?.contains(":has(") == true })
    }

    func testWhitelistAppendsIgnorePreviousRulesAtEnd() throws {
        let baseRule = ContentBlockerRule(
            trigger: .init(urlFilter: "^https?://doubleclick\\.net/", urlFilterIsCaseSensitive: nil, loadType: ["third-party"], resourceType: nil, ifDomain: nil, unlessDomain: nil),
            action: .init(type: "block", selector: nil)
        )
        let safeguard = ContentBlockerRule(
            trigger: .init(urlFilter: "^https?://googlevideo\\.com/", urlFilterIsCaseSensitive: nil, loadType: nil, resourceType: nil, ifDomain: nil, unlessDomain: nil),
            action: .init(type: "ignore-previous-rules", selector: nil)
        )

        let built = try FilterListParser.buildFinalEncodedJSON(
            baseRules: [safeguard, baseRule],
            extraRules: [],
            whitelistedDomains: ["https://www.ejemplo.com/ruta"]
        )

        let decoded = try JSONDecoder().decode([ContentBlockerRule].self, from: built.data)
        XCTAssertEqual(decoded.first?.action.type, "block")
        XCTAssertEqual(decoded.last?.action.type, "ignore-previous-rules")
        XCTAssertEqual(decoded.last?.trigger.ifDomain, ["*ejemplo.com"])
    }

    func testPersistenceStoreNeverSavesIncognitoTabs() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("nova_test_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = PersistenceStore(directory: tempDir)
        let normalTab = BrowserTab(title: "Wikipedia", urlString: "https://es.wikipedia.org", isIncognito: false)
        let incognitoTab = BrowserTab(title: "Privada", urlString: "https://example.com", isIncognito: true)

        store.saveTabsSnapshot(PersistedTabsSnapshot(tabs: [normalTab, incognitoTab], activeTabID: incognitoTab.id))
        let loaded = store.loadTabsSnapshot()

        XCTAssertEqual(loaded?.tabs.count, 1)
        XCTAssertEqual(loaded?.tabs.first?.id, normalTab.id)
        XCTAssertEqual(loaded?.activeTabID, normalTab.id)
    }

    func testDownloadItemSegmentsPersistAcrossPause() throws {
        let segs = [
            DownloadSegment(index: 0, startByte: 0, endByte: 999, downloadedBytes: 500, isCompleted: false),
            DownloadSegment(index: 1, startByte: 1000, endByte: 1999, downloadedBytes: 1000, isCompleted: true)
        ]
        let item = DownloadItem(
            filename: "video.mp4",
            sourceURLString: "https://example.com/video.mp4",
            totalBytes: 2000,
            receivedBytes: 1500,
            progress: 0.75,
            state: .paused,
            supportsResume: true,
            activeConnections: 2,
            segments: segs
        )
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(DownloadItem.self, from: data)
        XCTAssertEqual(decoded.state, .paused)
        XCTAssertEqual(decoded.segments?.count, 2)
        XCTAssertTrue(decoded.canResume)
        XCTAssertTrue(decoded.isVideo)
    }
}
