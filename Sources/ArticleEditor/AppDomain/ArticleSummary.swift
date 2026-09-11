import Foundation
import GeneratorCore

/// A shallow scan result for the sidebar: just enough to list and open a file, without
/// parsing its blocks.
public struct ArticleSummary: Identifiable, Equatable, Sendable {
    public var url: URL
    public var slug: String
    public var title: String
    public var number: Int

    public var id: String { slug }

    public init(url: URL, slug: String, title: String, number: Int) {
        self.url = url
        self.slug = slug
        self.title = title
        self.number = number
    }

    /// The same file, described by `article` instead.
    ///
    /// Every field here except `url` is *content* — the editor's form can change all
    /// three — so a summary taken before a write can disagree with the file the moment
    /// one lands. `url` is carried over rather than re-derived because saving rewrites a
    /// file, it never renames one: the path is the article's identity, the slug is just
    /// what it currently calls itself.
    public func reflecting(_ article: Article) -> ArticleSummary {
        ArticleSummary(url: url, slug: article.slug, title: article.title, number: article.number)
    }
}
