import AIChatFeature
import AppDomain
import ArticleEditorFeature
import ArticleListFeature
import GitHubSyncFeature
import SwiftRex
import SwiftRexArchitecture
import SwiftUI
import Vitral
import VitralTokens

/// Turns a route into a screen — **the boundary the `World` stops at**.
///
/// ``AppFeature`` constructs one (it is the only thing holding the `World`) and hands it
/// to the root view. The view can therefore render a destination without ever naming
/// `World`, naming a feature type, or knowing how a child is built: it knows `AppRoute`
/// and gets back an opaque `View`.
///
/// Every screen is built from the **same** ``AppScopes`` declaration that drives the
/// behavior fold, so a screen's action prism, its slice of state, and its environment
/// narrowing are stated once and cannot drift apart between the two uses.
///
/// Nothing is cached. Each method runs per visible screen, projecting the child's store
/// and narrowing `World` on the spot — a screen that isn't on screen has no store, no
/// view and no environment.
///
/// It holds the root's `ViewStore`, so a screen that lives in an optional slot is built from
/// the slot's presence as the root reads it, and each child keeps a view store of its own.
@MainActor
public struct AppRouter {
    private let viewStore: ViewStore<AppAction, AppState>
    private let world: World

    init(viewStore: ViewStore<AppAction, AppState>, world: World) {
        self.viewStore = viewStore
        self.world = world
    }

    /// The sidebar — always on screen, so a total lift rather than an affine one.
    public func sidebar() -> some View {
        AppScopes.articleList.view(of: ArticleListFeature.self, from: viewStore, world: world)
    }

    /// The screen for `route`. `@ViewBuilder` keeps the concrete per-route types without
    /// reaching for `AnyView`.
    @ViewBuilder
    public func destination(for route: AppRoute) -> some View {
        switch route {
        case .articleEditor:
            if let editor = AppScopes.articleEditor.view(of: ArticleEditorFeature.self, from: viewStore, world: world) { editor }
        }
    }

    /// The two-pane layout's detail column: whatever is on top of the stack, or the
    /// empty state. This is the app's only "nothing is open" screen — the editor itself
    /// no longer has one, because it is only ever built for an article.
    @ViewBuilder
    public func detail(for route: AppRoute?) -> some View {
        if let route {
            destination(for: route)
        } else {
            EmptyState(
                "No Article Open",
                message: Text("Choose an article from the sidebar."),
                icon: Image(systemName: "doc.text")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { Backdrop(.grid()) }
        }
    }

    @ViewBuilder
    public func chat() -> some View {
        if let chat = AppScopes.chat.view(of: AIChatFeature.self, from: viewStore, world: world) { chat }
    }

    @ViewBuilder
    public func gitHubSync() -> some View {
        if let sync = AppScopes.gitHubSync.view(of: GitHubSyncFeature.self, from: viewStore, world: world) { sync }
    }
}
