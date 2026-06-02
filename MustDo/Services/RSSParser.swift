import Foundation

struct ParsedFeed {
    var title: String
    var description: String
    var episodes: [ParsedEpisode]
}

struct ParsedEpisode {
    var title: String
    var summary: String
    var publishedAt: Date?
    var audioURL: String?
    var durationSeconds: Double?
}

final class RSSParser: NSObject, XMLParserDelegate {
    private var feed = ParsedFeed(title: "", description: "", episodes: [])
    private var currentElement = ""
    private var currentChars = ""
    private var inItem = false
    private var inChannel = false
    private var currentEpisode = ParsedEpisode(title: "", summary: "")
    private var dateFormatters: [DateFormatter] = {
        let f1 = DateFormatter()
        f1.locale = Locale(identifier: "en_US_POSIX")
        f1.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let f2 = DateFormatter()
        f2.locale = Locale(identifier: "en_US_POSIX")
        f2.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let f3 = DateFormatter()
        f3.locale = Locale(identifier: "en_US_POSIX")
        f3.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return [f1, f2, f3]
    }()

    static func parse(data: Data) -> ParsedFeed? {
        let parser = RSSParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.shouldProcessNamespaces = true
        xml.shouldReportNamespacePrefixes = false
        if xml.parse() {
            return parser.feed
        }
        return nil
    }

    static func fetch(from url: URL) async throws -> ParsedFeed {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let feed = parse(data: data) else {
            throw NSError(domain: "RSSParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not parse feed"])
        }
        return feed
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName.lowercased()
        currentChars = ""
        if currentElement == "channel" { inChannel = true }
        if currentElement == "item" {
            inItem = true
            currentEpisode = ParsedEpisode(title: "", summary: "")
        }
        if currentElement == "enclosure", inItem {
            if let url = attributeDict["url"] { currentEpisode.audioURL = url }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentChars.append(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        let trimmed = currentChars.trimmingCharacters(in: .whitespacesAndNewlines)
        if inItem {
            switch name {
            case "title": currentEpisode.title = trimmed
            case "description", "summary":
                if currentEpisode.summary.isEmpty { currentEpisode.summary = trimmed }
            case "pubdate":
                currentEpisode.publishedAt = parseDate(trimmed)
            case "duration":
                currentEpisode.durationSeconds = parseDuration(trimmed)
            case "item":
                feed.episodes.append(currentEpisode)
                inItem = false
            default: break
            }
        } else if inChannel {
            switch name {
            case "title":
                if feed.title.isEmpty { feed.title = trimmed }
            case "description":
                if feed.description.isEmpty { feed.description = trimmed }
            case "channel":
                inChannel = false
            default: break
            }
        }
        currentChars = ""
    }

    private func parseDate(_ s: String) -> Date? {
        for f in dateFormatters {
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    private func parseDuration(_ s: String) -> Double? {
        if let v = Double(s) { return v }
        let parts = s.split(separator: ":").compactMap { Double($0) }
        if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return nil
    }
}
