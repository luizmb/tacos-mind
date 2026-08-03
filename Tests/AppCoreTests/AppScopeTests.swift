import AIChatFeature
import AppDomain
import ArticleEditorFeature
import Foundation
import GeneratorCore
import Observation
import SwiftRex
import SwiftRexSwiftUI
import Testing

@testable import AppCore

@Suite("App scopes and root observability")
@MainActor
struct AppScopeTests {
    private func summary(_ slug: String, number: Int = 1) -> ArticleSummary {
        ArticleSummary(
            url: URL(fileURLWithPath: "/tmp/Articles/\(slug).json"),
            slug: slug,
            title: "Title for \(slug)",
            number: number
        )
    }

    // MARK: - The affine focus a pushed screen lives behind

    /// Read and write go through the same prism, so a child behavior's mutation lands
    /// back in the element it was read from. Nothing derives a copy, so nothing can drift.
    @Test("writing through the editor scope lands back in the stack element it read")
    func theAffineScopeWritesBackIntoTheElementItRead() {
        var state = AppState()
        state.path = [.articleEditor(ArticleEditorFeature.State(opening: summary("pure-functions")))]

        AppScopes.articleEditor.state.modify(&state) { $0.buildStatus = "Build succeeded" }

        #expect(state.path.count == 1)
        #expect(AppScopes.articleEditor.state.preview(state)?.buildStatus == "Build succeeded")
    }

    /// The write half cannot append, only overwrite — so an effect landing after its
    /// screen was popped cannot conjure that screen back onto the stack.
    @Test("writing a screen that isn't on the stack changes nothing")
    func writingAScreenThatIsNotOnTheStackChangesNothing() {
        var state = AppState()

        AppScopes.articleEditor.state.modify(&state) { $0.buildStatus = "Build succeeded" }

        #expect(state == AppState())
    }

    /// Same guarantee for a presentation slot: `Presentation.wrapped`'s setter ignores a
    /// write while `dismissed`, so a late effect can update a panel that is animating out
    /// but can never bring a dismissed one back.
    @Test("writing the chat scope while dismissed cannot resurrect the panel")
    func writingADismissedPresentationChangesNothing() {
        var state = AppState()

        AppScopes.chat.state.modify(&state) { $0.draftText = "hello?" }

        #expect(state.chat.wrapped == nil)
    }

    @Test("writing the chat scope mid-dismissal updates the content but keeps it dismissing")
    func writingADismissingPresentationPreservesTheStage() {
        var state = AppState()
        state.chat = .dismissing(last: AIChatFeature.State())

        AppScopes.chat.state.modify(&state) { $0.draftText = "still here" }

        #expect(state.chat.isPresented == false)
        #expect(state.chat.wrapped?.draftText == "still here")
    }

    // MARK: - The root is observable

    /// The regression guard for the bug this whole rewrite exists to make unrepresentable.
    ///
    /// `binding`/`presence` are declared on `StoreType`, which the concrete `Store`
    /// conforms to — so a root view that reads its path off a bare `Store` compiles,
    /// dispatches correctly, reduces correctly, and never re-renders. Nothing pushed,
    /// ever, and no test caught it because the state was always right.
    ///
    /// `AppFeature.view` builds a `ViewStore`, which is `@Observable`. This asserts the
    /// property that actually matters: reading `routes` registers a dependency that a
    /// push fires.
    @Test("the root path is observable, so a push actually re-renders the stack")
    func theRootPathIsObservableSoAPushRerendersTheStack() async {
        let store = MainStore.app(world: AppCore.World.mock())
        let viewStore = ViewStore(store)

        let observed = Observed()
        withObservationTracking {
            _ = viewStore.state.routes
        } onChange: {
            observed.fire()
        }

        #expect(observed.didFire == false)

        store.dispatch(.navigation(.push(.articleEditor(summary("pure-functions")))))

        #expect(observed.didFire)
        #expect(viewStore.state.routes == [.articleEditor])
    }

    /// Exercised serially from a single `@MainActor` test, so the lack of real
    /// synchronization is safe despite `@unchecked Sendable`.
    private final class Observed: @unchecked Sendable {
        private(set) var didFire = false
        func fire() { didFire = true }
    }
}
