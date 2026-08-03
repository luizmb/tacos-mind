import AIChatFeature
import AppDomain
import ArticleEditorFeature
import ArticleListFeature
import GitHubSyncFeature
import SwiftRex
import SwiftRexArchitecture
import SwiftUI

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
/// Note that every method takes what it needs as a **parameter** rather than reading it
/// off the store. The router holds the raw store, which SwiftUI does not observe; a read
/// in here would register no dependency and the screen would go stale. The root view does
/// all the reading, off its own `ViewStore`.
@MainActor
public struct AppRouter {
    private let store: MainStoreType
    private let world: World

    init(store: MainStoreType, world: World) {
        self.store = store
        self.world = world
    }

    /// The sidebar — always on screen, so a total lift rather than an affine one.
    public func sidebar() -> some View {
        AppScopes.articleList.view(of: ArticleListFeature.self, from: store, world: world)
    }

    /// The screen for `route`. `@ViewBuilder` keeps the concrete per-route types without
    /// reaching for `AnyView`.
    @ViewBuilder
    public func destination(for route: AppRoute) -> some View {
        switch route {
        case .articleEditor:
            AppScopes.articleEditor.screen(of: ArticleEditorFeature.self, from: store, world: world)
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
            ContentUnavailableView(
                "No Article Open",
                systemImage: "doc.text",
                description: Text("Choose an article from the sidebar.")
            )
        }
    }

    @ViewBuilder
    public func chat() -> some View {
        AppScopes.chat.screen(of: AIChatFeature.self, from: store, world: world)
    }

    @ViewBuilder
    public func gitHubSync() -> some View {
        AppScopes.gitHubSync.screen(of: GitHubSyncFeature.self, from: store, world: world)
    }
}

// MARK: - Building a view from an affine scope

/// The affine counterpart of `Relay.Scope.view(of:from:world:)`, which needs a *total*
/// state lane and so cannot build a screen that lives in a stack element or a
/// presentation slot.
///
/// That the library's total builder does not compile for these scopes is the useful part:
/// it is a type error, not a convention, that a screen which may not exist has to be
/// built through something that can say so.
///
/// `transpose()` holds the last value steady while SwiftUI animates the screen away, so
/// it never blanks on its way out; the outer `nil` then tears it down once the state is
/// actually gone.
extension Relay.Scope where
    ActionStrategy: Relay.ActionAxis.EmbedsProtocol,
    StateStrategy: Relay.StateAxis.WritesProtocol,
    EnvironmentStrategy: Relay.EnvironmentAxis.NarrowsProtocol,
    ActionStrategy.Global == Action,
    StateStrategy.Global == State,
    EnvironmentStrategy.Global == Environment {
    @MainActor @ViewBuilder
    func screen<F: ViewFactory>(
        of _: F.Type,
        from store: any StoreType<Action, State>,
        world: Environment
    ) -> some View
    where F.Action == ActionStrategy.Local, F.State == StateStrategy.Local, F.Environment == EnvironmentStrategy.Local {
        if let focused = store.projection(action: action.review, state: state.preview).transpose() {
            F.view(store: focused, environment: environment.narrow(world))
        }
    }
}
