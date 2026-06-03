import SwiftUI
import Foundation

/// URL detection over arbitrary user text (titles, notes).
enum LinkDetection {
    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    static func matches(in text: String) -> [NSTextCheckingResult] {
        guard let detector, !text.isEmpty else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range)
    }

    /// All URLs found in `text`, in order of appearance.
    static func urls(in text: String) -> [URL] {
        matches(in: text).compactMap { $0.url }
    }

    /// First http/https URL — the one we can render in a web view.
    static func firstWebURL(in text: String) -> URL? {
        urls(in: text).first { ($0.scheme?.lowercased()).map { $0 == "http" || $0 == "https" } ?? false }
    }

    /// Builds an AttributedString where every detected URL is colored and
    /// carries a `.link` attribute so SwiftUI renders it as a tappable link.
    static func attributed(_ text: String, linkColor: Color, strikethrough: Bool = false) -> AttributedString {
        var attr = AttributedString(text)
        if strikethrough {
            attr.strikethroughStyle = .single
        }
        for match in matches(in: text) {
            guard let url = match.url,
                  let range = Range(match.range, in: text),
                  let lo = AttributedString.Index(range.lowerBound, within: attr),
                  let hi = AttributedString.Index(range.upperBound, within: attr)
            else { continue }
            attr[lo..<hi].link = url
            attr[lo..<hi].foregroundColor = linkColor
            attr[lo..<hi].underlineStyle = .single
        }
        return attr
    }
}

/// Read-only text that renders URLs blue and clickable.
struct LinkText: View {
    let text: String
    var linkColor: Color = .accentColor
    var strikethrough: Bool = false

    var body: some View {
        Text(LinkDetection.attributed(text, linkColor: linkColor, strikethrough: strikethrough))
            .tint(linkColor)
            .textSelection(.enabled)
    }
}
