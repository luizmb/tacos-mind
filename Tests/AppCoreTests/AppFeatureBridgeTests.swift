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
    private func makeStore(initial: AppState = .init()) -> TestStore<AppAction, AppState, AppCore.World> {
        TestStore(
            initial: initial,
            behavior: AppFeature.behavior(),
            environment: AppCore.World.mock(),
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
        for _ in 0..<8 {
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
