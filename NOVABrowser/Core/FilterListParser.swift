import Foundation

enum FilterListParser {
    static let maxCompiledRulesForLegacyiPad = 18_000

    static func parseEasyListToWebKitRules(
        _ rawText: String,
        maxRules: Int = maxCompiledRulesForLegacyiPad
    ) -> (rules: [ContentBlockerRule], adDomains: Set<String>) {
        var rules: [ContentBlockerRule] = []
        var adDomains = Set<String>()
        var seenFilters = Set<String>()

        let lines = rawText.components(separatedBy: .newlines)
        for rawLine in lines {
            if rules.count >= maxRules { break }

            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") {
                continue
            }

            // Skip exception lines and complex extended selectors during remote EasyList merge
            // to prevent overriding critical YouTube/video protections or breaking WebKit compilation.
            if line.hasPrefix("@@") || line.contains("#@#") || line.contains("#?#") {
                continue
            }

            if line.contains("##") {
                if let rule = parseElementHidingRule(line), !seenFilters.contains("css:\(rule.action.selector ?? "")") {
                    seenFilters.insert("css:\(rule.action.selector ?? "")")
                    rules.append(rule)
                }
                continue
            }

            if line.hasPrefix("||") {
                if let parsed = parseDomainBlockRule(line) {
                    let key = "blk:\(parsed.rule.trigger.urlFilter)"
                    if !seenFilters.contains(key) {
                        seenFilters.insert(key)
                        rules.append(parsed.rule)
                        if let domain = parsed.domain {
                            adDomains.insert(domain)
                        }
                    }
                }
            }
        }

        return (rules, adDomains)
    }

    private static func parseDomainBlockRule(_ line: String) -> (rule: ContentBlockerRule, domain: String?)? {
        var body = String(line.dropFirst(2))
        var isThirdPartyOnly = true

        if let dollarIndex = body.firstIndex(of: "$") {
            let optionsPart = String(body[body.index(after: dollarIndex)...]).lowercased()
            body = String(body[..<dollarIndex])

            if optionsPart.contains("document") || optionsPart.contains("elemhide") || optionsPart.contains("generichide") {
                return nil
            }
            if optionsPart.contains("~third-party") {
                isThirdPartyOnly = false
            }
        }

        // Handle pure domain anchor ||domain.com^ or ||domain.com^/path
        var domainPart = body
        var pathPart = ""
        if let caretIndex = body.firstIndex(of: "^") {
            domainPart = String(body[..<caretIndex])
            pathPart = String(body[body.index(after: caretIndex)...])
        } else if let slashIndex = body.firstIndex(of: "/") {
            domainPart = String(body[..<slashIndex])
            pathPart = String(body[slashIndex...])
        }

        domainPart = domainPart.lowercased()
        guard isValidASCIIHostname(domainPart), !isProtectedVideoDomain(domainPart) else {
            return nil
        }

        let escapedDomain = NSRegularExpression.escapedPattern(for: domainPart)
        var regex = "^https?://([a-z0-9-]+\\.)*\(escapedDomain)(:|/|$)"
        if !pathPart.isEmpty {
            let cleanPath = pathPart.replacingOccurrences(of: "*", with: ".*")
            guard isSafeASCII(cleanPath) else { return nil }
            let escapedPath = escapePathExceptWildcard(pathPart)
            regex = "^https?://([a-z0-9-]+\\.)*\(escapedDomain)\(escapedPath)"
        }

        let trigger = ContentBlockerRule.Trigger(
            urlFilter: regex,
            urlFilterIsCaseSensitive: nil,
            loadType: isThirdPartyOnly ? ["third-party"] : nil,
            resourceType: nil,
            ifDomain: nil,
            unlessDomain: nil
        )
        let rule = ContentBlockerRule(
            trigger: trigger,
            action: ContentBlockerRule.Action(type: "block", selector: nil)
        )
        return (rule, pathPart.isEmpty ? domainPart : nil)
    }

    private static func parseElementHidingRule(_ line: String) -> ContentBlockerRule? {
        let parts = line.components(separatedBy: "##")
        guard parts.count == 2 else { return nil }
        let domainSpec = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let selector = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

        guard !selector.isEmpty,
              selector.count <= 140,
              isSafeCSSSelector(selector) else {
            return nil
        }

        var ifDomains: [String]? = nil
        if !domainSpec.isEmpty {
            let rawDomains = domainSpec.split(separator: ",").map { String($0).lowercased() }
            if rawDomains.contains(where: { $0.hasPrefix("~") }) {
                return nil
            }
            let validDomains = rawDomains.filter { isValidASCIIHostname($0) }
            guard !validDomains.isEmpty else { return nil }
            ifDomains = validDomains.map { "*\($0)" }
        }

        let trigger = ContentBlockerRule.Trigger(
            urlFilter: ".*",
            urlFilterIsCaseSensitive: nil,
            loadType: nil,
            resourceType: nil,
            ifDomain: ifDomains,
            unlessDomain: nil
        )
        return ContentBlockerRule(
            trigger: trigger,
            action: ContentBlockerRule.Action(type: "css-display-none", selector: selector)
        )
    }

    static func buildFinalEncodedJSON(
        baseRules: [ContentBlockerRule],
        extraRules: [ContentBlockerRule],
        whitelistedDomains: [String]
    ) throws -> (data: Data, ruleCount: Int) {
        var combined: [ContentBlockerRule] = []
        combined.reserveCapacity(min(baseRules.count + extraRules.count + 4, maxCompiledRulesForLegacyiPad))

        // Separate ignore-previous-rules safeguards from baseRules so safeguards always remain near the end.
        let baseBlocking = baseRules.filter { $0.action.type != "ignore-previous-rules" }
        let baseSafeguards = baseRules.filter { $0.action.type == "ignore-previous-rules" }

        let extraLimit = max(0, maxCompiledRulesForLegacyiPad - baseBlocking.count - baseSafeguards.count - 2)
        combined.append(contentsOf: baseBlocking)
        combined.append(contentsOf: extraRules.prefix(extraLimit))
        combined.append(contentsOf: baseSafeguards)

        let normalizedWhitelist = whitelistedDomains
            .map { URLResolver.normalizeDomainString($0) }
            .filter { !$0.isEmpty && isValidASCIIHostname($0) }

        if !normalizedWhitelist.isEmpty {
            let domainPatterns = normalizedWhitelist.map { "*\($0)" }
            let whitelistRule = ContentBlockerRule(
                trigger: ContentBlockerRule.Trigger(
                    urlFilter: ".*",
                    urlFilterIsCaseSensitive: nil,
                    loadType: nil,
                    resourceType: nil,
                    ifDomain: domainPatterns,
                    unlessDomain: nil
                ),
                action: ContentBlockerRule.Action(type: "ignore-previous-rules", selector: nil)
            )
            combined.append(whitelistRule)
        }

        let encoder = JSONEncoder()
        let data = try encoder.encode(combined)
        return (data, combined.count)
    }

    static func isValidASCIIHostname(_ host: String) -> Bool {
        guard !host.isEmpty, host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else {
            return false
        }
        return host.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }
    }

    static func isProtectedVideoDomain(_ domain: String) -> Bool {
        let protected = [
            "youtube.com", "youtu.be", "googlevideo.com", "ytimg.com",
            "ggpht.com", "vimeo.com", "vimeocdn.com", "jwpcdn.com", "twitch.tv"
        ]
        return protected.contains { domain == $0 || domain.hasSuffix(".\($0)") }
    }

    private static func isSafeASCII(_ text: String) -> Bool {
        text.allSatisfy { $0.isASCII }
    }

    private static func isSafeCSSSelector(_ selector: String) -> Bool {
        guard isSafeASCII(selector) else { return false }
        let unsupported = [":has(", ":is(", ":where(", ":-abp-", ":xpath(", "has-text("]
        let lower = selector.lowercased()
        if unsupported.contains(where: { lower.contains($0) }) {
            return false
        }
        return !selector.contains("{") && !selector.contains("}")
    }

    private static func escapePathExceptWildcard(_ path: String) -> String {
        var result = ""
        for ch in path {
            if ch == "*" {
                result.append(".*")
            } else if ".+?^$()[]{}|\\".contains(ch) {
                result.append("\\")
                result.append(ch)
            } else {
                result.append(ch)
            }
        }
        return result
    }
}
