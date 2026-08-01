import CoreFP
import CoreFPOperators

/// What a `[[slug]]` reference resolves to. Built by the generator from the full article
/// manifest: `isPublished` reflects whether the target made it into the *current* build, so
/// links to drafts degrade to plain text on publish builds and light up once the target ships.
public struct LinkTarget: Sendable {
    public let title: String
    public let isPublished: Bool

    public init(title: String, isPublished: Bool) {
        self.title = title
        self.isPublished = isPublished
    }
}

/// Splits text on backtick pairs, alternating plain text and inline `code` spans — a
/// deliberately tiny subset of Markdown, not a general parser. Plain segments additionally
/// support `[[slug]]` / `[[slug|custom text]]` article cross-references, `[text](url)`
/// external links, and `*emphasis*` spans (never inside code spans — backticks win). An
/// unmatched trailing backtick swallows the rest of the text into a code span rather than
/// erroring; an unmatched asterisk stays literal. Acceptable for hand-authored articles,
/// not for untrusted input.
func parseInline(_ text: String, links: [String: LinkTarget] = [:]) -> HTML {
    mconcat(
        text.components(separatedBy: "`").enumerated().map { index, segment in
            index.isMultiple(of: 2) ? parseLinks(segment, links: links) : code(.text(segment))
        }
    )
}

func parseLinks(_ text: String, links: [String: LinkTarget]) -> HTML {
    let chunks = text.components(separatedBy: "[[")
    let head = parseExternalLinks(chunks.first ?? "")
    let tail = chunks.dropFirst().map { chunk in
        renderLinkChunk(chunk, links: links)
    }
    return mconcat([head] + tail)
}

func renderLinkChunk(_ chunk: String, links: [String: LinkTarget]) -> HTML {
    guard let close = chunk.range(of: "]]") else {
        return parseExternalLinks("[[" + chunk)
    }
    let reference = String(chunk[..<close.lowerBound])
    let rest = String(chunk[close.upperBound...])
    return mconcat([renderReference(reference, links: links), parseExternalLinks(rest)])
}

/// `[text](url)` external links. Runs after `[[slug]]` splitting, so it only ever sees
/// single brackets. A `[` that isn't followed by the full `](…)` shape stays literal text.
func parseExternalLinks(_ text: String) -> HTML {
    let chunks = text.components(separatedBy: "[")
    let head = parseEmphasis(chunks.first ?? "")
    let tail = chunks.dropFirst().map(renderExternalLinkChunk)
    return mconcat([head] + tail)
}

func renderExternalLinkChunk(_ chunk: String) -> HTML {
    guard
        let close = chunk.range(of: "]("),
        let end = chunk.range(of: ")", range: close.upperBound..<chunk.endIndex)
    else {
        return parseEmphasis("[" + chunk)
    }
    let label = String(chunk[..<close.lowerBound])
    let url = String(chunk[close.upperBound..<end.lowerBound])
    let rest = String(chunk[end.upperBound...])
    return mconcat([externalLink(href: url, .text(label)), parseEmphasis(rest)])
}

/// `*emphasis*` spans in plain text, alternating on asterisk pairs like the backtick
/// splitter. An unmatched trailing asterisk stays literal — prose multiplication like
/// "10 * 4" survives untouched.
func parseEmphasis(_ text: String) -> HTML {
    let chunks = text.components(separatedBy: "*")
    let unmatched = chunks.count.isMultiple(of: 2)
    let paired = unmatched ? Array(chunks.dropLast()) : chunks
    let tail = unmatched ? HTML.text("*" + (chunks.last ?? "")) : .identity
    return mconcat(
        paired.enumerated().map { index, segment in
            index.isMultiple(of: 2) ? .text(segment) : em(.text(segment))
        }
    ) <> tail
}

func renderReference(_ reference: String, links: [String: LinkTarget]) -> HTML {
    let parts = reference.split(separator: "|", maxSplits: 1).map(String.init)
    let slug = parts.first ?? reference
    let customText = parts.count > 1 ? parts[1] : nil
    guard let target = links[slug] else {
        return .text(customText ?? slug)
    }
    let text = customText ?? target.title
    return target.isPublished ? a(href: "/articles/\(slug).html", .text(text)) : .text(text)
}

/// Every `[[slug]]` reference found in a text, code spans excluded.
func linkSlugs(in text: String) -> [String] {
    text.components(separatedBy: "`").enumerated()
        .filter { index, _ in index.isMultiple(of: 2) }
        .flatMap { _, segment in
            segment.components(separatedBy: "[[").dropFirst().compactMap { chunk in
                chunk.range(of: "]]").map { close in
                    String(chunk[..<close.lowerBound].prefix(while: { $0 != "|" }))
                }
            }
        }
}

func linkableTexts(of article: Article) -> [String] {
    article.blocks.flatMap { block -> [String] in
        switch block {
        case .heading(_, let text): [text]
        case .paragraph(let text): [text]
        case .list(let items, _): items
        default: []
        }
    }
}

/// Cross-reference validation: every `[[slug]]` in every article must name an article in the
/// manifest — drafts included, since links to drafts are valid (they degrade until published).
/// A non-empty result should fail the build; a typo'd or renamed slug is a broken promise.
public func undefinedLinkSlugs(in articles: [Article]) -> [String] {
    let known = Set(articles.map(\.slug))
    return articles
        .flatMap { linkableTexts(of: $0).flatMap(linkSlugs(in:)) }
        .filter { !known.contains($0) }
}

/// The slug-to-target table for a build: titles from the full manifest, publishability from
/// the filtered list actually being written.
public func linkTable(all: [Article], published: [Article]) -> [String: LinkTarget] {
    let publishedSlugs = Set(published.map(\.slug))
    return Dictionary(uniqueKeysWithValues: all.map { article in
        (article.slug, LinkTarget(title: article.title, isPublished: publishedSlugs.contains(article.slug)))
    })
}
