import Foundation

enum MetadataFetcher {
    struct Result {
        var title: String?
        var description: String?
    }

    static func fetch(url: URL) async -> Result {
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("Mozilla/5.0 (Macintosh) MustDo/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let html = String(data: data, encoding: .utf8) ?? ""
            let title = extractTitle(html: html)
            let description = extractMeta(html: html, name: "description")
                ?? extractMetaProperty(html: html, property: "og:description")
            return Result(title: title, description: description)
        } catch {
            return Result(title: nil, description: nil)
        }
    }

    private static func extractTitle(html: String) -> String? {
        if let og = extractMetaProperty(html: html, property: "og:title"), !og.isEmpty {
            return og
        }
        if let range = html.range(of: "<title[^>]*>([\\s\\S]*?)</title>", options: .regularExpression) {
            let inner = String(html[range])
            if let open = inner.range(of: ">"), let close = inner.range(of: "</title>", options: .backwards) {
                let content = String(inner[open.upperBound..<close.lowerBound])
                return decodeEntities(content.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return nil
    }

    private static func extractMeta(html: String, name: String) -> String? {
        let pattern = "<meta[^>]+name=\"\(name)\"[^>]+content=\"([^\"]*)\""
        return firstCaptureGroup(html: html, pattern: pattern)
    }

    private static func extractMetaProperty(html: String, property: String) -> String? {
        let pattern = "<meta[^>]+property=\"\(property)\"[^>]+content=\"([^\"]*)\""
        return firstCaptureGroup(html: html, pattern: pattern)
    }

    private static func firstCaptureGroup(html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = html as NSString
        let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: ns.length))
        guard let m = match, m.numberOfRanges >= 2 else { return nil }
        return decodeEntities(ns.substring(with: m.range(at: 1)))
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
