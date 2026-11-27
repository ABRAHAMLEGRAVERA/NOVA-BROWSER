import Foundation
import WebKit

enum PrivacyDataManager {
    @MainActor
    static func clearCookies(completion: @escaping () -> Void) {
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
