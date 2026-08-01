import Testing

@testable import GeneratorCore

@Suite("parseInline")
struct InlineMarkupTests {
    @Test("passes plain text through unchanged")
    func plainTextPassesThrough() {
        #expect(parseInline("hello world").rendered == "hello world")
    }

    @Test("wraps a single backtick span in code")
    func singleSpan() {
        #expect(parseInline("call `f(a)` now").rendered == "call <code>f(a)</code> now")
    }

    @Test("wraps multiple backtick spans in the same text")
    func multipleSpans() {
        let html = parseInline("`(A, B) -> C` becomes `A -> (B -> C)`").rendered

        #expect(html == "<code>(A, B) -&gt; C</code> becomes <code>A -&gt; (B -&gt; C)</code>")
    }

    @Test("escapes reserved characters in both plain and code segments")
    func escapesBothSegments() {
        let html = parseInline("a < b and `c < d`").rendered

        #expect(html == "a &lt; b and <code>c &lt; d</code>")
    }
}

@Suite("article links")
struct ArticleLinkTests {
    let links = [
        "currying": LinkTarget(title: "Currying: One Argument at a Time", isPublished: true),
        "map-array": LinkTarget(title: "map on Array", isPublished: false),
    ]

    @Test("renders a published reference as a link with the target's title")
    func publishedReference() {
        let html = parseInline("see [[currying]] for more", links: links).rendered

        #expect(html == "see <a href=\"/articles/currying.html\">Currying: One Argument at a Time</a> for more")
    }

    @Test("renders custom link text after a pipe")
    func customText() {
        let html = parseInline("the [[currying|currying article]] covers it", links: links).rendered

        #expect(html == "the <a href=\"/articles/currying.html\">currying article</a> covers it")
    }

    @Test("degrades an unpublished reference to plain text")
    func unpublishedReference() {
        let html = parseInline("later, [[map-array]] shows this", links: links).rendered

        #expect(html == "later, map on Array shows this")
        #expect(!html.contains("<a "))
    }

    @Test("never parses references inside code spans")
    func codeSpansWin() {
        let html = parseInline("literal `[[currying]]` stays code", links: links).rendered

        #expect(html == "literal <code>[[currying]]</code> stays code")
    }

    @Test("renders an external markdown link")
    func externalLink() {
        let html = parseInline("keep asking [\"why?\"](https://en.wikipedia.org/wiki/Five_whys) forever").rendered

        #expect(html == "keep asking <a href=\"https://en.wikipedia.org/wiki/Five_whys\""
            + " rel=\"noopener\" target=\"_blank\">\"why?\"</a> forever")
    }

    @Test("external links coexist with article references in the same text")
    func externalAndInternalLinks() {
        let html = parseInline("see [[currying]] and [wiki](https://example.org) too", links: links).rendered

        #expect(html == "see <a href=\"/articles/currying.html\">Currying: One Argument at a Time</a>"
            + " and <a href=\"https://example.org\" rel=\"noopener\" target=\"_blank\">wiki</a> too")
    }

    @Test("a lone bracket without the](url) shape stays literal")
    func loneBracketStaysLiteral() {
        #expect(parseInline("array[0] and [not a link]").rendered == "array[0] and [not a link]")
    }

    @Test("never parses external links inside code spans")
    func externalLinksSkipCodeSpans() {
        let html = parseInline("literal `[x](y)` stays code").rendered

        #expect(html == "literal <code>[x](y)</code> stays code")
    }

    @Test("renders asterisk pairs as emphasis")
    func emphasisSpans() {
        #expect(parseInline("it gets *better*: much better").rendered
            == "it gets <em>better</em>: much better")
    }

    @Test("an unmatched asterisk stays literal")
    func unmatchedAsteriskStaysLiteral() {
        #expect(parseInline("10 * 4 is forty").rendered == "10 * 4 is forty")
        #expect(parseInline("*leading emphasis* then 2 * 3").rendered
            == "<em>leading emphasis</em> then 2 * 3")
    }

    @Test("never parses emphasis inside code spans")
    func emphasisSkipsCodeSpans() {
        #expect(parseInline("code `a * b * c` stays code").rendered
            == "code <code>a * b * c</code> stays code")
    }

    @Test("emphasis coexists with links in the same text")
    func emphasisWithLinks() {
        let html = parseInline("*really*, see [[currying]] and [w](https://e.org) *now*", links: links).rendered

        #expect(html == "<em>really</em>, see <a href=\"/articles/currying.html\">Currying: One Argument at a Time</a>"
            + " and <a href=\"https://e.org\" rel=\"noopener\" target=\"_blank\">w</a> <em>now</em>")
    }

    @Test("undefinedLinkSlugs finds typos and accepts drafts")
    func validation() {
        let target = Article(title: "Target", slug: "target", emphasis: .text, draft: true, blocks: [])
        let referrer = Article(
            title: "Referrer",
            slug: "referrer",
            emphasis: .text,
            blocks: [
                .paragraph("good link to [[target]] and bad link to [[tagret]]"),
                .heading(level: .section, text: "also [[missing|a missing one]]"),
                .code(language: .swift, source: "let ignored = [[Int]]()"),
                .list(items: ["item with [[target]]", "item with [[typo-slug]]"]),
            ]
        )

        #expect(undefinedLinkSlugs(in: [target, referrer]) == ["tagret", "missing", "typo-slug"])
    }

    @Test("linkTable marks publishability from the filtered list")
    func tableConstruction() {
        let live = Article(title: "Live", slug: "live", emphasis: .text, blocks: [])
        let draft = Article(title: "Draft", slug: "draft", emphasis: .text, draft: true, blocks: [])

        let table = linkTable(all: [live, draft], published: [live])

        #expect(table["live"]?.isPublished == true)
        #expect(table["draft"]?.isPublished == false)
        #expect(table["draft"]?.title == "Draft")
    }
}
