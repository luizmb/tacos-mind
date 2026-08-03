import AppDomain
import Foundation
import GeneratorCore
import ReactiveConcurrency
import SwiftRex
import SwiftRexTesting
import Testing

@testable import ArticleEditorFeature

@Suite("ArticleEditorFeature")
@MainActor
struct ArticleEditorFeatureTests {
    private func article(slug: String) -> Article {
        Article(title: "Title for \(slug)", slug: slug, emphasis: .text, blocks: [.paragraph("Body")])
    }

    private func summary(slug: String, number: Int = 1) -> ArticleSummary {
        ArticleSummary(
            url: URL(fileURLWithPath: "/tmp/Articles/\(slug).json"),
            slug: slug,
            title: "Title for \(slug)",
            number: number
        )
    }

    /// Test-only spy for `openInBrowser` calls — exercised serially within a single
    /// `@MainActor` test function, so the lack of real synchronization is safe despite
    /// `@unchecked Sendable`.
    private final class URLRecorder: @unchecked Sendable {
        private(set) var urls: [URL] = []
        func record(_ url: URL) { urls.append(url) }
    }

    private func makeStore(
        opening: ArticleSummary? = nil,
        openDocument: @escaping @Sendable (URL) -> Publisher<(article: Article, blockIDs: [UUID]), ArticleEditorError> = { url in
            .fail(.fileReadFailed(path: url.path, reason: "unused"))
        },
        generateArticle: @escaping @Sendable (String) -> Publisher<URL, ArticleEditorError> = { slug in
            .just(URL(fileURLWithPath: "/tmp/dist/articles/\(slug).html"))
        },
        generateAllArticles: @escaping @Sendable () -> Publisher<Void, ArticleEditorError> = { .just(()) },
        openInBrowser: @escaping @MainActor @Sendable (URL) -> Void = { _ in }
    ) -> TestStore<ArticleEditorFeature.Action, ArticleEditorFeature.State, ArticleEditorFeature.Environment> {
        TestStore(
            initial: ArticleEditorFeature.State(opening: opening ?? summary(slug: "pure-functions")),
            behavior: ArticleEditorFeature.behavior(),
            environment: ArticleEditorFeature.Environment(
                openDocument: openDocument,
                saveDocument: { _ in .just("hash") },
                watchFile: { _ in .empty() },
                checkDiskHash: { _ in .just("hash") },
                parseDiskArticle: { _ in .fail(.fileReadFailed(path: "", reason: "unused")) },
                listArticles: { .just([]) },
                generateArticle: generateArticle,
                generateAllArticles: generateAllArticles,
                openInBrowser: openInBrowser
            )
        )
    }

    /// Drains one full `.start` round-trip: `.start` fires both `openDocument` and
    /// `listArticles` concurrently, so `.opened`/`.allSummariesLoaded` can arrive in
    /// either order — this drains whichever is actually next, rather than assuming one.
    private func receiveOpened(
        on store: TestStore<ArticleEditorFeature.Action, ArticleEditorFeature.State, ArticleEditorFeature.Environment>,
        expectedURL: URL
    ) async throws {
        for _ in 0..<2 {
            guard let next = store.receivedActions.first else { break }
            if case .opened = next {
                store.receive(ArticleEditorFeature.Action.prism.opened) { payload, state in
                    let (openedURL, result) = payload
                    #expect(openedURL == expectedURL)
                    guard case .success(let opened) = result else {
                        Issue.record("expected a successful open")
                        return
                    }
                    state.document = OpenDocument(url: openedURL, article: opened.article)
                    state.document?.blocks = zip(opened.blockIDs, opened.article.blocks).map { EditableBlock(id: $0, block: $1) }
                }
                await store.runEffects()
            } else {
                store.receive(ArticleEditorFeature.Action.prism.allSummariesLoaded) { _, _ in }
            }
        }
    }

    /// Regression test for a real, user-reported bug: the URL a document was loaded from
    /// used to be guessed rather than carried, and the guess resolved to the filesystem
    /// root, making every save fail with "the volume is read only." The screen is now
    /// constructed for exactly one article, so `document.url` is that article's URL by
    /// construction — this pins it.
    @Test(".start loads the article the screen was constructed for")
    func startLoadsTheArticleTheScreenWasBuiltFor() async throws {
        let target = summary(slug: "pure-functions")
        let article = article(slug: "pure-functions")
        let store = makeStore(opening: target, openDocument: { _ in .just((article: article, blockIDs: [UUID()])) })

        store.dispatch(.start) { _ in }
        await store.runEffects()
        try await receiveOpened(on: store, expectedURL: target.url)

        #expect(store.state.document?.url == target.url)
    }

    /// Switching articles replaces the stack element, but does not cancel the load the
    /// previous screen already started — so that load still arrives, addressed to the
    /// screen that replaced it. Without the URL guard it would quietly overwrite the new
    /// article with the old one's contents.
    @Test("a load that lands for a different article than this screen's is ignored")
    func aStaleLoadForAnotherArticleIsIgnored() async throws {
        let target = summary(slug: "side-effects", number: 2)
        let store = makeStore(opening: target)
        let stale = article(slug: "pure-functions")

        store.dispatch(
            .opened(URL(fileURLWithPath: "/tmp/Articles/pure-functions.json"), .success((article: stale, blockIDs: [UUID()])))
        ) { _ in }
        await store.runEffects()

        #expect(store.state.document == nil)
    }

    @Test(".build regenerates the whole site and reports success")
    func buildRegeneratesTheWholeSite() async throws {
        let store = makeStore(generateAllArticles: { .just(()) })

        store.dispatch(.build) { $0.isBuilding = true; $0.buildStatus = nil }
        await store.runEffects()
        store.receive(ArticleEditorFeature.Action.prism.built) { result, state in
            guard case .success = result else {
                Issue.record("expected a successful build")
                return
            }
            state.isBuilding = false
            state.buildStatus = "Build succeeded"
        }
    }

    @Test(".run is a no-op when no document is open")
    func runIsANoOpWithoutADocument() async throws {
        let store = makeStore()

        store.dispatch(.run) { _ in }
        await store.runEffects()

        #expect(store.receivedActions.isEmpty)
    }

    @Test(".run generates the current article and opens its preview URL in the browser")
    func runGeneratesCurrentArticleAndOpensBrowser() async throws {
        let recorder = URLRecorder()
        let target = summary(slug: "pure-functions")
        let previewURL = URL(fileURLWithPath: "/tmp/dist/articles/pure-functions.html")
        let currentArticle = article(slug: "pure-functions")
        let store = makeStore(
            opening: target,
            openDocument: { _ in .just((article: currentArticle, blockIDs: [UUID()])) },
            generateArticle: { slug in
                #expect(slug == "pure-functions")
                return .just(previewURL)
            },
            openInBrowser: { recorder.record($0) }
        )

        store.dispatch(.start) { _ in }
        await store.runEffects()
        try await receiveOpened(on: store, expectedURL: target.url)

        store.dispatch(.run) { _ in }
        await store.runEffects()
        store.receive(ArticleEditorFeature.Action.prism.ran) { result, _ in
            guard case .success(let receivedURL) = result else {
                Issue.record("expected a successful run")
                return
            }
            #expect(receivedURL == previewURL)
        }
        await store.runEffects()

        #expect(recorder.urls == [previewURL])
    }

    @Test(".openChat is a pure trigger — no local state change, no effect")
    func openChatIsAPureTrigger() async throws {
        let store = makeStore()

        store.dispatch(.openChat) { _ in }
        await store.runEffects()

        #expect(store.receivedActions.isEmpty)
    }
}
