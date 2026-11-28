import Foundation
import WebKit

enum PrivacyDataManager {
    private static let persistedCookiesKey = "nova_persisted_cookies_v1"
    private static var lastSyncTimestamp: CFAbsoluteTime = 0
    private static let syncQueue = DispatchQueue(label: "com.novabrowser.cookieBackup", qos: .utility)

    /// Synchronizes cookies from WKWebsiteDataStore.default().httpCookieStore into HTTPCookieStorage
    /// and a UserDefaults backup so signed-in sessions survive WebKit process terminations & cold relaunches.
    /// Throttled during navigation to prevent main-thread micro-freezes on heavy websites.
    @MainActor
    static func syncCookiesToPersistentBackup(force: Bool = false) {
        let nowAbs = CFAbsoluteTimeGetCurrent()
        if !force && (nowAbs - lastSyncTimestamp) < 25 {
            return
        }
        lastSyncTimestamp = nowAbs

        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        cookieStore.getAllCookies { cookies in
            syncQueue.async {
                let now = Date()
                var archivedProps: [[String: Any]] = []
                archivedProps.reserveCapacity(cookies.count)
                for cookie in cookies {
                    if let exp = cookie.expiresDate, exp < now {
                        continue
                    }
                    HTTPCookieStorage.shared.setCookie(cookie)
                    if let props = cookie.properties {
                        var serializable: [String: Any] = [:]
                        for (k, v) in props {
                            if v is String || v is NSNumber || v is Date || v is Data {
                                serializable[k.rawValue] = v
                            } else if let url = v as? URL {
                                serializable[k.rawValue] = url.absoluteString
                            }
                        }
                        archivedProps.append(serializable)
                    }
                }
                if !archivedProps.isEmpty {
                    if let data = try? PropertyListSerialization.data(
                        fromPropertyList: archivedProps,
                        format: .binary,
                        options: 0
                    ) {
                        UserDefaults.standard.set(data, forKey: persistedCookiesKey)
                    }
                }
            }
        }
    }

    @MainActor
    static func restoreCookiesIntoWebKitStore(completion: (() -> Void)? = nil) {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        guard let data = UserDefaults.standard.data(forKey: persistedCookiesKey) else {
            completion?()
            return
        }

        syncQueue.async {
            var rawArray: [[String: Any]]?
            if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]] {
                rawArray = plist
            } else if let legacy = try? NSKeyedUnarchiver.unarchivedObject(
                ofClasses: [NSArray.self, NSDictionary.self, NSString.self, NSNumber.self, NSDate.self, NSData.self],
                from: data
            ) as? [[String: Any]] {
                rawArray = legacy
            }

            guard let decodedArray = rawArray else {
                DispatchQueue.main.async { completion?() }
                return
            }

            let now = Date()
            var restored: [HTTPCookie] = []
            restored.reserveCapacity(decodedArray.count)
            for raw in decodedArray {
                var converted: [HTTPCookiePropertyKey: Any] = [:]
                for (k, v) in raw {
                    converted[HTTPCookiePropertyKey(k)] = v
                }
                if let cookie = HTTPCookie(properties: converted) {
                    if let exp = cookie.expiresDate, exp < now {
                        continue
                    }
                    restored.append(cookie)
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
            }

            DispatchQueue.main.async {
                guard !restored.isEmpty else {
                    completion?()
                    return
                }
                let group = DispatchGroup()
                for cookie in restored {
                    group.enter()
                    cookieStore.setCookie(cookie) {
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    completion?()
                }
            }
        }
    }

    @MainActor
    static func clearCookies(completion: @escaping () -> Void) {
        UserDefaults.standard.removeObject(forKey: persistedCookiesKey)
        let store = WKWebsiteDataStore.default()
        let types: Set<String> = [WKWebsiteDataTypeCookies]
        store.removeData(ofTypes: types, modifiedSince: .distantPast) {
            HTTPCookieStorage.shared.removeCookies(since: .distantPast)
            Task { @MainActor in
                completion()
            }
        }
    }

    @MainActor
    static func clearAllBrowsingData(completion: @escaping () -> Void) {
        UserDefaults.standard.removeObject(forKey: persistedCookiesKey)
        let store = WKWebsiteDataStore.default()
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        store.removeData(ofTypes: allTypes, modifiedSince: .distantPast) {
            HTTPCookieStorage.shared.removeCookies(since: .distantPast)
            URLCache.shared.removeAllCachedResponses()
            Task { @MainActor in
                completion()
            }
        }
    }
}
