import AIChatFeature
import AppDomain
import ArticleEditorFeature
import Foundation
import GeneratorCore
import GitHubSyncFeature
import ReactiveConcurrency
import SwiftRex
import SwiftRexTesting
import Testing

@testable import AppCore

/// These run the **whole** `AppFeature.behavior()` fold, not `navigationBehavior()` in
/// isolation — so they cover the part no unit test of a single reducer can: that a child's
/// action actually reaches the app, that the app's answer actually reaches back through
/// the affine scope into the right stack element or presentation slot, and that the
/// cross-feature `.on` wiring is hooked up at all.
@Suite("AppFeature bridges")
@MainActor
struct AppFeatureBridgeTests {
    private func summary(_ slug: String, number: Int = 1) -> ArticleSummary {
        ArticleSummary(
            url: URL(fileURLWithPath: "/tmp/Articles/\(slug).json"),
            slug: slug,
            title: "Title for \(slug)",
            number: number
        )
    }

    // `World` alone is ambiguous here: `GeneratorCore` has one too.
    private func makeStore(
        initial: AppState = .init(),
        world: AppCore.World = .mock()
    ) -> TestStore<AppAction, AppState, AppCore.World> {
        TestStore(
            initial: initial,
            behavior: AppFeature.behavior(),
            environment: world,
            exhaustive: false
        )
    }

    /// Runs the store to quiescence the way a live `Store` does.
    ///
    /// `TestStore` deliberately *records* an effect's output rather than applying it, so each
    /// hop can be asserted individually. These tests are about whether the bridges are wired
    /// together at all, not about the shape of each intermediate action — so this feeds every
    /// received action back through the behavior and repeats until nothing new appears.
    /// The bridges chain (`select → push → close`, `confirmClose → dismiss → resume`), which
    /// is exactly why one drain isn't enough.
    private func settle(_ store: TestStore<AppAction, AppState, AppCore.World>) async {
        var applied = 0
        // The longest chain in the app is a switch away from an unsaved article:
        // select → push → save → saved → resumePending → start → opened.
        for _ in 0..<12 {
            await store.runEffects()
            let received = store.receivedActions
            guard received.count > applied else { return }
            for action in received[applied...] {
                store.dispatch(action, source: ActionSource(file: #fileID, function: #function, line: #line))
            }
            applied = received.count
        }
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

    private func liveChat() -> AIChatFeature.State {
        var chat = AIChatFeature.State()
        chat.turns = [ChatTurn(role: .user, text: "Hi")]
        return chat
    }

    // MARK: - Sidebar → editor

    /// The single line that replaced three bridges. Tapping a row is the *only* way into
    /// the editor, and it lands in one synchronous pass rather than a tick later.
    @Test("tapping a sidebar row pushes the editor and highlights that row")
    func selectingAnArticleOpensIt() async {
        let target = summary("pure-functions")
        let store = makeStore()

        store.dispatch(.articleList(.select(target))) { _ in }
        await settle(store)

        #expect(store.state.routes == [.articleEditor])
        #expect(store.state.openEditor?.opened == target)
        #expect(store.state.articleList.selectedSlug == target.slug)
    }

    @Test("tapping a second row replaces the editor instead of stacking another")
    func selectingASecondArticleReplacesTheEditor() async {
        let first = summary("pure-functions")
        let second = summary("side-effects", number: 2)
        let store = makeStore()

        store.dispatch(.articleList(.select(first))) { _ in }
        await settle(store)
        store.dispatch(.articleList(.select(second))) { _ in }
        await settle(store)

        #expect(store.state.path.count == 1)
        #expect(store.state.openEditor?.opened == second)
        #expect(store.state.articleList.selectedSlug == second.slug)
    }

    /// Replacing in place is what keeps SwiftUI from tearing the editor down — and that is
    /// exactly why the replacement screen cannot load itself from `onAppear`, which never
    /// fires a second time. Invisible on iPhone (you pop back before picking another
    /// article), permanent on iPad's two-pane layout: every article after the first opened
    /// on a spinner that nothing would ever clear.
    @Test("the replacing editor loads its own article, with no view lifecycle to lean on")
    func selectingASecondArticleLoadsIt() async {
        let first = summary("pure-functions")
        let second = summary("side-effects", number: 2)
        let store = makeStore(world: .mock(openDocument: loadingOpenDocument))

        store.dispatch(.articleList(.select(first))) { _ in }
        await settle(store)

        #expect(store.state.openEditor?.document?.title == "Loaded pure-functions.json")

        store.dispatch(.articleList(.select(second))) { _ in }
        await settle(store)

        #expect(store.state.openEditor?.document?.title == "Loaded side-effects.json")
    }

    // MARK: - Leaving an article with unsaved edits

    /// The autosave promise, through the real fold: no question, the edits reach the
    /// environment, and the switch completes on its own. Every hop is a separate bridge —
    /// the gate takes the save, the save's outcome resumes the ask, the resume commits
    /// and starts the next screen — so this is the only test that proves they connect.
    @Test("switching away from unsaved edits writes them, then goes through")
    func switchingAwayFromUnsavedEditsSavesFirst() async {
        let open = summary("pure-functions")
        let target = summary("side-effects", number: 2)
        let saved = SavedDocuments()
        var initial = AppState()
        initial.path = [.articleEditor(dirtyEditor(for: open))]
        initial.articleList.selectedSlug = open.slug
        let store = makeStore(initial: initial, world: .mock(
            openDocument: loadingOpenDocument,
            saveDocument: { document in
                saved.record(document)
                return .just("hash-after-save")
            }
        ))

        store.dispatch(.articleList(.select(target))) { _ in }
        await settle(store)

        // The edits left the app rather than quietly going away with the screen.
        #expect(saved.titles == ["Edited, and not saved"])
        #expect(store.state.discardPrompt == nil)
        #expect(store.state.pendingNavigation == nil)
        // And the switch the user actually asked for happened, fully loaded.
        #expect(store.state.openEditor?.opened == target)
        #expect(store.state.openEditor?.document?.title == "Loaded side-effects.json")
    }

    /// The other edge of that promise: a save taken on the user's behalf that fails must
    /// not lose the work it was standing in for. The switch stops where it is and becomes
    /// the one question worth asking.
    @Test("a save that fails holds the switch and asks instead of discarding")
    func aFailedAutosaveHoldsTheSwitch() async {
        let open = summary("pure-functions")
        let target = summary("side-effects", number: 2)
        var initial = AppState()
        initial.path = [.articleEditor(dirtyEditor(for: open))]
        initial.articleList.selectedSlug = open.slug
        let store = makeStore(initial: initial, world: .mock(
            openDocument: loadingOpenDocument,
            saveDocument: { _ in .fail(.fileWriteFailed(path: "/tmp/Articles/pure-functions.json", reason: "disk full")) }
        ))

        store.dispatch(.articleList(.select(target))) { _ in }
        await settle(store)

        #expect(store.state.openEditor?.opened == open)
        #expect(store.state.openEditor?.document?.hasUnsavedChanges == true)
        #expect(store.state.discardPrompt == .saveFailed("Couldn't write /tmp/Articles/pure-functions.json: disk full"))

        // Answering it is the user choosing to lose the work — which is theirs to choose.
        store.dispatch(.navigation(.resumePending)) { state in
            state.pendingNavigation = nil
            state.path = [.articleEditor(ArticleEditorFeature.State(opening: target))]
            state.articleList.selectedSlug = target.slug
        }
        await settle(store)

        #expect(store.state.openEditor?.opened == target)
        #expect(store.state.discardPrompt == nil)
    }

    private func dirtyEditor(for summary: ArticleSummary) -> ArticleEditorFeature.State {
        var editor = editor(for: summary)
        editor.document?.title = "Edited, and not saved"
        return editor
    }

    // MARK: - Keeping the article index honest

    /// The sidebar is a listing of a directory, taken once. Anything that rewrites a file
    /// afterwards leaves it describing a file as it no longer is — here, a renamed article
    /// kept its old title in the sidebar until the app was relaunched.
    @Test("a save re-reads the index, so a renamed article doesn't keep its old title")
    func aSaveRefreshesTheSidebar() async {
        let open = summary("pure-functions")
        let renamed = ArticleSummary(url: open.url, slug: open.slug, title: "Renamed On Disk", number: 1)
        let directory = ArticleIndex([open])
        var initial = AppState()
        initial.path = [.articleEditor(dirtyEditor(for: open))]
        initial.articleList.summaries = [open]
        initial.articleList.selectedSlug = open.slug
        let store = makeStore(initial: initial, world: .mock(
            listArticles: { .just(directory.summaries) },
            saveDocument: { _ in
                // Writing the file is what makes the old listing wrong.
                directory.set([renamed])
                return .just("hash-after-save")
            }
        ))

        store.dispatch(.articleEditor(.save), source: ActionSource(file: #fileID, function: #function, line: #line))
        await settle(store)

        #expect(store.state.articleList.summaries == [renamed])
    }

    /// A pull writes whole files, including articles no screen has open — before this,
    /// they didn't appear in the sidebar at all until the next launch.
    @Test("a GitHub pull re-reads the index, so newly pulled articles show up")
    func aPullRefreshesTheSidebar() async {
        let existing = summary("pure-functions")
        let pulled = summary("from-github", number: 7)
        let directory = ArticleIndex([existing, pulled])
        var initial = AppState()
        initial.articleList.summaries = [existing]
        let store = makeStore(initial: initial, world: .mock(listArticles: { .just(directory.summaries) }))

        store.dispatch(
            .gitHubSync(.pullApplied(.success(PullOutcome(applied: 1, keptLocal: [])))),
            source: ActionSource(file: #fileID, function: #function, line: #line)
        )
        await settle(store)

        #expect(store.state.articleList.summaries == [existing, pulled])
    }

    /// A save can move the very slug the highlight matches on. The editor re-describes its
    /// own summary, and the highlight is re-derived from it in the same pass, so the two
    /// cannot end up pointing at different rows.
    @Test("renaming an article's slug and saving keeps the sidebar highlight on it")
    func aRenamedSlugKeepsItsHighlight() async {
        let open = summary("pure-functions")
        let renamed = ArticleSummary(url: open.url, slug: "renamed", title: "Renamed", number: 1)
        let directory = ArticleIndex([open])
        // The listing and the file agree on the number; only the name is being changed.
        var editor = ArticleEditorFeature.State(opening: open)
        var document = OpenDocument(
            url: open.url,
            article: Article(title: open.title, slug: open.slug, emphasis: .text, number: open.number, blocks: [.paragraph("Body")])
        )
        document.slug = "renamed"
        document.title = "Renamed"
        editor.document = document
        var initial = AppState()
        initial.path = [.articleEditor(editor)]
        initial.articleList.summaries = [open]
        initial.articleList.selectedSlug = open.slug
        let store = makeStore(initial: initial, world: .mock(
            listArticles: { .just(directory.summaries) },
            saveDocument: { _ in
                directory.set([renamed])
                return .just("hash-after-save")
            }
        ))

        store.dispatch(.articleEditor(.save), source: ActionSource(file: #fileID, function: #function, line: #line))
        await settle(store)

        #expect(store.state.articleList.summaries == [renamed])
        #expect(store.state.articleList.selectedSlug == "renamed")
        #expect(store.state.openEditor?.opened == renamed)
    }

    /// A stand-in for the Articles directory, so a test can change what the *next* listing
    /// answers — which is the whole point of a refresh. Exercised serially from a single
    /// `@MainActor` test, so the lack of real synchronization is safe despite
    /// `@unchecked Sendable`.
    private final class ArticleIndex: @unchecked Sendable {
        private(set) var summaries: [ArticleSummary]
        init(_ summaries: [ArticleSummary]) { self.summaries = summaries }
        func set(_ summaries: [ArticleSummary]) { self.summaries = summaries }
    }

    /// An `openDocument` that actually returns something, named after the file asked for,
    /// so a test can tell *which* article ended up on screen.
    private let loadingOpenDocument: @Sendable (URL) -> Publisher<(article: Article, blockIDs: [UUID]), ArticleEditorError> = { url in
        .just((
            article: Article(
                title: "Loaded \(url.lastPathComponent)",
                slug: url.deletingPathExtension().lastPathComponent,
                emphasis: .text,
                blocks: [.paragraph("Body")]
            ),
            blockIDs: [UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!]
        ))
    }

    /// Records what reached `saveDocument`, so a test can assert the user's edits actually
    /// left the app rather than merely failing to raise a dialog. Exercised serially from
    /// a single `@MainActor` test, so the lack of real synchronization is safe despite
    /// `@unchecked Sendable`.
    private final class SavedDocuments: @unchecked Sendable {
        private(set) var titles: [String] = []
        func record(_ document: OpenDocument) { titles.append(document.title) }
    }

    // MARK: - The chat gate, end to end

    /// The whole parked-navigation round trip, through the real fold: the push is held,
    /// the chat raises its own gate, the user's answer dismisses the panel *and* releases
    /// the push — none of which any single feature can do alone.
    @Test("switching articles mid-conversation waits for the answer, then goes through")
    func switchingArticlesMidConversationWaitsForTheAnswer() async {
        let open = summary("pure-functions")
        let target = summary("side-effects", number: 2)
        var initial = AppState()
        initial.path = [.articleEditor(editor(for: open))]
        initial.articleList.selectedSlug = open.slug
        initial.chat = .presented(liveChat())
        let store = makeStore(initial: initial)

        store.dispatch(.articleList(.select(target))) { _ in }
        await settle(store)

        // Held: still on the old article, and the chat is asking.
        #expect(store.state.openEditor?.opened == open)
        #expect(store.state.pendingNavigation?.gate == .chatSession)
        #expect(store.state.chat.wrapped?.isConfirmingClose == true)

        store.dispatch(.chat(.confirmCloseAndDiscard)) { state in
            state.chat.wrapped?.isConfirmingClose = false
            state.chat.wrapped?.turns = []
        }
        await settle(store)

        // `isPresented`, not `wrapped == nil`: dismissal is a two-step walk and the second
        // step is SwiftUI's "the animation finished" signal, which no store-level test has.
        // Nothing is on screen the moment this goes false.
        #expect(store.state.chat.isPresented == false)
        #expect(store.state.pendingNavigation == nil)
        #expect(store.state.openEditor?.opened == target)
        #expect(store.state.articleList.selectedSlug == target.slug)
    }

    @Test("backing out of that question also backs out of the switch")
    func cancellingTheChatCloseCancelsTheSwitch() async {
        let open = summary("pure-functions")
        var initial = AppState()
        initial.path = [.articleEditor(editor(for: open))]
        initial.articleList.selectedSlug = open.slug
        initial.chat = .presented(liveChat())
        let store = makeStore(initial: initial)

        store.dispatch(.articleList(.select(summary("side-effects", number: 2)))) { _ in }
        await settle(store)
        store.dispatch(.chat(.cancelClose)) { $0.chat.wrapped?.isConfirmingClose = false }
        await settle(store)

        #expect(store.state.pendingNavigation == nil)
        #expect(store.state.openEditor?.opened == open)
        #expect(store.state.chat.isPresented)
        #expect(store.state.chat.wrapped?.turns.isEmpty == false)
    }

    // MARK: - The chat panel

    @Test("the editor's Ask Assistant button presents the panel, seeded from that article")
    func openChatPresentsThePanelSeededFromTheArticle() async {
        let open = summary("pure-functions")
        var initial = AppState()
        initial.path = [.articleEditor(editor(for: open, brainstorming: "Half-formed thoughts"))]
        let store = makeStore(initial: initial)

        store.dispatch(.articleEditor(.openChat)) { _ in }
        await settle(store)

        #expect(store.state.chat.isPresented)
        #expect(store.state.chat.wrapped?.brainstorming == "Half-formed thoughts")
    }

    /// A panel cannot dismiss itself, so "close with nothing to lose" is only a dismissal
    /// because the app bridges it. Worth pinning: the `when:` guard is the whole mechanism.
    @Test("closing an empty conversation dismisses the panel with no question asked")
    func closingAnEmptyConversationJustDismisses() async {
        var initial = AppState()
        initial.chat = .presented(AIChatFeature.State())
        let store = makeStore(initial: initial)

        store.dispatch(.chat(.close)) { _ in }
        await settle(store)

        #expect(store.state.chat.isPresented == false)
    }

    @Test("closing a live conversation asks instead of dismissing")
    func closingALiveConversationAsksFirst() async {
        var initial = AppState()
        initial.chat = .presented(liveChat())
        let store = makeStore(initial: initial)

        store.dispatch(.chat(.close)) { $0.chat.wrapped?.isConfirmingClose = true }
        await settle(store)

        #expect(store.state.chat.isPresented)
        #expect(store.state.chat.wrapped?.isConfirmingClose == true)
    }

    /// Crosses two affine scopes in one hop: out of the chat's presentation slot, into the
    /// editor's stack element.
    @Test("saving the conversation writes it into the open article's Brainstorming")
    func savingTheConversationWritesIntoTheArticle() async {
        let open = summary("pure-functions")
        var initial = AppState()
        initial.path = [.articleEditor(editor(for: open))]
        initial.chat = .presented(liveChat())
        let store = makeStore(initial: initial)

        store.dispatch(.chat(.notesCompacted("You: Hi"))) { _ in }
        await settle(store)

        #expect(store.state.openEditor?.document?.brainstorming == "You: Hi")
        // …and straight back out again, so the panel's own copy stays current.
        #expect(store.state.chat.wrapped?.brainstorming == "You: Hi")
    }

    // MARK: - GitHub Sync

    @Test("the sheet's Done button dismisses it")
    func requestCloseDismissesTheSheet() async {
        var initial = AppState()
        initial.gitHubSync = .presented(GitHubSyncFeature.State())
        let store = makeStore(initial: initial)

        store.dispatch(.gitHubSync(.requestClose)) { _ in }
        await settle(store)

        #expect(store.state.gitHubSync.isPresented == false)
    }

    @Test("a freshly linked repo's first sync closes the sheet on its own")
    func firstSyncClosesTheSheet() async {
        var initial = AppState()
        initial.gitHubSync = .presented(GitHubSyncFeature.State())
        let store = makeStore(initial: initial)

        store.dispatch(.gitHubSync(.firstSyncCompleted)) { _ in }
        await settle(store)

        #expect(store.state.gitHubSync.isPresented == false)
    }
}
