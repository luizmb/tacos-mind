import AIChatFeature
import AppDomain
import ArticleEditorFeature
import ArticleListFeature
import CoreFP
import CoreFPOperators
import FPMacros
import Foundation
import GitHubSyncFeature
import ReactiveConcurrency
import SwiftRex
import SwiftRexArchitecture
import SwiftRexOperators
import SwiftRexReactiveConcurrency

// MARK: - AppState

@Lenses
public struct AppState: Sendable {
    public var articleList: ArticleListFeature.State
    public var articleEditor: ArticleEditorFeature.State
    public var chat: AIChatFeature.State
    public var gitHubSync: GitHubSyncFeature.State
    public var quitConfirmation: QuitConfirmationState
    /// Set while an article switch is on hold because the chat panel has an active
    /// session — the switch resumes once that's resolved (saved or discarded), or is
    /// dropped entirely if the user cancels. See `bridgeBehavior`/`continueArticleSwitchBridge`.
    public var pendingArticleSwitch: URL?

    public init() {
        articleList = ArticleListFeature.initialState(with: ())
        articleEditor = ArticleEditorFeature.initialState(with: ())
        chat = AIChatFeature.initialState(with: ())
        gitHubSync = GitHubSyncFeature.initialState(with: ())
        quitConfirmation = .idle
        pendingArticleSwitch = nil
    }
}

/// The in-flight "app is about to quit" flow (macOS only — see `AppDelegate`; iOS has no
/// way to intercept termination at all, so it relies on `ArticleEditorFeature`'s
/// `appDidEnterBackground` save instead). Whichever path a quit takes,
/// `World.completeTermination` is called exactly once, at the same moment
/// `quitConfirmation` resets to `.idle`.
public enum QuitConfirmationState: Sendable, Equatable {
    case idle
    /// The confirmation alert is up, waiting on the user's choice.
    case confirmingWithUser
    /// The user chose "Save and Quit"; waiting for `ArticleEditorFeature.Action.saved` to
    /// actually arrive before completing termination.
    case waitingForSaveThenQuit
}

// MARK: - AppAction

@Prisms
public enum AppAction: Sendable {
    case articleList(ArticleListFeature.Action)
    case articleEditor(ArticleEditorFeature.Action)
    case chat(AIChatFeature.Action)
    case gitHubSync(GitHubSyncFeature.Action)
    /// Dispatched by `AppDelegate.applicationShouldTerminate` — a thin translation of the
    /// OS callback, always followed by `.terminateLater`. Every actual decision (show the
    /// alert, wait for a save, tell AppKit to proceed) lives in `quitBehavior()`.
    case quitRequested
    case quitAlertResolved(QuitAlertChoice)
    case terminationOutcomeReady(Bool)
}

/// What the user picked in the "unsaved changes" quit alert (`World.confirmQuit`).
public enum QuitAlertChoice: Sendable, Equatable {
    case saveAndQuit
    case discardAndQuit
    case cancel
}

public typealias MainStoreType = any StoreType<AppAction, AppState>
public typealias MainStore = Store<AppAction, AppState, World>

// MARK: - Store factory

extension MainStore {
    @MainActor
    public static func app(world: World) -> MainStoreType {
        Store(
            initial: AppState(),
            behavior: behavior(),
            environment: world
        )
    }

    private static func behavior() -> Behavior<AppAction, AppState, World> {
        AppScopes.articleList.behavior(of: ArticleListFeature.self)
            <> AppScopes.articleEditor.behavior(of: ArticleEditorFeature.self)
            <> AppScopes.chat.behavior(of: AIChatFeature.self)
            <> AppScopes.gitHubSync.behavior(of: GitHubSyncFeature.self)
            <> bridgeBehavior()
            <> selectionSyncBehavior()
            <> chatContextSyncBehavior()
            <> chatSaveToNotesBridge()
            <> openChatBridge()
            <> articleSwitchGateBridge()
            <> quitBehavior()
    }
}

// MARK: - Bridge behavior
//
// Picking an article in the sidebar opens it in the editor — but if the chat panel has
// an active session, that decision (save or discard it into Brainstorming) has to be
// made FIRST: the switch is held in `pendingArticleSwitch` and only resumes once
// `articleSwitchGateBridge` sees the chat session actually end. Everything else (IO,
// file watching, conflicts) lives inside ArticleEditorFeature's own behavior.

private func bridgeBehavior() -> Behavior<AppAction, AppState, World> {
    Behavior<AppAction, AppState, World>.handle { action, context in
        // A freshly created article opens exactly the same way tapping it in the
        // sidebar would — same gate, same reasoning, just a different trigger action.
        let summary: ArticleSummary
        switch action {
        case .articleList(.select(let selected)): summary = selected
        case .articleList(.created(.success(let created))): summary = created
        default: return .doNothing
        }
        guard let turns = context.stateBefore?.chat.turns, !turns.isEmpty else {
            return .produce { _ in AppAction.immediateDispatch(.articleEditor(.open(summary.url))) }
        }
        return .reduce { $0.pendingArticleSwitch = summary.url }
            .produce { _ in AppAction.immediateDispatch(.chat(.close)) }
    }
}

// MARK: - Article switch gate
//
// Resolves whatever `bridgeBehavior` put on hold: once the chat session's close is
// decided (saved-and-closed or discarded-and-closed), resume the switch that was
// waiting on it. Cancelling the chat confirmation cancels the switch too — the user
// stays on the current article with the conversation intact.

private func articleSwitchGateBridge() -> Behavior<AppAction, AppState, World> {
    Behavior<AppAction, AppState, World>.handle { action, context in
        switch action {
        case .chat(.confirmCloseAndDiscard), .chat(.confirmCloseAndSave):
            guard let url = context.stateBefore?.pendingArticleSwitch else { return .doNothing }
            return .reduce { $0.pendingArticleSwitch = nil }
                .produce { _ in AppAction.immediateDispatch(.articleEditor(.open(url))) }
        case .chat(.cancelClose):
            guard context.stateBefore?.pendingArticleSwitch != nil else { return .doNothing }
            return .reduce { $0.pendingArticleSwitch = nil }
        default:
            return .doNothing
        }
    }
}

// MARK: - Selection sync
//
// The sidebar's highlighted row reflects whatever's actually open in the editor, not
// whatever was last tapped — tapping a row while the current document has unsaved
// changes can defer or cancel the switch (see ArticleEditorFeature's pendingOpenURL), so
// ArticleListFeature.select deliberately does NOT set selectedSlug itself. This behavior
// updates it only once the editor actually confirms a document is open.

private func selectionSyncBehavior() -> Behavior<AppAction, AppState, World> {
    Behavior<AppAction, AppState, World>.handle { action, _ in
        switch action {
        case .articleEditor(.opened(_, .success(let result))):
            return .reduce { $0.articleList.selectedSlug = result.article.slug }
        case .articleEditor(.reloaded(.success(let result))):
            return .reduce { $0.articleList.selectedSlug = result.article.slug }
        default:
            return .doNothing
        }
    }
}

// MARK: - Chat context sync
//
// The assistant's long-term memory is the open article's Brainstorming field, but
// AIChatFeature never reads ArticleEditorFeature's state directly (features stay
// decoupled) — this mirrors it into `chat.brainstorming` whenever it changes or a
// document is (re)opened, reading straight off each action's own payload, exactly like
// `selectionSyncBehavior` above.

private func chatContextSyncBehavior() -> Behavior<AppAction, AppState, World> {
    Behavior<AppAction, AppState, World>.handle { action, _ in
        switch action {
        case .articleEditor(.setBrainstorming(let text)):
            return .reduce { $0.chat.brainstorming = text }
        case .articleEditor(.opened(_, .success(let result))):
            return .reduce { $0.chat.brainstorming = result.article.brainstorming }
        case .articleEditor(.reloaded(.success(let result))):
            return .reduce { $0.chat.brainstorming = result.article.brainstorming }
        default:
            return .doNothing
        }
    }
}

// MARK: - Save to Notes bridge
//
// AIChatFeature computes the compaction itself (`.saveToNotes`/`.confirmCloseAndSave`
// both fire `notesCompacted` with the text already built) — only the actual write needs
// ArticleEditorFeature's own `setBrainstorming` (so the edit participates in undo/redo
// like any other text edit), which only this app-level bridge can reach.

private func chatSaveToNotesBridge() -> Behavior<AppAction, AppState, World> {
    Behavior<AppAction, AppState, World>.identity
        .on(
            .action(\.chat.notesCompacted),
            dispatch: .action(review: { text in .articleEditor(.setBrainstorming(text)) })
        )
}

// MARK: - Open chat bridge
//
// The assistant is conceptually a CHILD of whichever article is open — it reads/writes
// that article's Brainstorming (see `chatContextSyncBehavior`/`chatSaveToNotesBridge`
// above) — so its entry point lives inside the article editor's own UI (a button next to
// Brainstorming), not a standalone top-level toolbar button. `.openChat` is that trigger;
// only this app-level bridge can reach across into `AIChatFeature`'s sibling state.

private func openChatBridge() -> Behavior<AppAction, AppState, World> {
    Behavior<AppAction, AppState, World>.identity
        .on(.action(\.articleEditor.openChat), dispatch: .action(\.chat.open))
}

// MARK: - Quit confirmation (macOS only)
//
// AppDelegate.applicationShouldTerminate only ever dispatches `.quitRequested` and
// returns `.terminateLater` — every actual decision lives here. Every path funnels into
// `.terminationOutcomeReady`, so `World.completeTermination` (which calls back into
// AppKit) is invoked from exactly one place, regardless of how the user answered.

private func quitBehavior() -> Behavior<AppAction, AppState, World> {
    Behavior<AppAction, AppState, World>.handle { action, context in
        switch action {
        case .quitRequested:
            guard context.stateBefore?.articleEditor.document?.hasUnsavedChanges == true else {
                return .produce { _ in AppAction.immediateDispatch(.terminationOutcomeReady(true)) }
            }
            return .reduce { $0.quitConfirmation = .confirmingWithUser }
                .produce { ctx in ctx.environment.confirmQuit().asEffect { AppAction.quitAlertResolved($0) } }

        case .quitAlertResolved(.saveAndQuit):
            return .reduce { $0.quitConfirmation = .waitingForSaveThenQuit }
                .produce { _ in AppAction.immediateDispatch(.articleEditor(.save)) }

        case .quitAlertResolved(.discardAndQuit):
            return .produce { _ in AppAction.immediateDispatch(.terminationOutcomeReady(true)) }

        case .quitAlertResolved(.cancel):
            return .reduce { $0.quitConfirmation = .idle }
                .produce { _ in AppAction.immediateDispatch(.terminationOutcomeReady(false)) }

        case .terminationOutcomeReady(let shouldTerminate):
            // `completeTermination` is `@MainActor` (it wraps an AppKit call), but
            // `.produce`'s closure isn't — the actual call has to happen inside the
            // Effect's own async body, which can `await` across that hop; the closure
            // here only ever constructs the Effect value, synchronously.
            return .reduce { $0.quitConfirmation = .idle }
                .produce { ctx in
                    Publisher<Void, Never> { continuation in
                        await ctx.environment.completeTermination(shouldTerminate)
                        continuation.finish()
                    }
                    // The Publisher above never actually yields a value (it only ever
                    // `finish()`es), so this transform is never invoked — it exists only
                    // to satisfy `asEffect`'s signature.
                    .asEffect(unreachableActionTransform)
                }

        default:
            return .doNothing
        }
    }
    <> waitForSaveThenQuitBridge()
}

/// The user chose "Save and Quit": bridges the editor's own save-completion action back
/// into the quit flow, but only while we're actually waiting on it — an unrelated save
/// (the user hitting the toolbar Save button mid-flow, say) elsewhere wouldn't set
/// `quitConfirmation` to `.waitingForSaveThenQuit` in the first place, so this `when`
/// can't misfire.
private func waitForSaveThenQuitBridge() -> Behavior<AppAction, AppState, World> {
    Behavior<AppAction, AppState, World>.identity
        .on(
            .action(\.articleEditor.saved),
            when: { $0.quitConfirmation == .waitingForSaveThenQuit },
            dispatch: .action(review: { result in
                switch result {
                case .success: .terminationOutcomeReady(true)
                case .failure: .terminationOutcomeReady(false)
                }
            })
        )
}

extension AppAction {
    /// Fires `action` as an immediate follow-up dispatch from within a `.produce` step —
    /// the same "wrap a pure value in a one-shot Effect" trick used for the debounced
    /// undo checkpoint, just without the `.debounce` scheduling.
    fileprivate static func immediateDispatch(_ action: AppAction) -> Effect<AppAction> {
        let transform: @Sendable (()) -> AppAction = const(action)
        return Publisher<Void, Never>.just(()).asEffect(transform)
    }
}

/// A placeholder `(Void) -> AppAction` for effects that finish without ever yielding a
/// value — `asEffect` still needs a transform to satisfy its signature, even though one
/// that's provably never called.
private let unreachableActionTransform: @Sendable (()) -> AppAction = { _ in .terminationOutcomeReady(false) }

// MARK: - Feature scopes

public enum AppScopes: Rig {
    public typealias Action = AppAction
    public typealias State = AppState
    public typealias Environment = World

    public static let articleList = ScopeOf<AppScopes>
        .action(\.articleList).state(\.articleList)
        .environment { (world: World) in
            ArticleListFeature.Environment(listArticles: world.listArticles, createArticle: world.createArticle)
        }

    public static let articleEditor = ScopeOf<AppScopes>
        .action(\.articleEditor).state(\.articleEditor)
        .environment { (world: World) in
            ArticleEditorFeature.Environment(
                openDocument: world.openDocument,
                saveDocument: world.saveDocument,
                watchFile: world.watchFile,
                checkDiskHash: world.checkDiskHash,
                parseDiskArticle: world.parseDiskArticle,
                listArticles: world.listArticles,
                generateArticle: world.generateArticle,
                generateAllArticles: world.generateAllArticles,
                openInBrowser: world.openInBrowser
            )
        }

    public static let chat = ScopeOf<AppScopes>
        .action(\.chat).state(\.chat)
        .environment { (world: World) in
            AIChatFeature.Environment(
                isAssistantAvailable: world.isAssistantAvailable,
                chatRespond: world.chatRespond,
                speak: world.speak,
                startListening: world.startListening
            )
        }

    public static let gitHubSync = ScopeOf<AppScopes>
        .action(\.gitHubSync).state(\.gitHubSync)
        .environment { (world: World) in
            GitHubSyncFeature.Environment(
                loadGitHubSettings: world.loadGitHubSettings,
                saveGitHubSettings: world.saveGitHubSettings,
                previewPull: world.previewPull,
                applyPull: world.applyPull,
                commitLocalChanges: world.commitLocalChanges,
                openPullRequest: world.openPullRequest
            )
        }
}
