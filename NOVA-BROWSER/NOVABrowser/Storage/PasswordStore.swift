import Foundation
import Security

struct PasswordCredential: Identifiable, Codable, Equatable {
    let id: UUID
    var domain: String
    var username: String
    var password: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        domain: String,
        username: String,
        password: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.domain = URLResolver.normalizeDomainString(domain)
        self.username = username
        self.password = password
        self.updatedAt = updatedAt
    }
}

@MainActor
final class PasswordStore: ObservableObject {
    @Published private(set) var credentials: [PasswordCredential] = []

    private let serviceName = "com.novabrowser.ipad.credentials"
    private let accountKey = "nova_saved_credentials_v1"

    init() {
        loadFromKeychain()
    }

    func matchingCredentials(for host: String?) -> [PasswordCredential] {
        guard let host = host else { return [] }
        let normalized = URLResolver.normalizeDomainString(host)
        guard !normalized.isEmpty else { return [] }
        return credentials.filter { cred in
            let d = URLResolver.normalizeDomainString(cred.domain)
            return normalized == d || normalized.hasSuffix(".\(d)") || d.hasSuffix(".\(normalized)")
        }
    }

    func saveCredential(domain: String, username: String, password: String) {
        let normalizedDomain = URLResolver.normalizeDomainString(domain)
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDomain.isEmpty, !cleanUser.isEmpty, !password.isEmpty else { return }

        if let idx = credentials.firstIndex(where: {
            URLResolver.normalizeDomainString($0.domain) == normalizedDomain &&
            $0.username.caseInsensitiveCompare(cleanUser) == .orderedSame
        }) {
            credentials[idx].password = password
            credentials[idx].updatedAt = Date()
        } else {
            let item = PasswordCredential(domain: normalizedDomain, username: cleanUser, password: password)
            credentials.insert(item, at: 0)
        }
        credentials.sort { $0.updatedAt > $1.updatedAt }
        persistToKeychain()
    }

    func updateCredential(_ credential: PasswordCredential, domain: String, username: String, password: String) {
        guard let idx = credentials.firstIndex(where: { $0.id == credential.id }) else { return }
        let normalizedDomain = URLResolver.normalizeDomainString(domain)
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDomain.isEmpty, !cleanUser.isEmpty, !password.isEmpty else { return }

        credentials[idx].domain = normalizedDomain
        credentials[idx].username = cleanUser
        credentials[idx].password = password
        credentials[idx].updatedAt = Date()
        credentials.sort { $0.updatedAt > $1.updatedAt }
        persistToKeychain()
    }

    func deleteCredential(_ credential: PasswordCredential) {
        credentials.removeAll { $0.id == credential.id }
        persistToKeychain()
    }

    func deleteAllCredentials() {
        credentials.removeAll()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountKey
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func loadFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            credentials = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([PasswordCredential].self, from: data) {
            credentials = decoded.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private func persistToKeychain() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(credentials) else { return }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountKey
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}
