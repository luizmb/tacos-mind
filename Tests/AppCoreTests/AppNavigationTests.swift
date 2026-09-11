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

    /// Every commit is followed by the screen's `.start` — navigation's own doing, because
    /// a push onto an already-open editor reuses the view in place and `onAppear` never
    /// fires again. Draining it here is what makes each push test assert it happened.
    private func expectStart(_ store: TestStore<AppAction, AppState, AppCore.World>) async {
        await store.runEffects()
        store.receive(AppAction.prism.articleEditor) { action, _ in
            #expect(ArticleEditorFeature.Action.prism.start.preview(action) != nil)
        }
    }

    /// The saving gate acts rather than asks, so every test that trips it has a save to
    /// drain — and asserting it here is what keeps "nothing was asked" from quietly
    /// meaning "nothing happened at all".
    private func expectSave(_ store: TestStore<AppAction, AppState, AppCore.World>) async {
        await store.runEffects()
        store.receive(AppAction.prism.articleEditor) { action, _ in
            #expect(ArticleEditorFeature.Action.prism.save.preview(action) != nil)
        }
    }

    private func dirtyEditor(for summary: ArticleSummary) -> ArticleEditorFeature.State {
        var editor = editor(for: summary)
        editor.document?.title = "Edited, and not saved"
        #expect(editor.document?.hasUnsavedChanges == true)
        return editor
    }

    /// Dirty *and* changed underneath — the one document the app must not write on the
    /// user's behalf, because either version it picks overrules the other.
    private func conflictedEditor(for summary: ArticleSummary) -> ArticleEditorFeature.State {
        var editor = dirtyEditor(for: summary)
        editor.document?.externalChange = .conflict(
            diskArticle: Article(title: "Changed by someone else", slug: summary.slug, emphasis: .text, blocks: [.paragraph("Theirs")])
        )
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
        // Nothing is loaded *yet* — the screen is built empty and told to load itself,
        // which is the `.start` drained below.
        #expect(store.state.openEditor?.document == nil)
        await expectStart(store)
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
        // And precisely because `routes` is unchanged, SwiftUI keeps the very same view
        // alive — so the replacement screen would never load a thing if navigation did
        // not start it. This is the iPad two-pane blank editor, caught at store level.
        await expectStart(store)
    }

    @Test("push re-derives the sidebar highlight, and popping clears it")
    func pushAndPopKeepTheSidebarHonest() async throws {
        let target = summary("pure-functions")
        let store = makeStore()

        store.dispatch(.navigation(.push(.articleEditor(target)))) { state in
            state.path = [.articleEditor(ArticleEditorFeature.State(opening: target))]
            state.articleList.selectedSlug = target.slug
        }
        await expectStart(store)

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

    /// The whole point of the unsaved-document gate: it does not ask. Leaving an article
    /// with edits in it writes them, the same promise `appDidEnterBackground` and the
    /// macOS quit flow already make on every other way out.
    @Test("unsaved edits are saved on the way out, with nothing asked")
    func unsavedEditsAreSavedNotQueried() async throws {
        let open = summary("pure-functions")
        let target = summary("side-effects", number: 2)
        var initial = AppState()
        initial.path = [.articleEditor(dirtyEditor(for: open))]
        initial.articleList.selectedSlug = open.slug
        let store = makeStore(initial: initial)

        store.dispatch(.navigation(.push(.articleEditor(target)))) { state in
            state.pendingNavigation = PendingNavigation(request: .articleEditor(target), gate: .unsavedDocument)
        }

        // Held on the old article until the save lands, and no question anywhere.
        #expect(store.state.openEditor?.opened == open)
        #expect(store.state.discardPrompt == nil)
        await expectSave(store)
    }

    /// Re-opening the article already on screen used to be exempt from the gate, on the
    /// grounds that it discards nothing — except ``AppState/commit(_:)`` rebuilds the
    /// entry either way, so the edits went with it, silently. Saving first is what makes
    /// the exemption unnecessary rather than merely wrong.
    @Test("re-opening the article already on screen saves its edits instead of dropping them")
    func reopeningTheSameArticleSavesFirst() async throws {
        let open = summary("pure-functions")
        var initial = AppState()
        initial.path = [.articleEditor(dirtyEditor(for: open))]
        initial.articleList.selectedSlug = open.slug
        let store = makeStore(initial: initial)

        store.dispatch(.navigation(.push(.articleEditor(open)))) { state in
            state.pendingNavigation = PendingNavigation(request: .articleEditor(open), gate: .unsavedDocument)
        }

        // Nothing is rebuilt yet, so the edits are still there to be written.
        #expect(store.state.openEditor?.document?.hasUnsavedChanges == true)
        await expectSave(store)
    }

    /// A document the app cannot write without overruling the copy on disk is the one
    /// case where the user really does have to choose — so this gate asks, and, sitting
    /// *after* the saving gate in the walk, is reached without a save being attempted.
    @Test("a conflicted article is never written on the user's behalf — it asks instead")
    func conflictedEditsAskRatherThanSave() async throws {
        let open = summary("pure-functions")
        let target = summary("side-effects", number: 2)
        var initial = AppState()
        initial.path = [.articleEditor(conflictedEditor(for: open))]
        initial.articleList.selectedSlug = open.slug
        let store = makeStore(initial: initial)

        store.dispatch(.navigation(.push(.articleEditor(target)))) { state in
            state.pendingNavigation = PendingNavigation(request: .articleEditor(target), gate: .unsavableDocument)
        }

        #expect(store.state.openEditor?.opened == open)
        #expect(store.state.discardPrompt == .fileChangedOnDisk)
    }

    /// The save came back with a failure, so the switch cannot go through quietly any
    /// more. Carrying that on the *pending ask* rather than reading `saveError` back out
    /// of the editor is what stops a stale failure from making every later switch ask
    /// instead of simply trying again.
    @Test("a failed save turns the quiet switch into the one question worth asking")
    func aFailedSaveRaisesTheDiscardPrompt() async throws {
        let open = summary("pure-functions")
        let target = summary("side-effects", number: 2)
        var editor = dirtyEditor(for: open)
        editor.saveError = "Couldn't write /tmp/Articles/pure-functions.json: disk full"
        var initial = AppState()
        initial.path = [.articleEditor(editor)]
        initial.articleList.selectedSlug = open.slug
        initial.pendingNavigation = PendingNavigation(request: .articleEditor(target), gate: .unsavedDocument)
        let store = makeStore(initial: initial)

        store.dispatch(.navigation(.pendingSaveFailed)) { state in
            state.pendingNavigation = PendingNavigation(request: .articleEditor(target), gate: .unsavableDocument)
        }

        #expect(store.state.openEditor?.opened == open)
        #expect(store.state.discardPrompt == .saveFailed(editor.saveError ?? ""))
    }

    /// Gates are ordered and each resolution resumes at the *next* one. This is the case
    /// that made the multi-gate resume worth writing down: answering the chat must hand
    /// over to the edits rather than pushing straight past them.
    @Test("answering the chat gate hands over to saving the edits, not to the push")
    func resumingFromTheChatGateFallsIntoTheSavingGate() async throws {
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
        await expectSave(store)
    }

    /// A landed save is the saving gate's "satisfied" signal, delivered through the very
    /// same `resumePending` a user's answer would use — the document is clean by then, so
    /// the walk finds nothing left to settle and the ask goes through.
    @Test("a save that lands lets the parked ask straight through")
    func aLandedSaveResumesTheAsk() async throws {
        let open = summary("pure-functions")
        let target = summary("side-effects", number: 2)
        var initial = AppState()
        // Clean, because by the time the resume arrives the save has re-baselined it.
        initial.path = [.articleEditor(editor(for: open))]
        initial.articleList.selectedSlug = open.slug
        initial.pendingNavigation = PendingNavigation(request: .articleEditor(target), gate: .unsavedDocument)
        let store = makeStore(initial: initial)

        store.dispatch(.navigation(.resumePending)) { state in
            state.pendingNavigation = nil
            state.path = [.articleEditor(ArticleEditorFeature.State(opening: target))]
            state.articleList.selectedSlug = target.slug
        }
        await expectStart(store)
    }

    /// The mirror image, and the reason a gate resumes at its *successor* rather than
    /// being re-evaluated from the start: the same dirty document is still there, so a
    /// naive re-check would park on it again, forever — and, worse, would now try to save
    /// the very edits the user just said to abandon.
    @Test("answering the discard prompt pushes, without re-asking or re-saving")
    func resumingFromTheDiscardPromptActuallyPushes() async throws {
        let open = summary("pure-functions")
        let target = summary("side-effects", number: 2)
        var initial = AppState()
        initial.path = [.articleEditor(conflictedEditor(for: open))]
        initial.articleList.selectedSlug = open.slug
        initial.pendingNavigation = PendingNavigation(request: .articleEditor(target), gate: .unsavableDocument)
        let store = makeStore(initial: initial)

        store.dispatch(.navigation(.resumePending)) { state in
            state.pendingNavigation = nil
            state.path = [.articleEditor(ArticleEditorFeature.State(opening: target))]
            state.articleList.selectedSlug = target.slug
        }
        await expectStart(store)
    }

    @Test("cancelling drops the parked ask and leaves the user where they were")
    func cancelPendingDropsTheAsk() async throws {
        let open = summary("pure-functions")
        var initial = AppState()
        initial.path = [.articleEditor(conflictedEditor(for: open))]
        initial.articleList.selectedSlug = open.slug
        initial.pendingNavigation = PendingNavigation(
            request: .articleEditor(summary("side-effects", number: 2)),
            gate: .unsavableDocument
        )
        let store = makeStore(initial: initial)

        store.dispatch(.navigation(.cancelPending)) { $0.pendingNavigation = nil }

        #expect(store.state.discardPrompt == nil)
        #expect(store.state.openEditor?.opened == open)
        #expect(store.state.openEditor?.document?.hasUnsavedChanges == true)
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
