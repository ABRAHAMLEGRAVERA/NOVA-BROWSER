import Foundation

struct ContentBlockerRule: Codable, Equatable {
    struct Trigger: Codable, Equatable {
        var urlFilter: String
        var urlFilterIsCaseSensitive: Bool?
        var loadType: [String]?
        var resourceType: [String]?
        var ifDomain: [String]?
        var unlessDomain: [String]?

        enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter"
            case urlFilterIsCaseSensitive = "url-filter-is-case-sensitive"
            case loadType = "load-type"
            case resourceType = "resource-type"
            case ifDomain = "if-domain"
            case unlessDomain = "unless-domain"
        }
    }

    struct Action: Codable, Equatable {
        var type: String
        var selector: String?
    }

    var trigger: Trigger
    var action: Action
}

struct FilterListMetadata: Codable, Equatable {
    var sourceName: String
    var sourceURLString: String
    var lastUpdated: Date?
    var compiledRuleCount: Int
    var usingBundledFallback: Bool

    static let initial = FilterListMetadata(
        sourceName: "NOVA Shield + EasyList",
        sourceURLString: "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblockplus&showintro=0&mimetype=plaintext",
        lastUpdated: nil,
        compiledRuleCount: 0,
        usingBundledFallback: true
    )
}

enum AdBlockerStatus: Equatable {
    case idle
    case compiling
    case ready(ruleCount: Int)
    case disabled
    case error(String)
}
