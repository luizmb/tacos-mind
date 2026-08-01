import Foundation
import GeneratorCore

/// The article currently open for editing. Scalar fields are bindable form values;
/// `blocks` carries editor-only identity via `EditableBlock`. `currentArticle` is the
/// single source of truth handed to the parser/printer and diffed against
/// `originalSnapshot` on save — nothing else needs to reconstruct an `Article`.
public struct OpenDocument: Equatable, Sendable {
    public var url: URL
    public var title: String
    public var slug: String
    public var author: String
    public var emphasis: Emphasis
    public var draft: Bool
    public var number: Int
    public var published: PublicationDate?
    public var tags: [Tag]
    public var blocks: [EditableBlock]
    public var brainstorming: String

    public var originalSnapshot: Article
    public var lastWrittenHash: String?
    public var externalChange: ExternalChangeState

    /// Past states, most-recent last — `undo` pops here and pushes the current state to
    /// `redoStack`. Structural edits (add/remove/reorder block, tag toggle, …) push
    /// immediately; text edits push only once per debounced typing burst, via
    /// `pendingUndoCheckpoint`. Cleared on save and on load — see `ArticleEditorFeature`.
    public var undoStack: [Article]
    /// Future states, most-recent last — `redo` pops here and pushes the current state to
    /// `undoStack`. Cleared by any fresh edit made after undoing (standard branch
    /// truncation), and on save/load.
    public var redoStack: [Article]
    /// The state from *before* the in-progress text-editing burst, captured once at the
    /// burst's first keystroke and committed to `undoStack` either by the debounce firing
    /// (quiet elapsed) or by any other action flushing it first (see
    /// `ArticleEditorFeature.flushPendingUndoCheckpoint`). `nil` when no burst is in flight.
    public var pendingUndoCheckpoint: Article?

    public init(url: URL, article: Article) {
        self.url = url
        title = article.title
        slug = article.slug
        author = article.author
        emphasis = article.emphasis
        draft = article.draft
        number = article.number
        published = article.published
        tags = article.tags
        blocks = article.blocks.map { EditableBlock(id: UUID(), block: $0) }
        brainstorming = article.brainstorming
        originalSnapshot = article
        lastWrittenHash = nil
        externalChange = .none
        undoStack = []
        redoStack = []
        pendingUndoCheckpoint = nil
    }

    public var currentArticle: Article {
        Article(
            title: title,
            slug: slug,
            author: author,
            emphasis: emphasis,
            draft: draft,
            number: number,
            published: published,
            tags: tags,
            blocks: blocks.map(\.block),
            brainstorming: brainstorming
        )
    }

    public var hasUnsavedChanges: Bool {
        currentArticle != originalSnapshot
    }

    /// Overwrites every editable field from `article` (fresh block identities — undo/redo
    /// and revert aren't expected to preserve row identity across a full-content swap),
    /// leaving `originalSnapshot`/`lastWrittenHash`/`externalChange` untouched. Shared by
    /// undo, redo, and "Revert Changes" (which restores from `originalSnapshot`).
    public mutating func applyEditableFields(from article: Article) {
        title = article.title
        slug = article.slug
        author = article.author
        emphasis = article.emphasis
        draft = article.draft
        number = article.number
        published = article.published
        tags = article.tags
        blocks = article.blocks.map { EditableBlock(id: UUID(), block: $0) }
        brainstorming = article.brainstorming
    }
}

public enum ExternalChangeState: Equatable, Sendable {
    case none
    case conflict(diskArticle: Article)
}
