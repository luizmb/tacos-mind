import CoreFP

public struct HTML: Sendable, Equatable, Codable {
    let markup: String

    public var rendered: String { markup }
}

extension HTML: Semigroup {
    public static func combine(_ lhs: HTML, _ rhs: HTML) -> HTML {
        HTML(markup: lhs.markup + rhs.markup)
    }
}

extension HTML: Monoid {
    public static var identity: HTML { HTML(markup: "") }
}

extension HTML {
    public static func text(_ content: String) -> HTML {
        HTML(markup: escapeText(content))
    }

    public static func raw(_ markup: String) -> HTML {
        HTML(markup: markup)
    }
}

public func element(_ tag: String, _ children: HTML, attributes: [String: String] = [:]) -> HTML {
    HTML(markup: "<\(tag)\(renderAttributes(attributes))>\(children.markup)</\(tag)>")
}

public func voidElement(_ tag: String, attributes: [String: String] = [:]) -> HTML {
    HTML(markup: "<\(tag)\(renderAttributes(attributes)) />")
}

func renderAttributes(_ attributes: [String: String]) -> String {
    attributes
        .sorted { $0.key < $1.key }
        .map { " \($0.key)=\"\(escapeAttribute($0.value))\"" }
        .joined()
}

func escapeText(_ text: String) -> String {
    text
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

func escapeAttribute(_ text: String) -> String {
    escapeText(text).replacingOccurrences(of: "\"", with: "&quot;")
}
