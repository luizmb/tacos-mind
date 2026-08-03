import FPMacros
import Foundation

/// The identity of a screen on the navigation stack — **payload-free on purpose**.
///
/// `NavigationStack` keys its destinations by the path element's *value*, so a payload
/// here would make "the same screen showing different data" a different destination:
/// SwiftUI tears the screen down and re-pushes it whenever that data changes. What a
/// screen currently shows belongs to its own feature state; a route only says *which*
/// screen. It is also what lets opening a second article replace the open editor in
/// place (see `NavigationAction.push`) rather than animating a pop and a push.
///
/// The root (the article list) is deliberately absent — it is not a destination, so it
/// can never be pushed on top of itself.
@Prisms
public enum AppRoute: Hashable, Sendable, Codable {
    case articleEditor
}

/// An ask to navigate — carrying whatever the destination needs in order to be built.
///
/// It is a transient action payload, never stored: the navigation reducer turns it into
/// the `StackEntry` that goes on the stack. Keeping intent separate from the screen is
/// what lets a feature dispatch `push(.articleEditor(summary))` without knowing anything
/// about `ArticleEditorFeature`, and what lets the same ask be *parked* while the user
/// answers a confirmation and replayed unchanged afterwards.
///
/// The payload is an ``ArticleSummary`` rather than a bare `URL` because the destination
/// needs both halves before it can load anything: the URL to read, and the slug the
/// sidebar highlights. It is also declared to match `ArticleListFeature.Action.select`'s
/// payload exactly, which is what keeps the wiring between them a single tacit line.
@Prisms
public enum NavigationRequest: Sendable, Equatable {
    case articleEditor(ArticleSummary)
}

public extension NavigationRequest {
    /// Which screen this ask resolves to, before anything is built. Used to decide
    /// whether a push replaces the top of the stack or grows it.
    var route: AppRoute {
        switch self {
        case .articleEditor: .articleEditor
        }
    }
}
