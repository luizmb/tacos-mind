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

    /// - Parameter blockIDs: each block's identity, from the world; a block without one (the
    ///   list shorter than the article's) is given its position's.
    public init(url: URL, article: Article, blockIDs: [UUID]) {
        self.url = url
        title = article.title
        slug = article.slug
        author = article.author
        emphasis = article.emphasis
        draft = article.draft
        number = article.number
        published = article.published
        tags = article.tags
        blocks = article.blocks.enumerated().map { index, block in
            EditableBlock(id: blockIDs.indices.contains(index) ? blockIDs[index] : .block(at: index), block: block)
        }
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

    /// Overwrites every editable field from `article` (block identities by position — undo/redo
    /// and revert aren't expected to preserve row identity across a full-content swap, and a
    /// position is an identity that needs nothing from outside),
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
        blocks = article.blocks.enumerated().map { index, block in EditableBlock(id: .block(at: index), block: block) }
        brainstorming = article.brainstorming
    }
}

public enum ExternalChangeState: Equatable, Sendable {
    case none
    case conflict(diskArticle: Article)
}

private extension UUID {
    /// A block's identity made from its position: unique within a document, the same for the
    /// same position every time, and made from bytes rather than minted.
    static func block(at index: Int) -> UUID {
        let n = UInt64(clamping: index)
        return UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            UInt8(truncatingIfNeeded: n >> 56), UInt8(truncatingIfNeeded: n >> 48),
            UInt8(truncatingIfNeeded: n >> 40), UInt8(truncatingIfNeeded: n >> 32),
            UInt8(truncatingIfNeeded: n >> 24), UInt8(truncatingIfNeeded: n >> 16),
            UInt8(truncatingIfNeeded: n >> 8), UInt8(truncatingIfNeeded: n)
        ))
    }
}
