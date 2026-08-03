import AIChatFeature
import AppDomain
import ArticleEditorFeature
import FPMacros
import Foundation
import GitHubSyncFeature
import SwiftRex
import SwiftRexArchitecture
import SwiftRexSwiftUI

// MARK: - Navigation action

/// The navigation vocabulary — the only actions that move the user between screens.
///
/// `push` carries a ``NavigationRequest`` — the *ask* ("open this article"), not the
/// screen itself. The reducer turns a request into a ``StackEntry``, so a feature can
/// dispatch tacitly without knowing what state the destination needs. A request is a
/// transient action payload, never stored, so it is not a second source of truth.
///
/// `setPath` is what `NavigationStack`'s binding delivers for every interactive change —
/// back button, back-swipe, pop-to-root — so user-driven and programmatic navigation
/// land in the same reducer.
///
/// The chat and GitHub Sync cases are here rather than in the features themselves
/// because the *parent* owns a child's presentation: a screen cannot present or dismiss
/// itself without a second source of truth appearing (which is exactly how this app's
/// previous `isOpen`/`isPresented` flags drifted out of step with what was on screen).
@Prisms
public enum NavigationAction: Sendable {
    case push(NavigationRequest)
    case pop
    case popToRoot
    case setPath([AppRoute])
    /// The user answered the question a parked push raised — carry on with it.
    case resumePending
    /// The user backed out — drop the parked push entirely.
    case cancelPending
    case presentChat
    /// One stage-dependent step of the chat's `Presentation`. Dispatched from **both**
    /// dismissal edges (the binding's `set(false)` and the animation-complete signal),
    /// so the presentation can never stick half-dismissed.
    case dismissChat
    case presentGitHubSync
    /// One stage-dependent step, same as `dismissChat`.
    case dismissGitHubSync
}

// MARK: - Gates

/// A question that has to be answered before a navigation ask may proceed.
///
/// Gates are checked in declaration order and each resolution resumes at the gate
/// *after* the one just answered — an answered gate is never re-asked. That ordering is
/// what stops "discard and open" from parking all over again on the very document it was
/// just told to abandon.
public enum NavigationGate: Sendable, Equatable, CaseIterable {
    /// A live assistant conversation would be lost. `AIChatFeature` owns the dialog.
    case chatSession
    /// The open article has edits that switching away would discard. The root owns the
    /// dialog, because by the time it matters the ask is already app-level.
    case unsavedDocument
}

/// A navigation ask held back until the user answers the gate it ran into.
///
/// One value replaces what used to be two independent, mutually unaware holds — an
/// app-level `pendingArticleSwitch` and an editor-level `pendingOpenURL` — each resuming
/// a beat late through its own bridge.
public struct PendingNavigation: Sendable, Equatable {
    public let request: NavigationRequest
    public let gate: NavigationGate

    public init(request: NavigationRequest, gate: NavigationGate) {
        self.request = request
        self.gate = gate
    }
}

// MARK: - The navigation behavior

/// The only writer of `path`, `pendingNavigation`, `chat`'s stage and `gitHubSync`'s
/// stage.
///
/// Every case is a plain list or stage operation, because the list *is* the state. There
/// is no reconciliation step: nothing to seed after a push and nothing to discard after a
/// pop, since a screen's data lives in the element that was appended or removed.
func navigationBehavior() -> Behavior<AppAction, AppState, World> {
    .handle { action, context in
        guard let navigation = AppAction.prism.navigation.preview(action),
              let stateBefore = context.stateBefore
        else { return .doNothing }

        switch navigation {
        case .push(let request):
            switch stateBefore.gate(for: request, startingAt: .chatSession) {
            case .chatSession:
                // The chat owns its own "save this conversation?" dialog — asking it to
                // close is what raises it, and its answer comes back as one of the
                // `resumePending`/`cancelPending` bridges in `AppFeature`.
                return .reduce { $0.pendingNavigation = PendingNavigation(request: request, gate: .chatSession) }
                    .produce { _ in AppAction.immediateDispatch(.chat(.close)) }

            case .unsavedDocument:
                return .reduce { $0.pendingNavigation = PendingNavigation(request: request, gate: .unsavedDocument) }

            case nil:
                return .reduce { $0.commit(request) }
            }

        case .resumePending:
            guard let pending = stateBefore.pendingNavigation else { return .doNothing }
            guard let next = pending.gate.successor,
                  let blocking = stateBefore.gate(for: pending.request, startingAt: next)
            else { return .reduce { $0.commit(pending.request) } }
            return .reduce { $0.pendingNavigation = PendingNavigation(request: pending.request, gate: blocking) }

        case .cancelPending:
            guard stateBefore.pendingNavigation != nil else { return .doNothing }
            return .reduce { $0.pendingNavigation = nil }

        case .pop:
            guard !stateBefore.path.isEmpty else { return .doNothing }
            return .reduce { state in
                state.path.removeLast()
                state.syncSidebarSelection()
            }

        case .popToRoot:
            return .reduce { state in
                state.path.removeAll()
                state.syncSidebarSelection()
            }

        case .setPath(let routes):
            // SwiftUI only ever shortens the path interactively. Folding to the longest
            // matching prefix is total: it cannot desynchronise, and an unexpected path
            // simply truncates rather than leaving `path` disagreeing with the screen.
            return .reduce { state in
                state.path = zip(state.path, routes)
                    .prefix { $0.route == $1 }
                    .map(\.0)
                state.syncSidebarSelection()
            }

        case .presentChat:
            let brainstorming = stateBefore.openEditor?.document?.brainstorming ?? ""
            return .reduce { $0.chat = .presented(AIChatFeature.State(brainstorming: brainstorming)) }

        case .dismissChat:
            return .reduce { $0.chat = $0.chat.dismiss() }

        case .presentGitHubSync:
            return .reduce { $0.gitHubSync = .presented(GitHubSyncFeature.initialState(with: ())) }

        case .dismissGitHubSync:
            return .reduce { $0.gitHubSync = $0.gitHubSync.dismiss() }
        }
    }
}

// MARK: - Hydration

extension AppState {
    /// Puts `request`'s screen on the stack, fully built.
    ///
    /// Replacing rather than appending when the top is already that route is precisely
    /// why ``AppRoute`` is payload-free: `routes` comes out identical, so
    /// `NavigationStack` does not tear the screen down and re-push it, and the compact
    /// stack cannot grow one editor per article visited. The affine scope simply re-reads
    /// the replaced element.
    mutating func commit(_ request: NavigationRequest) {
        pendingNavigation = nil
        let entry = entry(for: request)
        if path.last?.route == entry.route {
            path[path.index(before: path.endIndex)] = entry
        } else {
            path.append(entry)
        }
        syncSidebarSelection()
    }

    /// Builds the stack entry a request asks for — by **construction**, so there is never
    /// a half-initialised screen for someone else to finish assembling. What the screen
    /// then loads from disk is its own business, driven by its own `.start`.
    func entry(for request: NavigationRequest) -> StackEntry {
        switch request {
        case .articleEditor(let summary):
            .articleEditor(ArticleEditorFeature.State(opening: summary))
        }
    }

    /// The one deliberate mirror in the app: the sidebar's highlight is a *view* of the
    /// stack, re-derived in the same synchronous step that changes it. Keeping it a
    /// stored field of `ArticleListFeature` (rather than deriving it in `mapState`) is
    /// only because a feature's `mapState` cannot see the app's path; making navigation
    /// its single writer is what removes the three bridges that used to race over it.
    mutating func syncSidebarSelection() {
        articleList.selectedSlug = openEditor?.opened.slug
    }
}

// MARK: - Gate evaluation

extension AppState {
    /// The first gate at or after `first` that blocks `request`, or `nil` if the ask is
    /// free to proceed.
    func gate(for request: NavigationRequest, startingAt first: NavigationGate) -> NavigationGate? {
        NavigationGate.allCases
            .drop(while: { $0 != first })
            .first { $0.blocks(request, in: self) }
    }
}

private extension NavigationGate {
    /// The gate checked after this one. `nil` means nothing is left to ask.
    var successor: NavigationGate? {
        switch self {
        case .chatSession: .unsavedDocument
        case .unsavedDocument: nil
        }
    }

    func blocks(_ request: NavigationRequest, in state: AppState) -> Bool {
        switch self {
        case .chatSession:
            state.chat.wrapped.map { !$0.turns.isEmpty } ?? false
        case .unsavedDocument:
            state.wouldDiscardEdits(request)
        }
    }
}

private extension AppState {
    /// Whether committing `request` would replace an editor holding unsaved edits with a
    /// *different* article. Re-opening the article already on screen is not a discard.
    func wouldDiscardEdits(_ request: NavigationRequest) -> Bool {
        guard case .articleEditor(let summary) = request, let editor = openEditor else { return false }
        return editor.opened.url != summary.url && editor.document?.hasUnsavedChanges == true
    }
}
