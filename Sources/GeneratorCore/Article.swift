public enum Emphasis: String, Sendable, Equatable, CaseIterable, Codable {
    case text
    case video
}

public enum CodeLanguage: String, Sendable, Equatable, CaseIterable, Codable {
    case swift
}

public enum HeadingLevel: String, Sendable, Equatable, CaseIterable, Codable {
    case section
    case subsection
}

public enum ContentBlock: Sendable, Equatable, Codable {
    case heading(level: HeadingLevel, text: String)
    case paragraph(String)
    case list(items: [String], bullet: String? = nil)
    case image(url: String, altText: String)
    case video(url: String, caption: String?)
    case code(language: CodeLanguage, source: String)
    case equation(HTML)
}

/// Rendered as `#raw_value` on the article page; multi-word cases carry their
/// snake_case spelling in the raw value so the rendered hashtag needs no conversion.
public enum Tag: String, Sendable, Equatable, CaseIterable, Codable {
    case basic
    case intermediate
    case advanced
    case algebraicDataTypes = "algebraic_data_types"
    case helpers
    case fun
    case composition
    case tacitStyle = "tacit_style"
    case dataStructures = "data_structures"
    case algebra
    case categoryTheory = "category_theory"
    case math
    case functor
    case applicativeFunctor = "applicative_functor"
    case monad
    case monoid
    case semigroup
    case purity
    case effects
    case functions
    case higherOrderFunction = "higher_order_function"
    case currying
    case laziness
    case laws
}

public struct PublicationDate: Sendable, Equatable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public var iso: String {
        "\(year)-\(padded(month))-\(padded(day))"
    }
}

func padded(_ value: Int) -> String {
    value < 10 ? "0\(value)" : "\(value)"
}

public struct Article: Sendable, Equatable, Codable {
    public let title: String
    public let slug: String
    public let author: String
    public let emphasis: Emphasis
    public let draft: Bool
    public let number: Int
    public let published: PublicationDate?
    public let tags: [Tag]
    public let blocks: [ContentBlock]
    /// Free-form personal notes — never rendered to HTML, read only by the author (and,
    /// on-device, a future writing assistant).
    public let brainstorming: String

    public init(
        title: String,
        slug: String,
        author: String = "Luiz Barbosa",
        emphasis: Emphasis,
        draft: Bool = false,
        number: Int = 0,
        published: PublicationDate? = nil,
        tags: [Tag] = [],
        blocks: [ContentBlock],
        brainstorming: String = ""
    ) {
        self.title = title
        self.slug = slug
        self.author = author
        self.emphasis = emphasis
        self.draft = draft
        self.number = number
        self.published = published
        self.tags = tags
        self.blocks = blocks
        self.brainstorming = brainstorming
    }

    /// Hand-written only for `brainstorming`'s sake: every article JSON file written
    /// before this field existed lacks the key, and a fully-synthesized `Decodable`
    /// would fail to decode them outright. `encode(to:)` stays synthesized (Swift
    /// synthesizes whichever `Codable` half isn't hand-written) — every future save
    /// writes the key, so this fallback only ever matters for the pre-existing files.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        slug = try container.decode(String.self, forKey: .slug)
        author = try container.decode(String.self, forKey: .author)
        emphasis = try container.decode(Emphasis.self, forKey: .emphasis)
        draft = try container.decode(Bool.self, forKey: .draft)
        number = try container.decode(Int.self, forKey: .number)
        published = try container.decodeIfPresent(PublicationDate.self, forKey: .published)
        tags = try container.decode([Tag].self, forKey: .tags)
        blocks = try container.decode([ContentBlock].self, forKey: .blocks)
        brainstorming = try container.decodeIfPresent(String.self, forKey: .brainstorming) ?? ""
    }
}

/// Filters out draft articles for a publish build; a dev build (`includeDrafts: true`) sees everything.
public func publishableArticles(_ articles: [Article], includeDrafts: Bool) -> [Article] {
    includeDrafts ? articles : articles.filter { !$0.draft }
}
