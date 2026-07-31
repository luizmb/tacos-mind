import Foundation

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
}
