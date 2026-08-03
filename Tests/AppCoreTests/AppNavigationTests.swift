import AIChatFeature
import AppDomain
import ArticleEditorFeature
import Foundation
import GeneratorCore
import GitHubSyncFeature
import SwiftRex
import SwiftRexTesting
import Testing

@testable import AppCore

/// There is no invariant test in here policing "a route agrees with its state", and that
/// is the point: a screen's state lives *in* the `path` element, so "a route without its
/// state" cannot be constructed. The previous design needed a bridge to keep two stores
/// in step; this one makes the disagreement a type error.
@Suite("App navigation")
@MainActor
struct AppNavigationTests {
    private func summary(_ slug: String, number: Int = 1) -> ArticleSummary {
        ArticleSummary(
            url: URL(fileURLWithPath: "/tmp/Articles/\(slug).json"),
            slug: slug,
            title: "Title for \(slug)",
            number: number
        )
    }

    // `World` alone is ambiguous here: `GeneratorCore` has one too, and this suite needs
    // `Article` from it.
    private func makeStore(initial: AppState = .init()) -> TestStore<AppAction, AppState, AppCore.World> {
        TestStore(
            initial: initial,
            behavior: navigationBehavior(),
            environment: AppCore.World.mock()
        )
    }

    private func editor(for summary: ArticleSummary, brainstorming: String = "") -> ArticleEditorFeature.State {
        var editor = ArticleEditorFeature.State(opening: summary)
        var document = OpenDocument(
            url: summary.url,
            article: Article(title: summary.title, slug: summary.slug, emphasis: .text, blocks: [.paragraph("Body")])
        )
        document.brainstorming = brainstorming
        editor.document = document
        return editor
    }

    private func dirtyEditor(for summary: ArticleSummary) -> ArticleEditorFeature.State {
        var editor = editor(for: summary)
        editor.document?.title = "Edited, and not saved"
        #expect(editor.document?.hasUnsavedChanges == true)
        return editor
    }

    // MARK: - Push

    @Test("push builds the whole screen, so there is never a half-filled one to finish")
    func pushHydratesTheEntry() async throws {
        let target = summary("pure-functions")
        let store = makeStore()

        store.dispatch(.navigation(.push(.articleEditor(target)))) { state in
            state.path = [.articleEditor(ArticleEditorFeature.State(opening: target))]
            state.articleList.selectedSlug = target.slug
        }

        #expect(store.state.routes == [.articleEditor])
        // Nothing is loaded yet — that is the screen's own `.start`, not navigation's job.
        #expect(store.state.openEditor?.document == nil)
    }

    /// Opening a second article must not stack a second editor, and must not make SwiftUI
    /// tear the first one down and re-push it. Both fall out of `AppRoute` being
    /// payload-free: the element is replaced, `routes` comes out identical.
    @Test("pushing onto an open editor replaces it in place, leaving routes identical")
    func pushCollapsesOntoAnOpenEditor() async throws {
        let first = summary("pure-functions")
        let second = summary("side-effects", number: 2)
        var initial = AppState()
        initial.path = [.articleEditor(ArticleEditorFeature.State(opening: first))]
        initial.articleList.selectedSlug = first.slug
        let store = makeStore(initial: initial)
        let routesBefore = store.state.routes

        store.dispatch(.navigation(.push(.articleEditor(second)))) { state in
            state.path = [.articleEditor(ArticleEditorFeature.State(opening: second))]
            state.articleList.selectedSlug = second.slug
        }

        #expect(store.state.path.count == 1)
        #expect(store.state.routes == routesBefore)
    }

    @Test("push re-derives the sidebar highlight, and popping clears it")
    func pushAndPopKeepTheSidebarHonest() async throws {
        let target = summary("pure-functions")
        let store = makeStore()

        store.dispatch(.navigation(.push(.articleEditor(target)))) { state in
            state.path = [.articleEditor(ArticleEditorFeature.State(opening: target))]
            state.articleList.selectedSlug = target.slug
        }

        store.dispatch(.navigation(.pop)) { state in
            state.path = []
            state.articleList.selectedSlug = nil
        }
    }

    // MARK: - Pop / setPath

    @Test("popToRoot empties the stack and the highlight with it")
    func popToRootClearsEverything() async throws {
        let target = summary("pure-functions")
        var initial = AppState()
        initial.path = [.articleEditor(ArticleEditorFeature.State(opening: target))]
        initial.articleList.selectedSlug = target.slug
        let store = makeStore(initial: initial)

        store.dispatch(.navigation(.popToRoot)) { state in
            state.path = []
            state.articleList.selectedSlug = nil
        }
    }

    @Test("pop on an empty stack changes nothing")
    func popOnAnEmptyStackIsANoOp() async throws {
        let store = makeStore()
        store.dispatch(.navigation(.pop)) { _ in }
        #expect(store.state == AppState())
    }

    /// This is what the system back button and back-swipe deliver. Folding to the longest
    /// matching prefix is total — an unexpected path truncates rather than leaving `path`
    /// disagreeing with what is on screen.
    @Test("setPath truncates to the longest prefix that still matches the real stack")
    func setPathFoldsToTheLongestMatchingPrefix() async throws {
        let target = summary("pure-functions")
        var initial = AppState()
        initial.path = [.articleEditor(ArticleEditorFeature.State(opening: target))]
        initial.articleList.selectedSlug = target.slug
        let store = makeStore(initial: initial)

        store.dispatch(.navigation(.setPath([]))) { state in
            state.path = []
            state.articleList.selectedSlug = nil
        }
    }

    @Test("setPath cannot conjure a screen that was never pushed")
    func setPathCannotGrowTheStack() async throws {
        let store = makeStore()

        store.dispatch(.navigation(.setPath([.articleEditor]))) { _ in }

        #expect(store.state.path.isEmpty)
    }

    // MARK: - Gates

    @Test("a live conversation parks the push and asks the chat to close")
    func aLiveChatSessionParksThePush() async throws {
        var chat = AIChatFeature.State()
        chat.turns = [ChatTurn(role: .user, text: "Hi")]
        var initial = AppState()
        initial.chat = .presented(chat)
        let store = makeStore(initial: initial)
        let target = summary("pure-functions")

        store.dispatch(.navigation(.push(.articleEditor(target)))) { state in
            state.pendingNavigation = PendingNavigation(request: .articleEditor(target), gate: .chatSession)
        }

        #expect(store.state.path.isEmpty)

        await store.runEffects()
        store.receive(AppAction.prism.chat) { action, _ in
            #expect(AIChatFeature.Action.prism.close.preview(action) != nil)
        }
    }

    @Test("unsaved edits park the push behind the discard prompt")
    func unsavedEditsParkThePush() async throws {
        let open = summary("pure-functions")
        let target = summary("side-effects", number: 2)
        var initial = AppState()
        initial.path = [.articleEditor(dirtyEditor(for: open))]
        initial.articleList.selectedSlug = open.slug
        let store = makeStore(initial: initial)

        store.dispatch(.navigation(.push(.articleEditor(target)))) { state in
            state.pendingNavigation = PendingNavigation(request: .articleEditor(target), gate: .unsavedDocument)
        }

        #expect(store.state.openEditor?.opened == open)
        #expect(store.state.discardPrompt == .articleEditor(target))
    }

    /// The gate is about losing *someone else's* edits. Re-opening the article already on
    /// screen loses nothing, so it must not ask.
    @Test("re-opening the article already on screen never asks about discarding")
    func reopeningTheSameArticleAsksNothing() async throws {
        let open = summary("pure-functions")
        var initial = AppState()
        initial.path = [.articleEditor(dirtyEditor(for: open))]
        initial.articleList.selectedSlug = open.slug
        let store = makeStore(initial: initial)

        store.dispatch(.navigation(.push(.articleEditor(open)))) { state in
            // Rebuilt fresh, so the unsaved edits go with it — but no question was asked,
            // because the user asked for the article they were already on.
            state.path = [.articleEditor(ArticleEditorFeature.State(opening: open))]
        }

        #expect(store.state.pendingNavigation == nil)
    }

    /// Gates are ordered and each answer resumes at the *next* one. This is the case that
    /// made the two-gate resume worth writing down: answering the chat must hand over to
    /// the discard question rather than pushing straight through it.
    @Test("answering the chat gate hands over to the discard gate, not to the push")
    func resumingFromTheChatGateFallsIntoTheDiscardGate() async throws {
        let open = summary("pure-functions")
        let target = summary("side-effects", number: 2)
        var initial = AppState()
        initial.path = [.articleEditor(dirtyEditor(for: open))]
        initial.articleList.selectedSlug = open.slug
        initial.chat = .presented(AIChatFeature.State())
        initial.pendingNavigation = PendingNavigation(request: .articleEditor(target), gate: .chatSession)
        let store = makeStore(initial: initial)

        store.dispatch(.navigation(.resumePending)) { state in
            state.pendingNavigation = PendingNavigation(request: .articleEditor(target), gate: .unsavedDocument)
        }

        #expect(store.state.path.count == 1)
        #expect(store.state.openEditor?.opened == open)
    }

    /// The mirror image, and the reason a gate resumes at its *successor* rather than
    /// being re-evaluated from the start: the same dirty document is still there, so a
    /// naive re-check would park on it again, forever.
    @Test("answering the discard gate pushes, without re-asking the question just answered")
    func resumingFromTheDiscardGateActuallyPushes() async throws {
        let open = summary("pure-functions")
        let target = summary("side-effects", number: 2)
        var initial = AppState()
        initial.path = [.articleEditor(dirtyEditor(for: open))]
        initial.articleList.selectedSlug = open.slug
        initial.pendingNavigation = PendingNavigation(request: .articleEditor(target), gate: .unsavedDocument)
        let store = makeStore(initial: initial)

        store.dispatch(.navigation(.resumePending)) { state in
            state.pendingNavigation = nil
            state.path = [.articleEditor(ArticleEditorFeature.State(opening: target))]
            state.articleList.selectedSlug = target.slug
        }
    }

    @Test("cancelling drops the parked ask and leaves the user where they were")
    func cancelPendingDropsTheAsk() async throws {
        let open = summary("pure-functions")
        var initial = AppState()
        initial.path = [.articleEditor(dirtyEditor(for: open))]
        initial.articleList.selectedSlug = open.slug
        initial.pendingNavigation = PendingNavigation(
            request: .articleEditor(summary("side-effects", number: 2)),
            gate: .unsavedDocument
        )
        let store = makeStore(initial: initial)

        store.dispatch(.navigation(.cancelPending)) { $0.pendingNavigation = nil }

        #expect(store.state.discardPrompt == nil)
        #expect(store.state.openEditor?.opened == open)
    }

    // MARK: - Presentations

    @Test("presenting the chat seeds it from the open article's notes")
    func presentingTheChatSeedsItFromTheArticle() async throws {
        let open = summary("pure-functions")
        var initial = AppState()
        initial.path = [.articleEditor(editor(for: open, brainstorming: "Half-formed thoughts"))]
        initial.articleList.selectedSlug = open.slug
        let store = makeStore(initial: initial)

        store.dispatch(.navigation(.presentChat)) { state in
            state.chat = .presented(AIChatFeature.State(brainstorming: "Half-formed thoughts"))
        }

        #expect(store.state.chat.isPresented)
        #expect(store.state.chat.wrapped?.turns.isEmpty == true)
    }

    /// Two dismiss steps, one per dismissal edge. The middle stage is what keeps the panel
    /// rendering its last contents while SwiftUI animates it away, instead of blanking.
    @Test("dismissing walks presented → dismissing → dismissed, one step per edge")
    func dismissingWalksTheThreeStages() async throws {
        let session = AIChatFeature.State()
        var initial = AppState()
        initial.chat = .presented(session)
        let store = makeStore(initial: initial)

        store.dispatch(.navigation(.dismissChat)) { $0.chat = .dismissing(last: session) }
        #expect(store.state.chat.isPresented == false)
        #expect(store.state.chat.wrapped != nil)

        store.dispatch(.navigation(.dismissChat)) { $0.chat = .dismissed }
        #expect(store.state.chat.wrapped == nil)
    }

    @Test("dismissing is idempotent once dismissed")
    func dismissingIsIdempotent() async throws {
        let store = makeStore()
        store.dispatch(.navigation(.dismissGitHubSync)) { _ in }
        #expect(store.state.gitHubSync.wrapped == nil)
    }

    /// Nothing survives a dismissal, so a sheet re-opened after a half-finished form starts
    /// blank without anyone remembering to clear it.
    @Test("presenting GitHub Sync builds it fresh every time")
    func presentingGitHubSyncBuildsItFresh() async throws {
        var stale = GitHubSyncFeature.State()
        stale.path = [.link]
        stale.linkRepoInput = "left over"
        var initial = AppState()
        initial.gitHubSync = .dismissing(last: stale)
        let store = makeStore(initial: initial)

        store.dispatch(.navigation(.dismissGitHubSync)) { $0.gitHubSync = .dismissed }
        store.dispatch(.navigation(.presentGitHubSync)) { $0.gitHubSync = .presented(GitHubSyncFeature.State()) }

        #expect(store.state.gitHubSync.wrapped?.path.isEmpty == true)
        #expect(store.state.gitHubSync.wrapped?.linkRepoInput.isEmpty == true)
    }
}
