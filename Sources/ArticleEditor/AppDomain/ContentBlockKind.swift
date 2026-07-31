import GeneratorCore

/// The block types a user can insert via the editor's "add block" menu. `.equation` is
/// deliberately excluded — it's parsed and round-tripped when present in a file, but
/// nobody authors a new one through this UI in v1.
public enum ContentBlockKind: String, CaseIterable, Identifiable, Sendable {
    case heading
    case paragraph
    case list
    case image
    case video
    case code

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .heading: "Heading"
        case .paragraph: "Paragraph"
        case .list: "List"
        case .image: "Image"
        case .video: "Video"
        case .code: "Code"
        }
    }

    public func makeDefault() -> ContentBlock {
        switch self {
        case .heading: .heading(level: .section, text: "")
        case .paragraph: .paragraph("")
        case .list: .list(items: [""])
        case .image: .image(url: "", altText: "")
        case .video: .video(url: "", caption: nil)
        case .code: .code(language: .swift, source: "")
        }
    }
}
