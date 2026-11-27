import Foundation

enum URLResolver {
    static func resolveInput(_ rawInput: String, searchEngine: SearchEngine) -> URL? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let direct = URL(string: trimmed),
           let scheme = direct.scheme?.lowercased(),
           ["http", "https", "about"].contains(scheme),
           direct.host != nil || scheme == "about" {
            return direct
        }

        if !trimmed.contains(" "), looksLikeDomainOrHost(trimmed) {
            let candidate = "https://\(trimmed)"
            if let url = URL(string: candidate), url.host != nil {
                return url
            }
        }

        return searchEngine.searchURL(for: trimmed)
    }

    static func looksLikeDomainOrHost(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower == "localhost" || lower.hasPrefix("localhost:") || lower.hasPrefix("localhost/") {
            return true
        }
        if isIPv4Like(lower) {
            return true
        }
        guard let firstSegment = lower.split(separator: "/").first?.split(separator: ":").first else {
            return false
        }
        let host = String(firstSegment)
        guard host.contains("."),
              !host.hasPrefix("."),
              !host.hasSuffix("."),
              !host.contains("..") else {
            return false
        }
        let parts = host.split(separator: ".")
        guard let tld = parts.last, tld.count >= 2, tld.allSatisfy({ $0.isLetter }) else {
            return false
        }
        return host.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }
    }

    private static func isIPv4Like(_ text: String) -> Bool {
        let hostPart = String(text.split(separator: "/").first?.split(separator: ":").first ?? "")
        let octets = hostPart.split(separator: ".")
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { segment in
            if let num = Int(segment), num >= 0 && num <= 255 {
                return true
            }
            return false
        }
    }

    static func normalizedHost(from url: URL?) -> String? {
        guard let host = url?.host?.lowercased(), !host.isEmpty else { return nil }
        return normalizeDomainString(host)
    }

    static func normalizeDomainString(_ domain: String) -> String {
        var clean = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.hasPrefix("http://") {
            clean = String(clean.dropFirst("http://".count))
        } else if clean.hasPrefix("https://") {
            clean = String(clean.dropFirst("https://".count))
        }
        if let slashIndex = clean.firstIndex(of: "/") {
            clean = String(clean[..<slashIndex])
        }
        if let colonIndex = clean.firstIndex(of: ":") {
            clean = String(clean[..<colonIndex])
        }
        if clean.hasPrefix("www.") {
            clean = String(clean.dropFirst("www.".count))
        }
        return clean
    }

    static func displayTitle(for url: URL?, pageTitle: String?) -> String {
        if let title = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let host = url?.host?.replacingOccurrences(of: "www.", with: ""), !host.isEmpty {
            return host
        }
        return "Nueva pestaña"
    }

    static func isWebScheme(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "about", "blob", "data"].contains(scheme)
    }
}
