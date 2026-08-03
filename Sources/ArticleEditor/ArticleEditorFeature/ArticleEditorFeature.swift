import AppDomain
import FileWatching
import CoreFP
import CoreFPOperators
import Foundation
import GeneratorCore
import ReactiveConcurrency
import SwiftRex
import SwiftRexArchitecture
import SwiftRexOperators
import SwiftRexReactiveConcurrency
import SwiftUI

@Feature(strategy: .observationSimple)
public enum ArticleEditorFeature {
    public struct State: Sendable, Equatable {
        /// The sidebar entry this screen was pushed for — the identity the editor exists
        /// to edit, available from the moment the screen is constructed. `document` is
        /// `nil` until the file finishes loading, so this is what the sidebar highlight
        /// and the "which article is this?" question read instead.
        public var opened: ArticleSummary
        public var document: OpenDocument?
        public var allSummaries: [ArticleSummary]
        public var isSaving: Bool
        public var saveError: String?
        /// `true` while Cmd+B's full-site regenerate is running.
        public var isBuilding: Bool
        /// The last Build outcome, shown via the toolbar button's `.help(...)` — success
        /// or failure text, `nil` before the first Build.
        public var buildStatus: String?
        /// `true` while the "revert all unsaved changes?" confirmation is up — store
        /// state, not local SwiftUI `@State`, same convention as every other prompt here.
        public var isConfirmingRevert: Bool

        /// A fresh screen for `summary` — the file itself loads on `.start`. Seeding is
        /// construction, so there is no partly-filled editor for a caller to finish
        /// assembling, and no window in which this screen shows a previous article's data.
        public init(opening summary: ArticleSummary) {
            opened = summary
            document = nil
            allSummaries = []
            isSaving = false
            saveError = nil
            isBuilding = false
            buildStatus = nil
            isConfirmingRevert = false
        }
    }

    @Prisms
    public enum Action: Sendable {
        /// Dispatched by the view's `onAppear`. Loads `state.opened` — switching articles
        /// is a *new screen*, not a message to an existing one, so there is no `.open(URL)`
        /// and no "am I allowed to replace what's here?" gate; the app answers that
        /// question before this screen is ever built (see `AppNavigation`'s gates).
        case start
        /// Carries the URL that was actually loaded, so a load still in flight for the
        /// article the user just navigated away from cannot land in the screen that
        /// replaced it (the stack element is replaced, the in-flight effect is not).
        case opened(URL, Result<(article: Article, blockIDs: [UUID]), ArticleEditorError>)
        case allSummariesLoaded(Result<[ArticleSummary], ArticleEditorError>)

        case setTitle(String)
        case setSlug(String)
        case setAuthor(String)
        case setEmphasis(Emphasis)
        case setDraft(Bool)
        case setNumber(Int)
        case setPublished(PublicationDate?)
        case toggleTag(Tag)
        case setBrainstorming(String)

        case addBlock(ContentBlockKind, at: Int)
        case removeBlock(UUID)
        case moveBlocks(IndexSet, Int)
        case updateBlock(UUID, ContentBlock)

        case save
        case saved(Result<String, ArticleEditorError>)
        case requestRevert
        case cancelRevertConfirmation
        case revertChanges
        /// The app is about to be suspended (iOS backgrounding, a stand-in for "about to
        /// quit" — iOS gives apps no way to block termination, so this is the only real
        /// protection available there). Saves if there are unsaved changes; a no-op
        /// otherwise. Not user-facing, so it's absent from `ViewAction`.
        case appDidEnterBackground

        case undo
        case redo
        /// Fired by the debounced Cmd (`undoCheckpointCommitID`) after ~15s of no further
        /// text edits — flushes `pendingUndoCheckpoint` the "nothing else happened"
        /// way. Not user-facing, so it's absent from `ViewAction`.
        case commitPendingUndoCheckpoint

        case fileChangedOnDisk
        case diskHashChecked(Result<String, ArticleEditorError>)
        case diskArticleParsed(Result<Article, ArticleEditorError>)
        case reloaded(URL, Result<(article: Article, blockIDs: [UUID]), ArticleEditorError>)
        case keepMine
        case reloadTheirs

        /// Cmd+B — regenerates the entire site into `dist/`. No document required.
        case build
        case built(Result<Void, ArticleEditorError>)
        /// Cmd+R — regenerates just the current document's article and opens it in the
        /// system browser. Requires an open document (no-op otherwise, same guard style
        /// as `.save`).
        case run
        case ran(Result<URL, ArticleEditorError>)

        /// Opens the assistant, scoped to whatever article is currently open — handled by
        /// an app-level bridge (`AppFeature`'s `openChatBridge`), which is the only place
        /// that can reach across into `AIChatFeature`'s own sibling state.
        case openChat
    }

    public struct Environment: Sendable {
        public let openDocument: @Sendable (URL) -> Publisher<(article: Article, blockIDs: [UUID]), ArticleEditorError>
        public let saveDocument: @Sendable (OpenDocument) -> Publisher<String, ArticleEditorError>
        public let watchFile: @Sendable (URL) -> Publisher<FileWatchEvent, Never>
        public let checkDiskHash: @Sendable (URL) -> Publisher<String, ArticleEditorError>
        public let parseDiskArticle: @Sendable (URL) -> Publisher<Article, ArticleEditorError>
        public let listArticles: @Sendable () -> Publisher<[ArticleSummary], ArticleEditorError>
        public let generateArticle: @Sendable (String) -> Publisher<URL, ArticleEditorError>
        public let generateAllArticles: @Sendable () -> Publisher<Void, ArticleEditorError>
        public let openInBrowser: @MainActor @Sendable (URL) -> Void

        public init(
            openDocument: @escaping @Sendable (URL) -> Publisher<(article: Article, blockIDs: [UUID]), ArticleEditorError>,
            saveDocument: @escaping @Sendable (OpenDocument) -> Publisher<String, ArticleEditorError>,
            watchFile: @escaping @Sendable (URL) -> Publisher<FileWatchEvent, Never>,
            checkDiskHash: @escaping @Sendable (URL) -> Publisher<String, ArticleEditorError>,
            parseDiskArticle: @escaping @Sendable (URL) -> Publisher<Article, ArticleEditorError>,
            listArticles: @escaping @Sendable () -> Publisher<[ArticleSummary], ArticleEditorError>,
            generateArticle: @escaping @Sendable (String) -> Publisher<URL, ArticleEditorError>,
            generateAllArticles: @escaping @Sendable () -> Publisher<Void, ArticleEditorError>,
            openInBrowser: @escaping @MainActor @Sendable (URL) -> Void
        ) {
            self.openDocument = openDocument
            self.saveDocument = saveDocument
            self.watchFile = watchFile
            self.checkDiskHash = checkDiskHash
            self.parseDiskArticle = parseDiskArticle
            self.listArticles = listArticles
            self.generateArticle = generateArticle
            self.generateAllArticles = generateAllArticles
            self.openInBrowser = openInBrowser
        }
    }

    public struct ViewState: Sendable, Equatable {
        public var isDocumentOpen: Bool
        public var title: String
        public var slug: String
        public var author: String
        public var emphasis: Emphasis
        public var draft: Bool
        public var number: Int
        public var published: PublicationDate?
        public var tags: [Tag]
        public var allTags: [Tag]
        public var brainstorming: String
        public var blocks: [EditableBlock]
        public var allBlockKinds: [ContentBlockKind]
        public var hasUnsavedChanges: Bool
        public var isConfirmingRevert: Bool
        public var canUndo: Bool
        public var canRedo: Bool
        public var isSaving: Bool
        public var saveError: String?
        public var conflict: ExternalChangeState
        public var allSummaries: [ArticleSummary]
        public var isBuilding: Bool
        public var buildStatus: String?
    }

    @Prisms
    public enum ViewAction: Sendable {
        case onAppear
        case setTitle(String)
        case setSlug(String)
        case setAuthor(String)
        case setEmphasis(Emphasis)
        case setDraft(Bool)
        case setNumber(Int)
        case setPublished(PublicationDate?)
        case toggleTag(Tag)
        case setBrainstorming(String)
        case addBlock(ContentBlockKind, at: Int)
        case removeBlock(UUID)
        case moveBlocks(IndexSet, Int)
        case updateBlock(UUID, ContentBlock)
        case save
        case requestRevert
        case cancelRevertConfirmation
        case revertChanges
        case undo
        case redo
        case keepMine
        case reloadTheirs
        case build
        case run
        case openChat
    }

    public static let mapState = Reader<Environment, @MainActor @Sendable (State) -> ViewState> { _ in
        { state in
            ViewState(
                isDocumentOpen: state.document != nil,
                title: state.document?.title ?? "",
                slug: state.document?.slug ?? "",
                author: state.document?.author ?? "",
                emphasis: state.document?.emphasis ?? .text,
                draft: state.document?.draft ?? false,
                number: state.document?.number ?? 0,
                published: state.document?.published,
                tags: state.document?.tags ?? [],
                allTags: Tag.allCases,
                brainstorming: state.document?.brainstorming ?? "",
                blocks: state.document?.blocks ?? [],
                allBlockKinds: ContentBlockKind.allCases,
                hasUnsavedChanges: state.document?.hasUnsavedChanges ?? false,
                isConfirmingRevert: state.isConfirmingRevert,
                canUndo: state.document.map { $0.pendingUndoCheckpoint != nil || !$0.undoStack.isEmpty } ?? false,
                canRedo: state.document.map { !$0.redoStack.isEmpty } ?? false,
                isSaving: state.isSaving,
                saveError: state.saveError,
                conflict: state.document?.externalChange ?? .none,
                allSummaries: state.allSummaries,
                isBuilding: state.isBuilding,
                buildStatus: state.buildStatus
            )
        }
    }

    public static let mapAction = Reader<Environment, @Sendable (ViewAction) -> Action> { _ in
        { viewAction in
            switch viewAction {
            case .onAppear: .start
            case .setTitle(let value): .setTitle(value)
            case .setSlug(let value): .setSlug(value)
            case .setAuthor(let value): .setAuthor(value)
            case .setEmphasis(let value): .setEmphasis(value)
            case .setDraft(let value): .setDraft(value)
            case .setNumber(let value): .setNumber(value)
            case .setPublished(let value): .setPublished(value)
            case .toggleTag(let tag): .toggleTag(tag)
            case .setBrainstorming(let value): .setBrainstorming(value)
            case .addBlock(let kind, let index): .addBlock(kind, at: index)
            case .removeBlock(let id): .removeBlock(id)
            case .moveBlocks(let source, let destination): .moveBlocks(source, destination)
            case .updateBlock(let id, let block): .updateBlock(id, block)
            case .save: .save
            case .requestRevert: .requestRevert
            case .cancelRevertConfirmation: .cancelRevertConfirmation
            case .revertChanges: .revertChanges
            case .undo: .undo
            case .redo: .redo
            case .keepMine: .keepMine
            case .reloadTheirs: .reloadTheirs
            case .build: .build
            case .run: .run
            case .openChat: .openChat
            }
        }
    }

    public static func initialState(with summary: ArticleSummary) -> State { .init(opening: summary) }

    public static func behavior() -> Behavior<Action, State, Environment> {
        editingBehavior() <> fileWatchSupervisor()
    }

    // MARK: - Editing, saving, conflicts

    private static func editingBehavior() -> Behavior<Action, State, Environment> {
        .handle { action, context in
            switch action {
            // The screen was constructed for exactly one article, so there is nothing to
            // decide here: load it. Whether replacing whatever was previously on screen
            // is allowed (a live chat session, unsaved edits) was settled by the app's
            // navigation gates before this screen existed — see `AppNavigation`.
            case .start:
                guard let url = context.stateBefore?.opened.url else { return .doNothing }
                return .produce { _ in Effect<Action>.cancel(id: Self.undoCheckpointCommitID) }
                    .produce { ctx in ctx.environment.openDocument(url).asEffect { Action.opened(url, $0) } }
                    .produce { ctx in ctx.environment.listArticles().asEffect { Action.allSummariesLoaded($0) } }

            // A load for the article the user has since navigated away from must not land
            // here: the stack element was replaced, but the effect it started was not
            // cancelled, so it still arrives — addressed to this screen.
            case .opened(let url, .success(let result)):
                guard context.stateBefore?.opened.url == url else { return .doNothing }
                return .reduce { state in
                    var document = OpenDocument(url: url, article: result.article)
                    document.blocks = zip(result.blockIDs, result.article.blocks).map { EditableBlock(id: $0, block: $1) }
                    state.document = document
                }
                .produce { _ in Effect<Action>.cancel(id: Self.undoCheckpointCommitID) }

            case .opened(let url, .failure(let error)):
                guard context.stateBefore?.opened.url == url else { return .doNothing }
                return .reduce { $0.saveError = error.readableDescription }

            case .allSummariesLoaded(.success(let summaries)):
                return .reduce { $0.allSummaries = summaries }

            case .allSummariesLoaded(.failure):
                return .doNothing

            // Text edits: debounced. Only the burst's first keystroke captures a
            // checkpoint (and clears redo); the debounced Cmd below commits it after
            // ~15s of quiet, unless some other action flushes it first.
            case .setTitle(let value):
                return .reduce { state in Self.applyTextEdit(&state) { $0.title = value } }
                    .produce { _ in Self.debouncedUndoCheckpointCommit() }
            case .setSlug(let value):
                return .reduce { state in Self.applyTextEdit(&state) { $0.slug = value } }
                    .produce { _ in Self.debouncedUndoCheckpointCommit() }
            case .setAuthor(let value):
                return .reduce { state in Self.applyTextEdit(&state) { $0.author = value } }
                    .produce { _ in Self.debouncedUndoCheckpointCommit() }
            case .setBrainstorming(let value):
                return .reduce { state in Self.applyTextEdit(&state) { $0.brainstorming = value } }
                    .produce { _ in Self.debouncedUndoCheckpointCommit() }
            case .updateBlock(let id, let block):
                return .reduce { state in
                    Self.applyTextEdit(&state) { document in
                        guard let index = document.blocks.firstIndex(where: { $0.id == id }) else { return }
                        document.blocks[index].block = block
                    }
                }
                .produce { _ in Self.debouncedUndoCheckpointCommit() }

            // Structural edits: immediate — each commits its own undo step right away,
            // no debounce. First flushes any pending text checkpoint, so a structural
            // edit landing mid-burst can never race the debounce timer.
            case .setEmphasis(let value):
                return .reduce { state in Self.applyStructuralEdit(&state) { $0.emphasis = value } }
                    .produce { _ in Effect<Action>.cancel(id: Self.undoCheckpointCommitID) }
            case .setDraft(let value):
                return .reduce { state in Self.applyStructuralEdit(&state) { $0.draft = value } }
                    .produce { _ in Effect<Action>.cancel(id: Self.undoCheckpointCommitID) }
            case .setNumber(let value):
                return .reduce { state in Self.applyStructuralEdit(&state) { $0.number = value } }
                    .produce { _ in Effect<Action>.cancel(id: Self.undoCheckpointCommitID) }
            case .setPublished(let value):
                return .reduce { state in Self.applyStructuralEdit(&state) { $0.published = value } }
                    .produce { _ in Effect<Action>.cancel(id: Self.undoCheckpointCommitID) }

            case .toggleTag(let tag):
                return .reduce { state in
                    Self.applyStructuralEdit(&state) { document in
                        if let index = document.tags.firstIndex(of: tag) {
                            document.tags.remove(at: index)
                        } else {
                            document.tags.append(tag)
                        }
                    }
                }
                .produce { _ in Effect<Action>.cancel(id: Self.undoCheckpointCommitID) }

            case .addBlock(let kind, let index):
                return .reduce { state in
                    Self.applyStructuralEdit(&state) { document in
                        document.blocks.insert(EditableBlock(id: UUID(), block: kind.makeDefault()), at: index)
                    }
                }
                .produce { _ in Effect<Action>.cancel(id: Self.undoCheckpointCommitID) }

            case .removeBlock(let id):
                return .reduce { state in
                    Self.applyStructuralEdit(&state) { document in
                        document.blocks.removeAll { $0.id == id }
                    }
                }
                .produce { _ in Effect<Action>.cancel(id: Self.undoCheckpointCommitID) }

            case .moveBlocks(let source, let destination):
                return .reduce { state in
                    Self.applyStructuralEdit(&state) { document in
                        document.blocks.move(fromOffsets: source, toOffset: destination)
                    }
                }
                .produce { _ in Effect<Action>.cancel(id: Self.undoCheckpointCommitID) }

            case .save:
                guard let document = context.stateBefore?.document else { return .doNothing }
                return .reduce { $0.isSaving = true; $0.saveError = nil }
                    .produce { ctx in ctx.environment.saveDocument(document).asEffect { Action.saved($0) } }

            case .appDidEnterBackground:
                guard let document = context.stateBefore?.document, document.hasUnsavedChanges else { return .doNothing }
                return .reduce { $0.isSaving = true; $0.saveError = nil }
                    .produce { ctx in ctx.environment.saveDocument(document).asEffect { Action.saved($0) } }

            case .saved(.success(let hash)):
                return .reduce { state in
                    state.isSaving = false
                    guard let savedArticle = state.document?.currentArticle else { return }
                    state.document?.lastWrittenHash = hash
                    state.document?.originalSnapshot = savedArticle
                    // A save re-baselines the document: nothing left to step back to.
                    state.document?.undoStack = []
                    state.document?.redoStack = []
                    state.document?.pendingUndoCheckpoint = nil
                }
                .produce { _ in Effect<Action>.cancel(id: Self.undoCheckpointCommitID) }

            case .saved(.failure(let error)):
                return .reduce { $0.isSaving = false; $0.saveError = error.readableDescription }

            case .requestRevert:
                return .reduce { $0.isConfirmingRevert = true }

            case .cancelRevertConfirmation:
                return .reduce { $0.isConfirmingRevert = false }

            // Reverting re-baselines the document back to originalSnapshot, same as a
            // save or a load — there's nothing meaningful left to step back to, so the
            // undo/redo history is cleared, not pushed onto.
            case .revertChanges:
                return .reduce { state in
                    guard let snapshot = state.document?.originalSnapshot else { return }
                    state.document?.applyEditableFields(from: snapshot)
                    state.document?.undoStack = []
                    state.document?.redoStack = []
                    state.document?.pendingUndoCheckpoint = nil
                    state.isConfirmingRevert = false
                }
                .produce { _ in Effect<Action>.cancel(id: Self.undoCheckpointCommitID) }

            case .undo:
                return .reduce { state in
                    guard var document = state.document else { return }
                    Self.flushPendingUndoCheckpoint(&document)
                    guard let previous = document.undoStack.popLast() else { return }
                    document.redoStack.append(document.currentArticle)
                    document.applyEditableFields(from: previous)
                    state.document = document
                }
                .produce { _ in Effect<Action>.cancel(id: Self.undoCheckpointCommitID) }

            case .redo:
                return .reduce { state in
                    guard var document = state.document else { return }
                    Self.flushPendingUndoCheckpoint(&document)
                    guard let next = document.redoStack.popLast() else { return }
                    document.undoStack.append(document.currentArticle)
                    document.applyEditableFields(from: next)
                    state.document = document
                }
                .produce { _ in Effect<Action>.cancel(id: Self.undoCheckpointCommitID) }

            case .commitPendingUndoCheckpoint:
                return .reduce { state in
                    guard var document = state.document else { return }
                    Self.flushPendingUndoCheckpoint(&document)
                    state.document = document
                }

            case .fileChangedOnDisk:
                guard let url = context.stateBefore?.opened.url else { return .doNothing }
                return .produce { ctx in ctx.environment.checkDiskHash(url).asEffect { Action.diskHashChecked($0) } }

            case .diskHashChecked(.success(let hash)):
                guard let state = context.stateBefore, let document = state.document else { return .doNothing }
                guard hash != document.lastWrittenHash else { return .doNothing }
                let url = state.opened.url
                guard document.hasUnsavedChanges else {
                    return .produce { ctx in ctx.environment.openDocument(url).asEffect { Action.reloaded(url, $0) } }
                }
                return .produce { ctx in ctx.environment.parseDiskArticle(url).asEffect { Action.diskArticleParsed($0) } }

            case .diskHashChecked(.failure):
                return .doNothing

            case .diskArticleParsed(.success(let article)):
                return .reduce { $0.document?.externalChange = .conflict(diskArticle: article) }

            case .diskArticleParsed(.failure):
                return .doNothing

            case .reloaded(let url, .success(let result)):
                guard context.stateBefore?.opened.url == url else { return .doNothing }
                return .reduce { state in
                    state.document = OpenDocument(url: url, article: result.article)
                    state.document?.blocks = zip(result.blockIDs, result.article.blocks).map { EditableBlock(id: $0, block: $1) }
                }
                .produce { _ in Effect<Action>.cancel(id: Self.undoCheckpointCommitID) }

            case .reloaded(let url, .failure(let error)):
                guard context.stateBefore?.opened.url == url else { return .doNothing }
                return .reduce { $0.saveError = error.readableDescription }

            case .keepMine:
                return .reduce { $0.document?.externalChange = .none }

            case .reloadTheirs:
                guard let url = context.stateBefore?.opened.url else { return .doNothing }
                return .produce { ctx in ctx.environment.openDocument(url).asEffect { Action.reloaded(url, $0) } }

            case .build:
                return .reduce { $0.isBuilding = true; $0.buildStatus = nil }
                    .produce { ctx in ctx.environment.generateAllArticles().asEffect { Action.built($0) } }

            case .built(.success):
                return .reduce { $0.isBuilding = false; $0.buildStatus = "Build succeeded" }

            case .built(.failure(let error)):
                return .reduce { $0.isBuilding = false; $0.buildStatus = error.readableDescription }

            case .run:
                guard let document = context.stateBefore?.document else { return .doNothing }
                return .produce { ctx in ctx.environment.generateArticle(document.slug).asEffect { Action.ran($0) } }

            case .ran(.success(let url)):
                // `openInBrowser` is `@MainActor` (it wraps an AppKit/UIKit call), but
                // `.produce`'s closure isn't — the call has to happen inside the Effect's
                // own async body, same pattern as `AppFeature`'s `completeTermination` call.
                return .produce { ctx in
                    Publisher<Void, Never> { continuation in
                        await ctx.environment.openInBrowser(url)
                        continuation.finish()
                    }
                    .asEffect(Self.unreachableRanTransform)
                }

            case .ran(.failure(let error)):
                return .reduce { $0.saveError = error.readableDescription }

            // Purely a trigger for `AppFeature`'s `openChatBridge` — this feature never
            // touches `AIChatFeature`'s state directly (features stay decoupled, same
            // reasoning as `chatContextSyncBehavior`/`chatSaveToNotesBridge`).
            case .openChat:
                return .doNothing
            }
        }
    }

    /// The `openInBrowser` Publisher above never actually yields a value (it only ever
    /// `finish()`es), so this transform is never invoked — it exists only to satisfy
    /// `asEffect`'s signature. Mirrors `AppFeature`'s `unreachableActionTransform`.
    private static let unreachableRanTransform: @Sendable (()) -> Action = { _ in .cancelRevertConfirmation }

    // MARK: - Undo/redo

    private static let undoCheckpointCommitID = "undo-checkpoint-commit"

    /// The debounced Cmd every text-edit action re-fires: the Store's effect-scheduling
    /// engine coalesces repeated dispatches under the same id, restarting the wait each
    /// time, so `commitPendingUndoCheckpoint` only actually reaches the reducer once
    /// ~15s of quiet has passed — no manual timer/Subject bookkeeping needed. Ordering
    /// correctness never depends on this actually firing (see `applyStructuralEdit`,
    /// `.undo`, `.redo`, which all flush synchronously); it's the "user stopped typing
    /// and moved on to something else" case.
    private static func debouncedUndoCheckpointCommit() -> Effect<Action> {
        // `Never` conforms to `Error`, so a bare `const(...)` leaves `asEffect` unable to
        // pick between its `(Output) -> Action` and `(Result<Output, Failure>) -> Action`
        // overloads — this `let` pins the transform to the one we mean.
        let transform: @Sendable (()) -> Action = const(Action.commitPendingUndoCheckpoint)
        return Publisher<Void, Never>.just(())
            .asEffect(transform, scheduling: .debounce(id: undoCheckpointCommitID, delay: .seconds(15)))
    }

    /// Pushes any pending (uncommitted, still-debouncing) text-edit checkpoint onto
    /// `undoStack` and clears it. The shared first step of every undo/redo-touching
    /// action, so ordering never depends on the debounce timer's actual fire time — a
    /// structural edit, `.undo`, or `.redo` arriving mid-burst flushes it synchronously,
    /// right here, before doing anything else.
    private static func flushPendingUndoCheckpoint(_ document: inout OpenDocument) {
        guard let pending = document.pendingUndoCheckpoint else { return }
        document.undoStack.append(pending)
        document.pendingUndoCheckpoint = nil
    }

    /// Structural edits (add/remove/reorder block, tag toggle, emphasis/draft/number/
    /// published, revert) commit immediately: flush any pending text checkpoint first,
    /// clear redo (a fresh edit always invalidates "future"), push the pre-mutation
    /// state, then apply.
    private static func applyStructuralEdit(_ state: inout State, _ mutate: (inout OpenDocument) -> Void) {
        guard var document = state.document else { return }
        flushPendingUndoCheckpoint(&document)
        document.redoStack = []
        document.undoStack.append(document.currentArticle)
        mutate(&document)
        state.document = document
    }

    /// Text edits (title/slug/author/block content) debounce: only the first keystroke
    /// of a burst captures a checkpoint (and clears redo); later keystrokes in the same
    /// burst don't recapture — that's what coalesces a whole typing burst into one undo
    /// step instead of one per character.
    private static func applyTextEdit(_ state: inout State, _ mutate: (inout OpenDocument) -> Void) {
        guard var document = state.document else { return }
        if document.pendingUndoCheckpoint == nil {
            document.pendingUndoCheckpoint = document.currentArticle
            document.redoStack = []
        }
        mutate(&document)
        state.document = document
    }

    // MARK: - File watching (Subs)

    private static func fileWatchSupervisor() -> Behavior<Action, State, Environment> {
        .supervise { state in
            Supervision { env in
                // Keyed on `opened.url`, not `document?.url` — the screen knows which file
                // it is for before the load lands, and the watch has nothing to re-key
                // afterwards. Switching articles builds a *new* screen, so the old
                // subscription is torn down with the stack element it belonged to.
                let url = state.opened.url
                return [env.watchFile(url).asChannel(id: "file-watch-\(url.path)", { (_: FileWatchEvent) in Action.fileChangedOnDisk })]
            }
        }
    }

    public typealias Content = ArticleEditorView
}

extension ArticleEditorError {
    var readableDescription: String {
        switch self {
        case .fileReadFailed(let path, let reason): "Couldn't read \(path): \(reason)"
        case .fileWriteFailed(let path, let reason): "Couldn't write \(path): \(reason)"
        case .parseFailed(let path, let reason): "Couldn't parse \(path): \(reason)"
        }
    }
}
