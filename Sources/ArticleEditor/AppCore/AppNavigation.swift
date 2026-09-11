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
    /// The user answered the question a parked push raised — carry on with it. Also how
    /// a gate that *acts* rather than asks reports success: a save taken on the user's
    /// behalf landing is the same "this gate is satisfied, move on" signal.
    case resumePending
    /// The user backed out — drop the parked push entirely.
    case cancelPending
    /// The save a parked ask took on the user's behalf failed. The ask cannot go through
    /// quietly any more, so it moves to the one gate that does put a question up.
    case pendingSaveFailed
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

/// Something that has to be settled before a navigation ask may proceed.
///
/// Most gates are settled *for* the user rather than by them: unsaved edits are written,
/// not queried, which is the same promise `appDidEnterBackground` and the macOS quit flow
/// already make everywhere else you can leave an article. Only a gate that genuinely
/// needs a decision — one that would cost the user something whichever way it goes — puts
/// a question up.
///
/// Gates are checked in declaration order and each resolution resumes at the gate
/// *after* the one just settled — a settled gate is never revisited. That ordering is
/// what stops "discard and open" from parking all over again on the very document it was
/// just told to abandon, and it is why ``unsavableDocument`` sits last: answering it
/// commits straight away, without the save it just said to skip.
public enum NavigationGate: Sendable, Equatable, CaseIterable {
    /// A live assistant conversation would be lost. `AIChatFeature` owns the dialog.
    case chatSession
    /// The open article has edits that are not on disk yet, and nothing stands in the way
    /// of writing them. Nobody is asked: the edits are saved and the ask resumes when the
    /// save lands (see ``NavigationAction/pendingSaveFailed`` for when it doesn't).
    case unsavedDocument
    /// The open article has edits that *cannot* be written on the user's behalf — the
    /// file changed underneath us, so saving would silently pick a winner, or the save
    /// was tried and failed. Only now is there a question worth asking, and the root owns
    /// the dialog, because by the time it matters the ask is already app-level.
    case unsavableDocument
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
            guard let gate = stateBefore.gate(startingAt: .chatSession) else { return commit(request) }
            return park(request, at: gate)

        case .resumePending:
            guard let pending = stateBefore.pendingNavigation else { return .doNothing }
            guard let next = pending.gate.successor,
                  let blocking = stateBefore.gate(startingAt: next)
            else { return commit(pending.request) }
            return park(pending.request, at: blocking)

        case .pendingSaveFailed:
            // Only the gate that took the save can be disappointed by it. Moving the ask
            // to the last gate rather than reading the failure back out of the editor is
            // what keeps a stale `saveError` from making every later switch ask instead
            // of simply trying again.
            guard let pending = stateBefore.pendingNavigation, pending.gate == .unsavedDocument else { return .doNothing }
            return park(pending.request, at: .unsavableDocument)

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

/// Holds `request` at `gate` — and takes whatever step that gate is *for*.
///
/// Parking and acting are one operation on purpose: a gate that is recorded but never
/// acted on is an ask that waits forever, which is exactly what a second call site is
/// free to forget. Both places that park (a fresh push, and a resume that lands on the
/// next gate) go through here, so a gate cannot be entered without its step being taken.
private func park(_ request: NavigationRequest, at gate: NavigationGate) -> Reaction<AppAction, AppState, World> {
    let parked = Reaction<AppAction, AppState, World>.reduce {
        $0.pendingNavigation = PendingNavigation(request: request, gate: gate)
    }
    switch gate {
    case .chatSession:
        // The chat owns its own "save this conversation?" dialog — asking it to close is
        // what raises it, and its answer comes back as one of the
        // `resumePending`/`cancelPending` bridges in `AppFeature`.
        return parked.produce { _ in AppAction.immediateDispatch(.chat(.close)) }
    case .unsavedDocument:
        // Not a question. The answer to "you have unsaved work and you're leaving" is the
        // same one the app already gives when iOS backgrounds it: write the file. The
        // save's outcome comes back through the `articleEditor.saved` bridge in
        // `AppFeature`, as `resumePending` or `pendingSaveFailed`.
        return parked.produce { _ in AppAction.immediateDispatch(.articleEditor(.save)) }
    case .unsavableDocument:
        // The only gate with nothing to do but wait — `discardPrompt` renders it.
        return parked
    }
}

/// Puts `request`'s screen on the stack **and tells it to load**.
///
/// The load cannot hang off the screen's own `onAppear`: opening a second article
/// *replaces* the top element rather than pushing a new one (see ``AppState/commit(_:)``),
/// so SwiftUI keeps the very same view alive, `onAppear` never fires again, and the
/// freshly built — deliberately empty — state would sit on its spinner forever. That is
/// invisible on iPhone, where you have to pop back before picking another article, and
/// permanent on iPad's two-pane layout, where every article after the first opened blank.
///
/// Navigation is what brings a screen into existence, so navigation is what starts it.
/// Both commit sites go through here, which is also why a resumed push cannot forget.
private func commit(_ request: NavigationRequest) -> Reaction<AppAction, AppState, World> {
    .reduce { $0.commit(request) }
        .produce { _ in AppAction.immediateDispatch(request.start) }
}

private extension NavigationRequest {
    /// The action that tells the screen this ask just built to load itself.
    var start: AppAction {
        switch self {
        case .articleEditor: .articleEditor(.start)
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
    /// The first gate at or after `first` that holds an ask back, or `nil` if it is free
    /// to proceed.
    ///
    /// Which ask it is no longer enters into it: a gate is a fact about the screen being
    /// left, not about where the user is going. The one gate that used to read the
    /// destination did so only to exempt re-opening the same article, which saving first
    /// makes unnecessary — see ``hasUnsavedEdits``.
    func gate(startingAt first: NavigationGate) -> NavigationGate? {
        NavigationGate.allCases
            .drop(while: { $0 != first })
            .first { $0.blocks(in: self) }
    }
}

private extension NavigationGate {
    /// The gate checked after this one. `nil` means nothing is left to settle.
    var successor: NavigationGate? {
        switch self {
        case .chatSession: .unsavedDocument
        case .unsavedDocument: .unsavableDocument
        case .unsavableDocument: nil
        }
    }

    /// The two document gates are deliberately complementary — unsaved edits are either
    /// writable or they are not — so a document in conflict falls straight past the
    /// saving gate to the asking one, and is never written on the user's behalf.
    func blocks(in state: AppState) -> Bool {
        switch self {
        case .chatSession:
            state.chat.wrapped.map { !$0.turns.isEmpty } ?? false
        case .unsavedDocument:
            state.hasUnsavedEdits && !state.hasConflictedEdits
        case .unsavableDocument:
            state.hasConflictedEdits
        }
    }
}

private extension AppState {
    /// Whether the open editor is holding edits that are not on disk.
    ///
    /// Where the ask is *going* no longer enters into it. It used to: re-opening the
    /// article already on screen was exempt on the grounds that it discards nothing —
    /// except ``commit(_:)`` rebuilds the entry either way, so the edits went with it,
    /// silently. Saving first makes the destination irrelevant, which is the honest
    /// reading of "you have unsaved work and you are leaving this screen".
    var hasUnsavedEdits: Bool {
        openEditor?.document?.hasUnsavedChanges == true
    }

    /// Whether those edits are ones the app must not resolve on the user's behalf: the
    /// file changed underneath them, so writing would quietly declare a winner.
    var hasConflictedEdits: Bool {
        guard hasUnsavedEdits, case .conflict = openEditor?.document?.externalChange else { return false }
        return true
    }
}
