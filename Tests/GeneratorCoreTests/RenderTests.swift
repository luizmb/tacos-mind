import CoreFP
import CoreFPOperators
import DataStructure
import DataStructureOperators
import Foundation
import Testing

@testable import GeneratorCore

@Suite("renderArticle")
struct RenderArticleTests {
    @Test("renders blocks and an escaped paragraph, in order")
    func rendersBlocksInOrder() {
        let article = Article(
            title: "My <Title>",
            slug: "my-title",
            emphasis: .text,
            blocks: [
                .paragraph("<b>hi</b>"),
                .code(language: .swift, source: "let x = 1"),
            ]
        )
        let html = renderArticle(article)

        #expect(html.rendered.contains("<title>My &lt;Title&gt;</title>"))
        #expect(html.rendered.contains("<h1>My &lt;Title&gt;</h1>"))
        #expect(html.rendered.contains("<p>&lt;b&gt;hi&lt;/b&gt;</p>"))
        #expect(html.rendered.contains("<pre><code class=\"language-swift\">"))
        #expect(html.rendered.contains("<span class=\"token-keyword\">let</span>"))
        #expect(html.rendered.contains("<span class=\"token-declaration-other\">x</span>"))
        #expect(html.rendered.contains("<span class=\"token-number\">1</span>"))

        let paragraphIndex = html.rendered.range(of: "<p>")?.lowerBound
        let codeIndex = html.rendered.range(of: "<pre>")?.lowerBound
        #expect(paragraphIndex != nil && codeIndex != nil && paragraphIndex! < codeIndex!)
    }

    @Test("renders number, publication date, and tags in the article header")
    func rendersMetaAndTags() {
        let article = Article(
            title: "Tagged",
            slug: "tagged",
            emphasis: .text,
            number: 7,
            published: PublicationDate(year: 2026, month: 7, day: 24),
            tags: [.basic, .categoryTheory],
            blocks: []
        )
        let html = renderArticle(article)

        #expect(html.rendered.contains("<div class=\"article-meta\">Article #7 · 2026-07-24 · by Luiz Barbosa</div>"))
        #expect(html.rendered.contains("<a class=\"tag\" href=\"/tags/basic.html\">#basic</a>"))
        #expect(html.rendered.contains("<a class=\"tag\" href=\"/tags/category_theory.html\">#category_theory</a>"))
    }

    @Test("omits the tags container and date when absent")
    func omitsEmptyMeta() {
        let article = Article(title: "Bare", slug: "bare", emphasis: .text, number: 3, blocks: [])
        let html = renderArticle(article)

        #expect(html.rendered.contains("<div class=\"article-meta\">Article #3 · by Luiz Barbosa</div>"))
        #expect(!html.rendered.contains("article-tags"))
    }

    @Test("home page lists articles as #N - Title (by Author)")
    func homePageListFormat() {
        let article = Article(title: "Pure Functions", slug: "pure-functions", emphasis: .text, number: 1, blocks: [])

        let html = renderHomePage([article])

        #expect(html.rendered.contains(
            "<li><a href=\"/articles/pure-functions.html\">#1 - Pure Functions (by Luiz Barbosa)</a></li>"
        ))
    }

    @Test("renders a video block with an escaped caption")
    func rendersVideoWithCaption() {
        let article = Article(
            title: "Video",
            slug: "video",
            emphasis: .video,
            blocks: [.video(url: "clip.mp4", caption: "A & B")]
        )
        let html = renderArticle(article)

        #expect(html.rendered.contains("<video controls=\"controls\" src=\"clip.mp4\">"))
        #expect(html.rendered.contains("<figcaption>A &amp; B</figcaption>"))
    }

    @Test("renders a video block without a caption")
    func rendersVideoWithoutCaption() {
        let article = Article(
            title: "Video",
            slug: "video",
            emphasis: .video,
            blocks: [.video(url: "clip.mp4", caption: nil)]
        )
        let html = renderArticle(article)

        #expect(!html.rendered.contains("figcaption"))
    }

    @Test("renders section and subsection headings")
    func rendersHeadings() {
        let article = Article(
            title: "Sections",
            slug: "sections",
            emphasis: .text,
            blocks: [
                .heading(level: .section, text: "Overview"),
                .heading(level: .subsection, text: "Details"),
            ]
        )
        let html = renderArticle(article)

        #expect(html.rendered.contains("<h2>Overview</h2>"))
        #expect(html.rendered.contains("<h3>Details</h3>"))
    }

    @Test("renders inline code spans within a paragraph")
    func rendersInlineCodeInParagraph() {
        let article = Article(
            title: "Inline",
            slug: "inline",
            emphasis: .text,
            blocks: [.paragraph("call `f(a, b)` please")]
        )
        let html = renderArticle(article)

        #expect(html.rendered.contains("<p>call <code>f(a, b)</code> please</p>"))
    }

    @Test("renders a list block as ul/li with inline markup per item")
    func rendersListBlock() {
        let article = Article(
            title: "Checklist",
            slug: "checklist",
            emphasis: .text,
            blocks: [.list(items: ["plain item", "has `code` in it"])]
        )
        let html = renderArticle(article)

        #expect(html.rendered.contains("<ul><li>plain item</li><li>has <code>code</code> in it</li></ul>"))
    }

    @Test("header carries the tag strip on articles and home page alike")
    func headerTagStrip() {
        let article = Article(title: "T", slug: "t", emphasis: .text, blocks: [])
        let expected = "<div class=\"tag-strip\">"
            + "<a class=\"tag\" href=\"/tags/basic.html\">#basic</a>"
            + "<a class=\"tag\" href=\"/tags/purity.html\">#purity</a>"
            + "</div>"

        #expect(renderArticle(article, tags: [.basic, .purity]).rendered.contains(expected))
        #expect(renderHomePage([article], tags: [.basic, .purity]).rendered.contains(expected))
        #expect(!renderArticle(article).rendered.contains("tag-strip"))
    }

    @Test("tag page lists only the articles carrying that tag")
    func tagPageFilters() {
        let pure = Article(title: "Pure", slug: "pure", emphasis: .text, tags: [.purity], blocks: [])
        let math = Article(title: "Math", slug: "math", emphasis: .text, tags: [.math], blocks: [])

        let html = renderTagPage(.purity, articles: [pure, math], tags: [.math, .purity]).rendered

        #expect(html.contains("<title>#purity — Functional Programming for Swift Developers</title>"))
        #expect(html.contains("<h1>#purity</h1>"))
        #expect(html.contains("/articles/pure.html"))
        #expect(!html.contains("/articles/math.html"))
    }

    @Test("usedTags is unique and alphabetical by raw value")
    func usedTagsUniqueAndSorted() {
        let a = Article(title: "A", slug: "a", emphasis: .text, tags: [.math, .basic], blocks: [])
        let b = Article(title: "B", slug: "b", emphasis: .text, tags: [.basic, .categoryTheory], blocks: [])

        #expect(usedTags(in: [a, b]) == [.basic, .categoryTheory, .math])
    }

    @Test("renders a custom bullet as list-style-type on the ul, default otherwise")
    func rendersListBulletOption() {
        let article = Article(
            title: "Checklist",
            slug: "checklist",
            emphasis: .text,
            blocks: [
                .list(items: ["done"], bullet: "✅"),
                .list(items: ["plain"]),
            ]
        )
        let html = renderArticle(article)

        #expect(html.rendered.contains("<ul style=\"list-style-type: &quot;✅ &quot;\"><li>done</li></ul>"))
        #expect(html.rendered.contains("<ul><li>plain</li></ul>"))
    }
}

@Suite("writeArticle")
struct WriteArticleTests {
    @Test("creates the directory and writes the rendered markup to the article's path")
    func writesRenderedMarkupToDisk() {
        let article = Article(title: "Test", slug: "test-slug", emphasis: .text, blocks: [.paragraph("hi")])

        let createdDirectories = Box<[String]>([])
        let writtenFiles = Box<[(path: String, contents: String)]>([])
        let world = World.test(
            createDirectory: { path in
                createdDirectories.mutate { $0.append(path) }
                return .success(())
            },
            writeFile: { path, contents in
                writtenFiles.mutate { $0.append((path, contents)) }
                return .success(())
            }
        )

        let result = writeArticle(article, into: "dist/articles").runReader(world)

        #expect(result.isSuccess)
        #expect(createdDirectories.current == ["dist/articles"])
        #expect(writtenFiles.current.count == 1)
        #expect(writtenFiles.current.first?.path == "dist/articles/test-slug.html")
        #expect(writtenFiles.current.first?.contents.contains("<p>hi</p>") == true)
    }

    @Test("propagates a directory-creation failure without attempting to write the file")
    func propagatesDirectoryCreationFailure() {
        let article = Article(title: "Test", slug: "test-slug", emphasis: .text, blocks: [])
        let writeWasCalled = Box(false)
        let world = World.test(
            createDirectory: { _ in .failure(.directoryCreationFailed(path: "dist/articles", reason: "boom")) },
            writeFile: { _, _ in
                writeWasCalled.mutate { $0 = true }
                return .success(())
            }
        )

        let result = writeArticle(article, into: "dist/articles").runReader(world)

        #expect(result.failureValue == .directoryCreationFailed(path: "dist/articles", reason: "boom"))
        #expect(!writeWasCalled.current)
    }

    @Test("propagates a file-write failure")
    func propagatesFileWriteFailure() {
        let article = Article(title: "Test", slug: "test-slug", emphasis: .text, blocks: [])
        let world = World.test(
            writeFile: { _, _ in .failure(.fileWriteFailed(path: "dist/articles/test-slug.html", reason: "boom")) }
        )

        let result = writeArticle(article, into: "dist/articles").runReader(world)

        #expect(result.failureValue == .fileWriteFailed(path: "dist/articles/test-slug.html", reason: "boom"))
    }
}

@Suite("prepareSite")
struct PrepareSiteTests {
    @Test("wipes the output root before recreating it")
    func wipesThenCreates() {
        let calls = Box<[String]>([])
        let world = World.test(
            createDirectory: { path in
                calls.mutate { $0.append("create:\(path)") }
                return .success(())
            },
            removeDirectory: { path in
                calls.mutate { $0.append("remove:\(path)") }
                return .success(())
            }
        )

        let result = prepareSite(at: "dist").runReader(world)

        #expect(result.isSuccess)
        #expect(calls.current == ["remove:dist", "create:dist"])
    }

    @Test("propagates a removal failure without attempting to create")
    func propagatesRemovalFailure() {
        let createWasCalled = Box(false)
        let world = World.test(
            createDirectory: { _ in
                createWasCalled.mutate { $0 = true }
                return .success(())
            },
            removeDirectory: { _ in .failure(.directoryRemovalFailed(path: "dist", reason: "boom")) }
        )

        let result = prepareSite(at: "dist").runReader(world)

        #expect(result.failureValue == .directoryRemovalFailed(path: "dist", reason: "boom"))
        #expect(!createWasCalled.current)
    }
}

/// Test-only mutable box: World's closures are `@Sendable`, so a captured `var` can't be
/// mutated from inside them under strict concurrency — this gives spies a Sendable reference
/// to mutate instead.
final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    func mutate(_ transform: (inout T) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        transform(&value)
    }

    var current: T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private extension Result {
    var isSuccess: Bool {
        switch self {
        case .success: true
        case .failure: false
        }
    }
}

private extension Result {
    var failureValue: Failure? {
        switch self {
        case .success: nil
        case .failure(let error): error
        }
    }
}
