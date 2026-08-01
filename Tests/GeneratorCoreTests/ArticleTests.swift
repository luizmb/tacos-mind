import Testing

@testable import GeneratorCore

@Suite("publishableArticles")
struct ArticleTests {
    @Test("includes drafts when includeDrafts is true")
    func includesDraftsWhenRequested() {
        let published = Article(title: "Published", slug: "published", emphasis: .text, draft: false, blocks: [])
        let draft = Article(title: "Draft", slug: "draft", emphasis: .text, draft: true, blocks: [])

        let result = publishableArticles([published, draft], includeDrafts: true)

        #expect(result.map(\.slug) == ["published", "draft"])
    }

    @Test("filters out drafts when includeDrafts is false")
    func filtersDraftsForPublishBuild() {
        let published = Article(title: "Published", slug: "published", emphasis: .text, draft: false, blocks: [])
        let draft = Article(title: "Draft", slug: "draft", emphasis: .text, draft: true, blocks: [])

        let result = publishableArticles([published, draft], includeDrafts: false)

        #expect(result.map(\.slug) == ["published"])
    }

    @Test("defaults to not-draft when unspecified")
    func defaultsToNotDraft() {
        let article = Article(title: "Test", slug: "test", emphasis: .text, blocks: [])

        #expect(!article.draft)
    }
}
