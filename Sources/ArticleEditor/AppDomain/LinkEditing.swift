import Foundation

/// What an existing link span resolves to, matching the site's own `[[slug]]` /
/// `[[slug|custom text]]` and `[label](url)` syntax (`GeneratorCore/InlineMarkup.swift`).
public enum LinkKind: Equatable, Sendable {
    case internalSlug(slug: String, displayText: String)
    case external(url: String, displayText: String)

    public var displayText: String {
        switch self {
        case .internalSlug(_, let displayText): displayText
        case .external(_, let displayText): displayText
        }
    }
}

/// A link span found while scanning a block's raw text, in UTF-16 (`NSRange`) terms —
/// the same space `NSTextView.selectedRange()` / `UITextView.selectedRange` use.
public struct DetectedLink: Equatable, Sendable {
    public let range: NSRange
    public let kind: LinkKind

    public init(range: NSRange, kind: LinkKind) {
        self.range = range
        self.kind = kind
    }
}

/// Every `[[slug]]` / `[[slug|text]]` and `[label](url)` span in `text`, in source order.
/// Mirrors `GeneratorCore`'s own `parseLinks`/`parseExternalLinks`: internal spans are
/// found first, and the external-link scan skips anything already claimed by one, so a
/// `[[` pair is never misread as the start of a `[label](url)`.
public func findLinks(in text: String) -> [DetectedLink] {
    let ns = text as NSString
    var results: [DetectedLink] = []
    var claimed: [NSRange] = []

    var searchLocation = 0
    while searchLocation < ns.length {
        let openRange = ns.range(of: "[[", range: NSRange(location: searchLocation, length: ns.length - searchLocation))
        guard openRange.location != NSNotFound else { break }
        let afterOpen = openRange.location + openRange.length
        let closeRange = ns.range(of: "]]", range: NSRange(location: afterOpen, length: ns.length - afterOpen))
        guard closeRange.location != NSNotFound else { break }
        let inner = ns.substring(with: NSRange(location: afterOpen, length: closeRange.location - afterOpen))
        let parts = inner.split(separator: "|", maxSplits: 1).map(String.init)
        let slug = parts.first ?? inner
        let displayText = parts.count > 1 ? parts[1] : slug
        let fullRange = NSRange(location: openRange.location, length: closeRange.location + closeRange.length - openRange.location)
        results.append(DetectedLink(range: fullRange, kind: .internalSlug(slug: slug, displayText: displayText)))
        claimed.append(fullRange)
        searchLocation = fullRange.location + fullRange.length
    }

    searchLocation = 0
    while searchLocation < ns.length {
        let openRange = ns.range(of: "[", range: NSRange(location: searchLocation, length: ns.length - searchLocation))
        guard openRange.location != NSNotFound else { break }
        if claimed.contains(where: { NSLocationInRange(openRange.location, $0) }) {
            searchLocation = openRange.location + 1
            continue
        }
        if openRange.location + 1 < ns.length, ns.character(at: openRange.location + 1) == UInt16(UnicodeScalar("[").value) {
            searchLocation = openRange.location + 2
            continue
        }
        let afterOpen = openRange.location + openRange.length
        let labelClose = ns.range(of: "](", range: NSRange(location: afterOpen, length: ns.length - afterOpen))
        guard labelClose.location != NSNotFound else { searchLocation = afterOpen; continue }
        let afterLabelClose = labelClose.location + labelClose.length
        let urlClose = ns.range(of: ")", range: NSRange(location: afterLabelClose, length: ns.length - afterLabelClose))
        guard urlClose.location != NSNotFound else { searchLocation = afterOpen; continue }
        let label = ns.substring(with: NSRange(location: afterOpen, length: labelClose.location - afterOpen))
        let url = ns.substring(with: NSRange(location: afterLabelClose, length: urlClose.location - afterLabelClose))
        let fullRange = NSRange(location: openRange.location, length: urlClose.location + urlClose.length - openRange.location)
        results.append(DetectedLink(range: fullRange, kind: .external(url: url, displayText: label)))
        searchLocation = fullRange.location + fullRange.length
    }

    return results.sorted { $0.range.location < $1.range.location }
}

/// The link span (if any) containing `location`, an `NSRange`-space cursor position —
/// used to decide whether "Edit Link" should appear for a caret with no selection.
public func detectLink(in text: String, at location: Int) -> DetectedLink? {
    findLinks(in: text).first { NSLocationInRange(location, $0.range) }
}

/// The replacement text for wrapping `displayText` as a `[[slug]]` reference — plain
/// `[[slug]]` when the display text equals the slug (nothing to preserve), otherwise
/// `[[slug|displayText]]`.
public func internalLinkText(displayText: String, slug: String) -> String {
    displayText.isEmpty || displayText == slug ? "[[\(slug)]]" : "[[\(slug)|\(displayText)]]"
}

/// The replacement text for wrapping `displayText` as a `[label](url)` external link.
public func externalLinkText(displayText: String, url: String) -> String {
    "[\(displayText.isEmpty ? url : displayText)](\(url))"
}
