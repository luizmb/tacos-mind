import AppDomain
import SwiftRex
import SwiftRexArchitecture
import SwiftRexSwiftUI
import SwiftUI

/// The app shell.
///
/// It knows exactly two things: a ``ViewStore`` and an ``AppRouter``. No `World`, no
/// feature types, no idea how a child screen is assembled — it asks the router for a
/// screen and renders it. Both are handed in at construction by ``AppFeature``, which is
/// the only place holding the `World`.
///
/// Holding the router rather than reading it from `@Environment` is deliberate: it is
/// deterministic across sheet and inspector boundaries, which is exactly where SwiftUI's
/// environment propagation is not.
///
/// The layout is the same two-pane app it always was — sidebar lists articles, detail
/// edits whichever one is open — but both layouts now read the *same* `path`. macOS and
/// iPad-regular render `path.last` in the detail column; iPhone and iPad-compact bind the
/// path to a `NavigationStack`. `NavigationSplitView`'s own automatic compact-width push
/// was confirmed, by running this in Simulator across two separate fix attempts, to just
/// never fire, so the compact case stays an explicit stack.
public struct AppRootView: View, Routable {
    let viewStore: ViewStore<AppState, AppAction>
    public let router: AppRouter
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    init(viewStore: ViewStore<AppState, AppAction>, router: AppRouter) {
        self.viewStore = viewStore
        self.router = router
    }

    public var body: some View {
        #if os(macOS)
        splitLayout
        #else
        if horizontalSizeClass == .compact {
            compactLayout
        } else {
            splitLayout
        }
        #endif
    }

    /// Both panes always visible — macOS, and iPad in regular width. No "push" concept:
    /// the detail column reflects whatever is on top of the stack.
    ///
    /// Note that `viewStore.state.path.last` is read **here**, not inside the router:
    /// this is the only read of `path` on this layout, so it is the only thing that
    /// registers the observation dependency that makes the column update at all.
    private var splitLayout: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            router.detail(for: viewStore.state.path.last?.route)
                .modifier(ChatPresentation(viewStore: viewStore, router: router))
        }
        .modifier(SharedPresentations(viewStore: viewStore, router: router))
    }

    #if !os(macOS)
    /// iPhone, and iPad in compact width — one explicit stack over the same path.
    private var compactLayout: some View {
        NavigationStack(path: viewStore.binding(.state(\.routes), dispatch: .action(\.navigation.setPath))) {
            sidebar
                .navigationDestination(for: AppRoute.self) { route in
                    router.destination(for: route)
                        .modifier(ChatPresentation(viewStore: viewStore, router: router))
                }
        }
        .modifier(SharedPresentations(viewStore: viewStore, router: router))
    }
    #endif

    private var sidebar: some View {
        // Attached here, not on the outer `NavigationSplitView`/`NavigationStack`,
        // because a toolbar chained after the split view was confirmed — by actually
        // running this in Simulator — to not render at all once the sidebar collapses
        // to its own compact-width stack screen (iPhone): with zero articles there's no
        // way to ever reach the detail column, so a toolbar item scoped there would be
        // permanently unreachable. GitHub Sync has to work from an EMPTY article list,
        // so its entry point lives on the sidebar itself.
        router.sidebar()
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        viewStore.dispatch(.navigation(.presentGitHubSync))
                    } label: {
                        Label("GitHub Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
    }
}

/// Everything presented over the shell itself, shared by both layouts so the two cannot
/// drift. The assistant panel is *not* here — it belongs to whichever article is open, so
/// it is presented from the detail screen (see ``ChatPresentation``).
///
/// Every one of these is driven by a genuine `Optional` or a `Presentation` — never a
/// plain `Bool` behind `.presence`, which type-checks via an implicit optional promotion
/// and then reads `Optional(false) != nil`, i.e. permanently `true`. That single mistake
/// was what left this app's GitHub Sync sheet stacking undismissable modals.
private struct SharedPresentations: ViewModifier {
    let viewStore: ViewStore<AppState, AppAction>
    let router: AppRouter

    func body(content: Content) -> some View {
        content
            // `.presenting` wires BOTH dismissal edges — the binding's `set(false)` and
            // `onDismiss` — so the presentation walks `presented → dismissing → dismissed`
            // and can never stick half-way.
            .presenting(viewStore, \.gitHubSync, dismiss: .navigation(.dismissGitHubSync)) { _ in
                router.gitHubSync()
            }
            .confirmationDialog(
                "Discard unsaved changes and open the other article?",
                isPresented: viewStore.presence(.state(\.discardPrompt), dismiss: .navigation(.cancelPending)),
                titleVisibility: .visible
            ) {
                Button("Discard and Open", role: .destructive) {
                    viewStore.dispatch(.navigation(.resumePending))
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This article has unsaved changes. Switching now discards them — save first if you want to keep them.")
            }
    }
}

/// The assistant panel: an inspector alongside the editor on macOS, a sheet everywhere
/// else. `.inspector` on a compact-width column was confirmed, by running this in
/// Simulator, to take over the entire screen with no way to dismiss it.
///
/// Applied to the *detail* screen rather than the shell, because the assistant is a child
/// of whichever article is open — it reads and writes that article's Brainstorming field,
/// and its entry point is a button inside the editor, not a top-level toolbar item.
private struct ChatPresentation: ViewModifier {
    let viewStore: ViewStore<AppState, AppAction>
    let router: AppRouter

    func body(content: Content) -> some View {
        #if os(macOS)
        content.inspector(isPresented: viewStore.presence(.state(\.chat), dismiss: .navigation(.dismissChat))) {
            // `.inspector` has no `onDismiss`, so `onDisappear` is what drives the second
            // step of the presentation's walk — the same "the animation has finished"
            // signal `.presenting` gets for free on a sheet. If AppKit ever keeps the
            // collapsed content alive and it never fires, the state simply rests at
            // `dismissing`: `isPresented` is already false so nothing shows, the close
            // gate reads the (deliberately cleared) empty `turns`, and the next
            // `presentChat` replaces the whole thing with a fresh session anyway.
            router.chat()
                .onDisappear { viewStore.dispatch(.navigation(.dismissChat)) }
        }
        #else
        content.presenting(viewStore, \.chat, dismiss: .navigation(.dismissChat)) { _ in
            router.chat()
        }
        #endif
    }
}

/// The app's scene. `AppFeature` builds its own view, so there is nothing here but the
/// window — no store plumbing, no `World`.
public enum AppScene {
    @MainActor
    public static func scene(store: MainStoreType, world: World) -> some Scene {
        WindowGroup {
            AppFeature.view(store: store, environment: world)
        }
    }
}
