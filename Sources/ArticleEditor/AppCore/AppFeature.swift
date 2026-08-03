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
import SwiftRexSwiftUI
import SwiftUI

// MARK: - AppFeature

/// The app is a `Feature` like any other: it owns state, actions and a behavior, and it
/// builds its own view. Nothing about the root is special-cased — which is the point.
///
/// `binding`, `presence` and `item` are declared on `StoreType`, which the concrete
/// `Store` conforms to and which SwiftUI cannot observe. Handing a bare `Store` to a
/// root view therefore compiles, dispatches correctly, reduces correctly — and never
/// re-renders. Going through the standard `Feature` machinery means the root's view store
/// is built exactly the way every other screen's is, so that failure stops being
/// expressible here rather than being something to remember.
///
/// It is also the app's coordinator: it holds the `World`, constructs the ``AppRouter``,
/// and injects it into the root view. Child screens are created by that router on demand
/// and never cached.
@Feature(strategy: .observationSimple)
public enum AppFeature {

    // MARK: - State

    public struct State: Sendable, Equatable {
        /// The sidebar — always on screen, so never optional.
        public var articleList: ArticleListFeature.State

        /// The pushed screens, each carrying its own state. One source of truth: there is
        /// no parallel table to keep in step, so a route and its data cannot disagree,
        /// and popping a screen disposes of its data because the data *is* the element.
        public var path: [StackEntry]

        /// The assistant panel. Allocated when presented, thrown away when dismissed —
        /// which is what makes "every open is a fresh conversation" structural rather
        /// than a reset the reducer has to remember.
        public var chat: Presentation<AIChatFeature.State>

        /// The GitHub Sync sheet, on the same terms as `chat`.
        public var gitHubSync: Presentation<GitHubSyncFeature.State>

        /// A navigation ask waiting on the user's answer to a gate it ran into. Replaces
        /// two mutually unaware holds that used to live in two different features.
        public var pendingNavigation: PendingNavigation?

        public var quitConfirmation: QuitConfirmationState

        public init() {
            articleList = ArticleListFeature.initialState(with: ())
            path = []
            chat = .dismissed
            gitHubSync = .dismissed
            pendingNavigation = nil
            quitConfirmation = .idle
        }
    }

    // MARK: - Action

    public enum Action: Sendable {
        case navigation(NavigationAction)
        case articleList(ArticleListFeature.Action)
        case articleEditor(ArticleEditorFeature.Action)
        case chat(AIChatFeature.Action)
        case gitHubSync(GitHubSyncFeature.Action)
        /// Dispatched by `AppDelegate.applicationShouldTerminate` — a thin translation of
        /// the OS callback, always followed by `.terminateLater`. Every actual decision
        /// (show the alert, wait for a save, tell AppKit to proceed) lives in
        /// `quitBehavior()`.
        case quitRequested
        case quitAlertResolved(QuitAlertChoice)
        case terminationOutcomeReady(Bool)
    }

    // MARK: - Environment

    public typealias Environment = World

    // No `ViewState`/`ViewAction`: the macro aliases them to `State`/`Action`, so the
    // root view's store is `ViewStore<AppState, AppAction>` — the whole app, which is
    // what a router needs in order to project children out of it.

    public static func initialState(with _: Void) -> State { .init() }

    // MARK: - View
    //
    // Hand-written rather than `typealias Content`: the generated `view()` passes only the
    // view store, and the root view also needs its router. This is the one place holding
    // the `World`, so it is the one place that can build a router — and the `World` goes
    // no further.

    @MainActor
    public static func view(store: any StoreType<Action, State>, environment: World) -> some View {
        AppRootView(
            viewStore: ViewStore(store),
            router: AppRouter(store: store, world: environment)
        )
    }

    // MARK: - Behavior

    public static func behavior() -> Behavior<Action, State, World> {
        // Each feature's own wiring sits with it: the lift, then the actions it sends
        // onward. Reading a feature's row tells you everything it participates in,
        // without a separate bridge somewhere else to cross-check.
        navigationBehavior()

        <> AppScopes.articleList.behavior(of: ArticleListFeature.self)
            // The whole sidebar → editor path, in one tacit line. `select`'s payload and
            // `NavigationRequest.articleEditor`'s are the same type on purpose.
            .on(.action(\.articleList.select), dispatch: .action(\.navigation.push.articleEditor))

        <> AppScopes.articleEditor.behavior(of: ArticleEditorFeature.self)
            .on(.action(\.articleEditor.openChat), dispatch: .action(review: const(.navigation(.presentChat))))

        <> AppScopes.chat.behavior(of: AIChatFeature.self)
            .on(.action(\.chat.notesCompacted), dispatch: .action(review: { .articleEditor(.setBrainstorming($0)) }))
            // Closing with nothing to lose needs no question — and a panel cannot dismiss
            // itself, so the app does it.
            .on(.action(\.chat.close), when: hasNoLiveChatSession, dispatch: .action(review: const(.navigation(.dismissChat))))
            // Either answer to the "save this conversation?" gate ends the session, so
            // both dismiss the panel *and* release whatever navigation was waiting on it.
            .on(.action(\.chat.confirmCloseAndDiscard), dispatch: .action(review: const(.navigation(.dismissChat))))
            .on(.action(\.chat.confirmCloseAndDiscard), dispatch: .action(review: const(.navigation(.resumePending))))
            .on(.action(\.chat.confirmCloseAndSave), dispatch: .action(review: const(.navigation(.dismissChat))))
            .on(.action(\.chat.confirmCloseAndSave), dispatch: .action(review: const(.navigation(.resumePending))))
            // Backing out of that question also backs out of whatever raised it — the
            // user stays where they are, with the conversation intact.
            .on(.action(\.chat.cancelClose), dispatch: .action(review: const(.navigation(.cancelPending))))

        <> AppScopes.gitHubSync.behavior(of: GitHubSyncFeature.self)
            .on(.action(\.gitHubSync.requestClose), dispatch: .action(review: const(.navigation(.dismissGitHubSync))))
            .on(.action(\.gitHubSync.firstSyncCompleted), dispatch: .action(review: const(.navigation(.dismissGitHubSync))))

        <> chatContextSyncBehavior()
        <> quitBehavior()
    }
}

/// Whether there is no assistant conversation worth asking about. Used as the `when`
/// guard on the "close needs no confirmation" bridge; also the condition
/// ``NavigationGate/chatSession`` inverts.
private let hasNoLiveChatSession: @Sendable (AppState) -> Bool = { $0.chat.wrapped?.turns.isEmpty ?? true }

// Familiar spellings for the app triad — `AppFeature.State` everywhere would only add noise.
public typealias AppState = AppFeature.State
public typealias AppAction = AppFeature.Action
public typealias MainStoreType = any StoreType<AppAction, AppState>
public typealias MainStore = Store<AppAction, AppState, World>

// MARK: - The app, as SwiftUI sees it

public extension AppState {
    /// The `Hashable` identities SwiftUI navigates by. Read-only — the path is the truth,
    /// this is a view of it. A screen's data can change all it likes without changing
    /// which screen it is.
    var routes: [AppRoute] { path.map(\.route) }

    /// The editor currently on top of the stack, if any.
    var openEditor: ArticleEditorFeature.State? {
        path.compactMap(StackEntry.prism.articleEditor.preview).last
    }

    /// The ask waiting on the "discard unsaved changes?" question, if that is the gate
    /// currently holding it. A genuine `Optional`, so `presence` is the right primitive.
    var discardPrompt: NavigationRequest? {
        pendingNavigation.flatMap { $0.gate == .unsavedDocument ? $0.request : nil }
    }
}

// MARK: - Quit confirmation (macOS only)

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

/// What the user picked in the "unsaved changes" quit alert (`World.confirmQuit`).
public enum QuitAlertChoice: Sendable, Equatable {
    case saveAndQuit
    case discardAndQuit
    case cancel
}

// MARK: - Store factory

extension MainStore {
    @MainActor
    public static func app(world: World) -> MainStoreType {
        Store(
            initial: AppState(),
            behavior: AppFeature.behavior(),
            environment: world
        )
    }
}

// MARK: - Chat context sync
//
// The assistant's long-term memory is the open article's Brainstorming field, but
// AIChatFeature never reads ArticleEditorFeature's state directly (features stay
// decoupled) — this mirrors it into the presented panel whenever it changes or a document
// is (re)opened, reading straight off each action's own payload. The panel's *initial*
// value is seeded at presentation time (see `NavigationAction.presentChat`), so this only
// has to keep an already-open panel current.

private func chatContextSyncBehavior() -> Behavior<AppAction, AppState, World> {
    Behavior<AppAction, AppState, World>.handle { action, _ in
        switch action {
        case .articleEditor(.setBrainstorming(let text)):
            return .reduce { $0.chat.wrapped?.brainstorming = text }
        case .articleEditor(.opened(_, .success(let result))):
            return .reduce { $0.chat.wrapped?.brainstorming = result.article.brainstorming }
        case .articleEditor(.reloaded(_, .success(let result))):
            return .reduce { $0.chat.wrapped?.brainstorming = result.article.brainstorming }
        default:
            return .doNothing
        }
    }
}

// MARK: - Quit confirmation
//
// AppDelegate.applicationShouldTerminate only ever dispatches `.quitRequested` and
// returns `.terminateLater` — every actual decision lives here. Every path funnels into
// `.terminationOutcomeReady`, so `World.completeTermination` (which calls back into
// AppKit) is invoked from exactly one place, regardless of how the user answered.

private func quitBehavior() -> Behavior<AppAction, AppState, World> {
    Behavior<AppAction, AppState, World>.handle { action, context in
        switch action {
        case .quitRequested:
            guard context.stateBefore?.openEditor?.document?.hasUnsavedChanges == true else {
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
    static func immediateDispatch(_ action: AppAction) -> Effect<AppAction> {
        let transform: @Sendable (()) -> AppAction = const(action)
        return Publisher<Void, Never>.just(()).asEffect(transform)
    }
}

/// A placeholder `(Void) -> AppAction` for effects that finish without ever yielding a
/// value — `asEffect` still needs a transform to satisfy its signature, even one that's
/// provably never called.
private let unreachableActionTransform: @Sendable (()) -> AppAction = { _ in .terminationOutcomeReady(false) }

// MARK: - Feature scopes
//
// One declaration per feature carrying all three axes — action, state, environment — so
// the same value drives the behavior fold *and* the router, and they cannot drift apart
// between the two uses. Only the sidebar gets a total state lane; everything else is
// **affine**, focusing the path element or the presentation slot the screen actually
// lives in. Reading and writing go through the same optic, so there is no derived copy
// and nothing to keep in step — and a child behavior can never write a screen that isn't
// on screen.

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
        .action(\.articleEditor)
        .state(preview: topmost(StackEntry.prism.articleEditor), set: replacing(StackEntry.prism.articleEditor))
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
        .action(\.chat)
        .state(preview: { $0.chat.wrapped }, set: { state, chat in
            var updated = state
            // `Presentation.wrapped`'s setter preserves the stage and ignores a write
            // while `dismissed`, so a late effect landing mid-dismissal can update the
            // panel's content but can never resurrect the panel.
            updated.chat.wrapped = chat
            return updated
        })
        .environment { (world: World) in
            AIChatFeature.Environment(
                isAssistantAvailable: world.isAssistantAvailable,
                chatRespond: world.chatRespond,
                speak: world.speak,
                startListening: world.startListening
            )
        }

    public static let gitHubSync = ScopeOf<AppScopes>
        .action(\.gitHubSync)
        .state(preview: { $0.gitHubSync.wrapped }, set: { state, sync in
            var updated = state
            updated.gitHubSync.wrapped = sync
            return updated
        })
        .environment { (world: World) in
            GitHubSyncFeature.Environment(
                loadGitHubSettings: world.loadGitHubSettings,
                linkRepository: world.linkRepository,
                updateBranch: world.updateBranch,
                unlinkRepository: world.unlinkRepository,
                isArticlesDirEmpty: world.isArticlesDirEmpty,
                previewPull: world.previewPull,
                applyPull: world.applyPull,
                commitLocalChanges: world.commitLocalChanges,
                openPullRequest: world.openPullRequest
            )
        }
}

// MARK: - The affine focus a pushed screen lives behind
//
// Both halves go through the same prism, so a read and a write can never disagree about
// which element they mean. `replacing` only ever overwrites an element that is already
// there — it cannot append, so a child behavior can never conjure a screen navigation
// did not push.

private func topmost<S>(_ prism: Prism<StackEntry, S>) -> @Sendable (AppState) -> S? {
    { $0.path.compactMap(prism.preview).last }
}

private func replacing<S>(_ prism: Prism<StackEntry, S>) -> @Sendable (AppState, S) -> AppState {
    { state, screen in
        guard let index = state.path.lastIndex(where: { prism.preview($0) != nil }) else { return state }
        var updated = state
        updated.path[index] = prism.review(screen)
        return updated
    }
}
