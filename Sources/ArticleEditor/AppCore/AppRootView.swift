import AIChatFeature
import ArticleEditorFeature
import ArticleListFeature
import GitHubSyncFeature
import SwiftRex
import SwiftRexSwiftUI
import SwiftUI

/// The whole app is a fixed two-pane layout: sidebar lists articles, detail edits
/// whichever one is open. macOS/iPad-regular-width show both panes via
/// `NavigationSplitView`. iPhone/iPad-compact use an explicit `NavigationStack` push
/// instead — `NavigationSplitView`'s own automatic compact-width push (driven by the
/// sidebar's `List` selection) was confirmed, by actually running this in Simulator
/// across two separate fix attempts, to just never fire: tapping an article (or
/// auto-opening a freshly created one) silently did nothing. `NavigationStack` +
/// `.navigationDestination(isPresented:)` is unambiguous, well-documented push/pop
/// behavior that doesn't depend on that heuristic at all.
public enum AppScene {
    @MainActor
    public static func scene(store: MainStoreType, world: World) -> some Scene {
        WindowGroup {
            AppRootView(store: store, world: world)
        }
    }
}

public struct AppRootView: View {
    // `@Observable` (SwiftRex's `ViewStore`, not local state) — a plain `MainStoreType` is
    // never tracked by SwiftUI, so `body` would never re-invoke when `chat.isOpen` /
    // `gitHubSync.isPresented` flip, and the toolbar buttons below would silently no-op
    // (confirmed: the dispatch and reducer both ran correctly, only the re-render didn't).
    @State private var viewStore: ViewStore<AppState, AppAction>
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    let world: World

    public init(store: MainStoreType, world: World) {
        _viewStore = State(initialValue: ViewStore(store))
        self.world = world
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

    /// Both panes always visible — macOS, and iPad in regular width (full-screen or a
    /// wide Split View). No "push" concept: the detail column just reflects whatever's
    /// currently open, exactly as it always has.
    private var splitLayout: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .sheet(isPresented: isGitHubSyncPresented) {
            AppScopes.gitHubSync.view(of: GitHubSyncFeature.self, from: viewStore, world: world)
        }
    }

    #if !os(macOS)
    /// iPhone, and iPad in compact width — an explicit push/pop stack instead of relying
    /// on `NavigationSplitView`'s compact behavior (see the type-level doc above).
    private var compactLayout: some View {
        NavigationStack {
            sidebar
                .navigationDestination(isPresented: isArticleEditorPushed) {
                    detail
                }
        }
        .sheet(isPresented: isGitHubSyncPresented) {
            AppScopes.gitHubSync.view(of: GitHubSyncFeature.self, from: viewStore, world: world)
        }
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
        AppScopes.articleList.view(of: ArticleListFeature.self, from: viewStore, world: world)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        isGitHubSyncPresented.wrappedValue = true
                    } label: {
                        Label("GitHub Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
    }

    private var detail: some View {
        // The assistant is a child of whichever article is open (see
        // `AppFeature.openChatBridge`) — its entry point is a button next to
        // Brainstorming inside `ArticleEditorContent`, not a toolbar button here, and
        // its presentation is scoped to the detail column for the same reason.
        AppScopes.articleEditor.view(of: ArticleEditorFeature.self, from: viewStore, world: world)
            #if os(macOS)
            .inspector(isPresented: isChatOpen) {
                AppScopes.chat.view(of: AIChatFeature.self, from: viewStore, world: world)
            }
            #else
            // `.inspector` on a compact-width column was confirmed, by running this in
            // Simulator, to take over the entire screen with no way to dismiss it.
            // `.sheet` doesn't have that failure mode — it's the same presentation
            // GitHub Sync already uses successfully.
            .sheet(isPresented: isChatOpen) {
                AppScopes.chat.view(of: AIChatFeature.self, from: viewStore, world: world)
            }
            #endif
    }

    /// `.open`/`.close` (not a single `setOpen(Bool)`) because they trigger different
    /// work — `.open` checks assistant availability, `.close` also stops listening — so
    /// the binding's dispatch reviews the new value into whichever action applies.
    private var isChatOpen: Binding<Bool> {
        viewStore.binding(.state(\.chat.isOpen), dispatch: .action(review: { isOpen in .chat(isOpen ? .open : .close) }))
    }

    /// Store-backed, not local `@State` — `GitHubSyncFeature.State` already lives in the
    /// store, so its own presentation flag is the single source of truth, same as chat's.
    private var isGitHubSyncPresented: Binding<Bool> {
        viewStore.binding(.state(\.gitHubSync.isPresented), dispatch: .action(\.gitHubSync.setPresented))
    }

    #if !os(macOS)
    /// Drives the compact stack's push/pop. `selectedSlug` becomes non-nil the instant an
    /// article is tapped or created (see `ArticleListFeature`'s `.select`/`.created`) —
    /// popping back (the system back gesture/button) dispatches `.clearSelection`, so the
    /// sidebar shows nothing highlighted rather than stale-marking whatever was last open.
    /// `.presence` is the same primitive `isChatOpen`'s sibling `GitHubSyncFeature` uses
    /// for its own dismiss-only `Optional -> Bool` binding — `.navigationDestination`
    /// isn't called out by name in its doc comment, but it's the identical shape as
    /// `.sheet(isPresented:)`, so the same primitive applies.
    private var isArticleEditorPushed: Binding<Bool> {
        viewStore.presence(.state(\.articleList.selectedSlug), dismiss: .articleList(.clearSelection))
    }
    #endif
}
