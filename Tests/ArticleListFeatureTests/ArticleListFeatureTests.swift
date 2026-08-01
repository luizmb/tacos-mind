import AppDomain
import Foundation
import ReactiveConcurrency
import SwiftRex
import SwiftRexTesting
import Testing

@testable import ArticleListFeature

@Suite("ArticleListFeature")
@MainActor
struct ArticleListFeatureTests {
    private func makeStore(
        createArticle: @escaping @Sendable (String) -> Publisher<ArticleSummary, ArticleEditorError> = { name in
            .just(ArticleSummary(url: URL(fileURLWithPath: "/tmp/Articles/\(name).json"), slug: name, title: name, number: 1))
        }
    ) -> TestStore<ArticleListFeature.Action, ArticleListFeature.State, ArticleListFeature.Environment> {
        TestStore(
            initial: ArticleListFeature.State(),
            behavior: ArticleListFeature.behavior(),
            environment: ArticleListFeature.Environment(listArticles: { .just([]) }, createArticle: createArticle)
        )
    }

    @Test("confirming with a blank name shows an error and fires no effect")
    func confirmWithBlankNameShowsError() async throws {
        let store = makeStore()

        store.dispatch(.setNewArticleName("   ")) { $0.newArticleName = "   " }
        store.dispatch(.confirmNewArticle) { $0.createError = "Enter a name first." }
        await store.runEffects()

        #expect(store.receivedActions.isEmpty)
    }

    @Test("a successful creation appends the summary and closes the prompt")
    func successfulCreationAppendsSummary() async throws {
        let summary = ArticleSummary(url: URL(fileURLWithPath: "/tmp/Articles/my-new-article.json"), slug: "my-new-article", title: "my-new-article", number: 1)
        let store = makeStore(createArticle: { _ in .just(summary) })

        store.dispatch(.requestNewArticle) { state in
            state.isCreatingArticle = true
            state.newArticleName = ""
            state.createError = nil
        }
        store.dispatch(.setNewArticleName("my-new-article")) { $0.newArticleName = "my-new-article" }
        store.dispatch(.confirmNewArticle) { _ in }
        await store.runEffects()
        store.receive(ArticleListFeature.Action.prism.created) { result, state in
            guard case .success(let created) = result else {
                Issue.record("expected a successful creation")
                return
            }
            state.isCreatingArticle = false
            state.summaries.append(created)
            state.selectedSlug = created.slug
        }

        #expect(store.state.summaries == [summary])
        #expect(store.state.selectedSlug == summary.slug)
    }

    @Test("selecting an article sets selectedSlug immediately, not deferred until the editor confirms")
    func selectSetsSelectedSlugImmediately() async throws {
        let summary = ArticleSummary(url: URL(fileURLWithPath: "/tmp/Articles/pure-functions.json"), slug: "pure-functions", title: "Pure Functions", number: 1)
        let store = makeStore()

        store.dispatch(.select(summary)) { $0.selectedSlug = summary.slug }

        #expect(store.state.selectedSlug == summary.slug)
    }

    @Test("a failed creation (e.g. a duplicate name) surfaces the error and keeps the prompt open")
    func failedCreationSurfacesError() async throws {
        let store = makeStore(createArticle: { name in
            .fail(.fileWriteFailed(path: "/tmp/Articles/\(name).json", reason: "An article named \"\(name)\" already exists"))
        })

        store.dispatch(.setNewArticleName("existing-article")) { $0.newArticleName = "existing-article" }
        store.dispatch(.confirmNewArticle) { _ in }
        await store.runEffects()
        store.receive(ArticleListFeature.Action.prism.created) { result, state in
            guard case .failure = result else {
                Issue.record("expected a failed creation")
                return
            }
            state.createError = "Couldn't write /tmp/Articles/existing-article.json: An article named \"existing-article\" already exists"
        }
    }
}
