import Foundation
import Testing

@testable import GeneratorCore

@Suite("Article Codable round-trip")
struct ArticleCodableTests {
    @Test("round-trips an article covering every ContentBlock case")
    func roundTripsFullArticle() throws {
        let article = Article(
            title: "A Function That Never Surprises You",
            slug: "pure-functions",
            author: "Luiz Barbosa",
            emphasis: .text,
            draft: false,
            number: 1,
            published: PublicationDate(year: 2026, month: 7, day: 24),
            tags: [.basic, .purity],
            blocks: [
                .heading(level: .section, text: "A function that never surprises you"),
                .paragraph("Here's a function that calculates the price of a product including tax:"),
                .list(items: ["First", "Second"], bullet: "✅"),
                .list(items: ["No bullet item"]),
                .image(url: "https://example.com/x.png", altText: "An example"),
                .video(url: "https://example.com/x.mp4", caption: "A caption"),
                .video(url: "https://example.com/y.mp4", caption: nil),
                .code(language: .swift, source: "func priceWithTax(_ subtotal: Decimal) -> Decimal { subtotal }"),
                .equation(.raw("<math></math>")),
            ],
            brainstorming: "Maybe compare with a version that mutates a shared ledger instead?"
        )

        let data = try JSONEncoder().encode(article)
        let decoded = try JSONDecoder().decode(Article.self, from: data)

        #expect(decoded == article)
    }

    @Test("round-trips an article with no published date and no tags")
    func roundTripsMinimalArticle() throws {
        let article = Article(title: "Draft", slug: "draft", emphasis: .video, blocks: [.paragraph("Body")])

        let data = try JSONEncoder().encode(article)
        let decoded = try JSONDecoder().decode(Article.self, from: data)

        #expect(decoded == article)
    }

    @Test("decodes a pre-existing article JSON file that has no \"brainstorming\" key at all")
    func decodesArticleWithoutBrainstormingKey() throws {
        let json = """
        {
            "title": "Draft",
            "slug": "draft",
            "author": "Luiz Barbosa",
            "emphasis": "text",
            "draft": true,
            "number": 1,
            "tags": [],
            "blocks": [{"paragraph": {"_0": "Body"}}]
        }
        """
        let decoded = try JSONDecoder().decode(Article.self, from: Data(json.utf8))

        #expect(decoded.brainstorming == "")
    }
}
