import Foundation

struct TranslationTextNode: Codable {
    let id: Int
    let text: String
}

enum PageTranslatorService {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 14
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    static func translateNodes(
        _ nodes: [TranslationTextNode],
        targetLanguageCode: String
    ) async -> [Int: String] {
        guard !nodes.isEmpty else { return [:] }

        let chunks = makeBatches(from: nodes, maxCharsPerBatch: 1400, maxItemsPerBatch: 20)
        var results: [Int: String] = [:]

        // Process batches with bounded concurrency (max 3 in flight for iPad Air 2 stability)
        var index = 0
        while index < chunks.count {
            let end = min(index + 3, chunks.count)
            let slice = Array(chunks[index..<end])
            await withTaskGroup(of: [Int: String].self) { group in
                for batch in slice {
                    group.addTask {
                        await translateBatch(batch, targetLanguageCode: targetLanguageCode)
                    }
                }
                for await partial in group {
                    for (k, v) in partial {
                        results[k] = v
                    }
                }
            }
            index = end
        }
        return results
    }

    static func makeBatches(
        from nodes: [TranslationTextNode],
        maxCharsPerBatch: Int,
        maxItemsPerBatch: Int
    ) -> [[TranslationTextNode]] {
        var batches: [[TranslationTextNode]] = []
        var current: [TranslationTextNode] = []
        var currentChars = 0

        for node in nodes {
            let len = node.text.count
            if !current.isEmpty && (current.count >= maxItemsPerBatch || currentChars + len > maxCharsPerBatch) {
                batches.append(current)
                current = []
                currentChars = 0
            }
            current.append(node)
            currentChars += len
        }
        if !current.isEmpty {
            batches.append(current)
        }
        return batches
    }

    private static func translateBatch(
        _ batch: [TranslationTextNode],
        targetLanguageCode: String
    ) async -> [Int: String] {
        // Use a distinctive newline-separated marker that Google Translate preserves cleanly
        let markerPrefix = "NVX_"
        let taggedLines = batch.map { item -> String in
            let safeText = item.text.replacingOccurrences(of: "\n", with: " ")
            return "[\(markerPrefix)\(item.id)] \(safeText)"
        }
        let joined = taggedLines.joined(separator: "\n")

        guard let encoded = joined.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=\(targetLanguageCode)&dt=t&q=\(encoded)") else {
            return [:]
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPad; CPU OS 15_8 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let translatedFull = parseGoogleTranslateResponse(data) else {
            return [:]
        }

        return parseTaggedTranslations(translatedFull, expectedIDs: batch.map { $0.id })
    }

    static func parseGoogleTranslateResponse(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [Any] else {
            return nil
        }
        var combined = ""
        for segment in segments {
            if let pair = segment as? [Any], let chunk = pair.first as? String {
                combined.append(chunk)
            }
        }
        return combined.isEmpty ? nil : combined
    }

    static func parseTaggedTranslations(_ text: String, expectedIDs: [Int]) -> [Int: String] {
        var map: [Int: String] = [:]
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Match [NVX_123] or slight whitespace variations like [ NVX_123 ]
            if let range = trimmed.range(of: #"\[\s*NVX_(\d+)\s*\]\s*"#, options: .regularExpression) {
                let tag = String(trimmed[range])
                let digits = tag.filter { $0.isNumber }
                if let id = Int(digits) {
                    let translated = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !translated.isEmpty {
                        map[id] = translated
                    }
                }
            }
        }

        // Fallback positional alignment if line count matches batch size
        if map.isEmpty && lines.count == expectedIDs.count {
            for (idx, id) in expectedIDs.enumerated() {
                let t = lines[idx].trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    map[id] = t
                }
            }
        }
        return map
    }
}
