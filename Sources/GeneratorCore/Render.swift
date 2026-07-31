import CoreFP
import CoreFPOperators
import DataStructure
import DataStructureOperators
import Foundation

func renderBlock(_ block: ContentBlock, links: [String: LinkTarget]) -> HTML {
    switch block {
    case .heading(let level, let text):
        heading(level, parseInline(text, links: links))
    case .paragraph(let text):
        p(parseInline(text, links: links))
    case .list(let items, let bullet):
        ul(mconcat(items.map { li(parseInline($0, links: links)) }), attributes: bulletAttributes(bullet))
    case .image(let url, let altText):
        img(src: url, alt: altText)
    case .video(let url, let caption):
        renderVideo(url: url, caption: caption)
    case .code(let language, let source):
        pre(code(highlightedCode(language: language, source: source), language: languageSlug(language)))
    case .equation(let content):
        displayEquation(content)
    }
}

/// `list-style-type` is inherited, so setting it once on the `<ul>` reaches every `<li>` —
/// no per-item styling needed. `nil` omits the attribute entirely, leaving the browser's
/// (or an ancestor's) default marker in place.
func bulletAttributes(_ bullet: String?) -> [String: String] {
    bullet.map { ["style": "list-style-type: \"\($0) \""] } ?? [:]
}

func heading(_ level: HeadingLevel, _ children: HTML) -> HTML {
    switch level {
    case .section: h2(children)
    case .subsection: h3(children)
    }
}

func highlightedCode(language: CodeLanguage, source: String) -> HTML {
    switch language {
    case .swift: highlightSwift(source)
    }
}

func renderVideo(url: String, caption: String?) -> HTML {
    figure(mconcat([
        video(src: url),
        caption.map { figcaption(.text($0)) } ?? .identity,
    ]))
}

func languageSlug(_ language: CodeLanguage) -> String {
    switch language {
    case .swift: "swift"
    }
}

func articleMeta(_ article: Article) -> HTML {
    element(
        "div",
        .text(
            "Article #\(article.number)"
                + (article.published.map { " · \($0.iso)" } ?? "")
                + " · by \(article.author)"
        ),
        attributes: ["class": "article-meta"]
    )
}

func tagLink(_ tag: Tag) -> HTML {
    element(
        "a",
        .text("#\(tag.rawValue)"),
        attributes: ["href": "/tags/\(tag.rawValue).html", "class": "tag"]
    )
}

/// The header's hashtag menu: every tag in use, alphabetical. Derived from the *published*
/// article list, so a draft's tags never leak a menu entry before the article ships.
public func tagStrip(_ tags: [Tag]) -> HTML {
    tags.isEmpty
        ? .identity
        : element("div", mconcat(tags.map(tagLink)), attributes: ["class": "tag-strip"])
}

/// Unique tags across the given articles, alphabetical by raw value.
public func usedTags(in articles: [Article]) -> [Tag] {
    Array(Set(articles.flatMap(\.tags))).sorted { $0.rawValue < $1.rawValue }
}

func articleTags(_ tags: [Tag]) -> HTML {
    tags.isEmpty
        ? .identity
        : element(
            "div",
            mconcat(tags.map(tagLink)),
            attributes: ["class": "article-tags"]
        )
}

func articleHeader(_ article: Article) -> HTML {
    mconcat([
        h1(.text(article.title)),
        articleMeta(article),
        articleTags(article.tags),
    ])
}

/// Pure — no generation timestamp on purpose: the site publishes as a reviewable PR of built
/// output, so identical content must produce byte-identical pages or every build would touch
/// every file and drown real changes in noise. The article's own published date is already in
/// its meta line.
public func renderArticle(_ article: Article, links: [String: LinkTarget] = [:], tags: [Tag] = []) -> HTML {
    htmlDocument(
        title: article.title,
        tagStrip: tagStrip(tags),
        body: articleHeader(article)
            <> mconcat(article.blocks.map { renderBlock($0, links: links) })
    )
}

public func writeArticle(
    _ article: Article,
    into directory: String,
    links: [String: LinkTarget] = [:],
    tags: [Tag] = []
) -> Reader<World, Result<Void, GeneratorError>> {
    Reader<World, Result<Void, GeneratorError>>.asks { world -> Result<Void, GeneratorError> in
        world.createDirectory(directory)
            >>- { world.writeFile("\(directory)/\(article.slug).html", renderArticle(article, links: links, tags: tags).rendered) }
    }
}

/// Wipes and recreates the output root, so every build starts from nothing — a renamed slug
/// or retired tag can't leave its old page lying around locally. Must run before any write
/// that targets a bare path in it — discovered the hard way when a fully deleted `dist/`
/// made the stylesheet write fail while later steps (whose own subdirectory creation
/// resurrects the root) succeeded.
public func prepareSite(at directory: String) -> Reader<World, Result<Void, GeneratorError>> {
    Reader<World, Result<Void, GeneratorError>>.asks { world in
        world.removeDirectory(directory)
            >>- { world.createDirectory(directory) }
    }
}

public func writeStylesheet(to path: String) -> Reader<World, Result<Void, GeneratorError>> {
    Reader<World, Result<Void, GeneratorError>>.asks { world in world.writeFile(path, siteStylesheet) }
}

func articleListItem(_ article: Article) -> HTML {
    li(a(
        href: "/articles/\(article.slug).html",
        .text("#\(article.number) - \(article.title) (by \(article.author))")
    ))
}

public func renderHomePage(_ articles: [Article], tags: [Tag] = []) -> HTML {
    htmlDocument(
        title: "ios.lu — Functional Programming for Swift Developers",
        tagStrip: tagStrip(tags),
        body: mconcat([
            h1(.text("Functional Programming for Swift Developers")),
            ul(mconcat(articles.map(articleListItem)), attributes: ["class": "article-index"]),
        ])
    )
}

public func writeHomePage(_ articles: [Article], tags: [Tag] = [], to path: String) -> Reader<World, Result<Void, GeneratorError>> {
    Reader<World, Result<Void, GeneratorError>>.asks { world in world.writeFile(path, renderHomePage(articles, tags: tags).rendered) }
}

/// The landing page filtered to one hashtag: same list renderer, only the matching articles.
public func renderTagPage(_ tag: Tag, articles: [Article], tags: [Tag]) -> HTML {
    htmlDocument(
        title: "#\(tag.rawValue) — Functional Programming for Swift Developers",
        tagStrip: tagStrip(tags),
        body: mconcat([
            h1(.text("#\(tag.rawValue)")),
            ul(
                mconcat(articles.filter { $0.tags.contains(tag) }.map(articleListItem)),
                attributes: ["class": "article-index"]
            ),
        ])
    )
}

public func writeTagPage(
    _ tag: Tag,
    articles: [Article],
    tags: [Tag],
    into directory: String
) -> Reader<World, Result<Void, GeneratorError>> {
    Reader<World, Result<Void, GeneratorError>>.asks { world in
        world.createDirectory(directory)
            >>- { world.writeFile("\(directory)/\(tag.rawValue).html", renderTagPage(tag, articles: articles, tags: tags).rendered) }
    }
}
