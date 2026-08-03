import AppDomain
import CoreFP
import CoreFPOperators
import Foundation
import ReactiveConcurrency
import SwiftRex
import SwiftRexArchitecture
import SwiftRexOperators
import SwiftRexReactiveConcurrency
import SwiftUI

@Feature(strategy: .observationSimple)
public enum GitHubSyncFeature {
    public struct State: Sendable, Equatable {
        /// The screens pushed inside this sheet — see ``GitHubSyncRoute``. Whether the
        /// *sheet itself* is showing is not here: the app owns that, because a screen
        /// that can present and dismiss itself is a second source of truth waiting to
        /// disagree with the one SwiftUI is actually rendering.
        public var path: [GitHubSyncRoute]
        /// True while `firstSyncDecided`'s automatic pull/commit is in flight — lets
        /// `pullApplied`/`committed` tell a first-link sync apart from a manual
        /// Pull/Commit tap, since only the former should auto-close the sheet.
        public var isPerformingFirstSync: Bool
        /// Non-nil ⇒ linked. Only one repo can be linked at a time; `branch` is the only
        /// field editable afterward (see `GitHubSyncRoute.editBranch`) — changing
        /// `repoURL`/`token` means unlinking and linking again.
        public var settings: GitHubSettings?

        // Link setup (one-time, shown only while `settings == nil`).
        public var linkRepoInput: String
        public var linkBranchInput: String
        public var linkTokenInput: String
        public var isLinking: Bool
        public var linkError: String?

        // Unlink confirmation.
        public var isConfirmingUnlink: Bool
        public var isUnlinking: Bool

        // Edit branch (the only mutation allowed on an already-linked repo).
        public var editBranchInput: String
        public var isSavingBranch: Bool

        public var isPulling: Bool
        /// Non-nil ⇒ the "this will overwrite local changes" confirmation is up.
        public var pendingPullPreview: PullPreview?
        public var isCommitting: Bool
        public var lastCommitOutcome: CommitOutcome?
        public var isOpeningPR: Bool
        public var lastPRURL: URL?
        public var lastError: String?

        public init() {
            path = []
            isPerformingFirstSync = false
            settings = nil
            linkRepoInput = ""
            linkBranchInput = ""
            linkTokenInput = ""
            isLinking = false
            linkError = nil
            isConfirmingUnlink = false
            isUnlinking = false
            editBranchInput = ""
            isSavingBranch = false
            isPulling = false
            pendingPullPreview = nil
            isCommitting = false
            lastCommitOutcome = nil
            isOpeningPR = false
            lastPRURL = nil
            lastError = nil
        }
    }

    @Prisms
    public enum Action: Sendable {
        /// What the inner `NavigationStack`'s binding delivers for every interactive
        /// change — the back button, the back-swipe — so user-driven and programmatic
        /// navigation inside this sheet land in the same reducer.
        case setPath([GitHubSyncRoute])
        /// "I'd like to be closed." A pure intent, bridged by `AppFeature`: only the app
        /// owns this sheet's presentation.
        case requestClose
        /// A freshly-linked repo finished its automatic first sync. Also a pure intent —
        /// the reason to close is known here, the ability to close is not.
        case firstSyncCompleted
        case loadSettings
        case settingsLoaded(GitHubSettings?)

        case requestLink
        case cancelLink
        case setLinkRepoInput(String)
        case setLinkBranchInput(String)
        case setLinkTokenInput(String)
        case confirmLink
        case linked(Result<GitHubSettings, GitHubError>)
        /// Internal follow-up to a successful `linked` — decides what a brand-new link's
        /// first sync does. Never dispatched by the view.
        case firstSyncDecided(isArticlesDirEmpty: Bool, GitHubSettings)

        case requestUnlink
        case cancelUnlink
        case confirmUnlink
        case unlinked(Result<Void, GitHubError>)

        case requestEditBranch
        case cancelEditBranch
        case setEditBranchInput(String)
        case confirmEditBranch
        case branchUpdated(Result<String, GitHubError>)

        case pull
        case pullPreviewed(Result<PullPreview, GitHubError>)
        case confirmPull
        case cancelPull
        case pullApplied(Result<Int, GitHubError>)
        case commit
        case committed(Result<CommitOutcome, GitHubError>)
        case openPR
        case prOpened(Result<URL, GitHubError>)
    }

    public struct Environment: Sendable {
        public let loadGitHubSettings: @Sendable () -> Publisher<GitHubSettings?, Never>
        public let linkRepository: @Sendable (GitHubSettings) -> Publisher<Void, GitHubError>
        public let updateBranch: @Sendable (String) -> Publisher<Void, GitHubError>
        public let unlinkRepository: @Sendable () -> Publisher<Void, GitHubError>
        public let isArticlesDirEmpty: @Sendable () -> Publisher<Bool, Never>
        public let previewPull: @Sendable (GitHubSettings) -> Publisher<PullPreview, GitHubError>
        public let applyPull: @Sendable (PullPreview) -> Publisher<Int, GitHubError>
        public let commitLocalChanges: @Sendable (GitHubSettings) -> Publisher<CommitOutcome, GitHubError>
        public let openPullRequest: @Sendable (GitHubSettings) -> Publisher<URL, GitHubError>

        public init(
            loadGitHubSettings: @escaping @Sendable () -> Publisher<GitHubSettings?, Never>,
            linkRepository: @escaping @Sendable (GitHubSettings) -> Publisher<Void, GitHubError>,
            updateBranch: @escaping @Sendable (String) -> Publisher<Void, GitHubError>,
            unlinkRepository: @escaping @Sendable () -> Publisher<Void, GitHubError>,
            isArticlesDirEmpty: @escaping @Sendable () -> Publisher<Bool, Never>,
            previewPull: @escaping @Sendable (GitHubSettings) -> Publisher<PullPreview, GitHubError>,
            applyPull: @escaping @Sendable (PullPreview) -> Publisher<Int, GitHubError>,
            commitLocalChanges: @escaping @Sendable (GitHubSettings) -> Publisher<CommitOutcome, GitHubError>,
            openPullRequest: @escaping @Sendable (GitHubSettings) -> Publisher<URL, GitHubError>
        ) {
            self.loadGitHubSettings = loadGitHubSettings
            self.linkRepository = linkRepository
            self.updateBranch = updateBranch
            self.unlinkRepository = unlinkRepository
            self.isArticlesDirEmpty = isArticlesDirEmpty
            self.previewPull = previewPull
            self.applyPull = applyPull
            self.commitLocalChanges = commitLocalChanges
            self.openPullRequest = openPullRequest
        }
    }

    public struct ViewState: Sendable, Equatable {
        public var path: [GitHubSyncRoute]
        public var isConfigured: Bool
        public var repoURL: String
        public var branch: String

        public var linkRepoInput: String
        public var linkBranchInput: String
        public var linkTokenInput: String
        public var isLinking: Bool
        public var linkError: String?

        public var isConfirmingUnlink: Bool
        public var isUnlinking: Bool

        public var editBranchInput: String
        public var isSavingBranch: Bool

        public var isPulling: Bool
        public var pendingPullPreview: PullPreview?
        public var isCommitting: Bool
        public var lastCommitOutcome: CommitOutcome?
        public var isOpeningPR: Bool
        public var lastPRURL: URL?
        public var lastError: String?
    }

    @Prisms
    public enum ViewAction: Sendable {
        case loadSettings
        case setPath([GitHubSyncRoute])
        case requestClose
        case requestLink
        case cancelLink
        case setLinkRepoInput(String)
        case setLinkBranchInput(String)
        case setLinkTokenInput(String)
        case confirmLink
        case requestUnlink
        case cancelUnlink
        case confirmUnlink
        case requestEditBranch
        case cancelEditBranch
        case setEditBranchInput(String)
        case confirmEditBranch
        case pull
        case confirmPull
        case cancelPull
        case commit
        case openPR
    }

    public static let mapState = Reader<Environment, @MainActor @Sendable (State) -> ViewState> { _ in
        { state in
            ViewState(
                path: state.path,
                isConfigured: state.settings != nil,
                repoURL: state.settings?.repoURL ?? "",
                branch: state.settings?.branch ?? "",
                linkRepoInput: state.linkRepoInput,
                linkBranchInput: state.linkBranchInput,
                linkTokenInput: state.linkTokenInput,
                isLinking: state.isLinking,
                linkError: state.linkError,
                isConfirmingUnlink: state.isConfirmingUnlink,
                isUnlinking: state.isUnlinking,
                editBranchInput: state.editBranchInput,
                isSavingBranch: state.isSavingBranch,
                isPulling: state.isPulling,
                pendingPullPreview: state.pendingPullPreview,
                isCommitting: state.isCommitting,
                lastCommitOutcome: state.lastCommitOutcome,
                isOpeningPR: state.isOpeningPR,
                lastPRURL: state.lastPRURL,
                lastError: state.lastError
            )
        }
    }

    public static let mapAction = Reader<Environment, @Sendable (ViewAction) -> Action> { _ in
        { viewAction in
            switch viewAction {
            case .loadSettings: .loadSettings
            case .setPath(let routes): .setPath(routes)
            case .requestClose: .requestClose
            case .requestLink: .requestLink
            case .cancelLink: .cancelLink
            case .setLinkRepoInput(let value): .setLinkRepoInput(value)
            case .setLinkBranchInput(let value): .setLinkBranchInput(value)
            case .setLinkTokenInput(let value): .setLinkTokenInput(value)
            case .confirmLink: .confirmLink
            case .requestUnlink: .requestUnlink
            case .cancelUnlink: .cancelUnlink
            case .confirmUnlink: .confirmUnlink
            case .requestEditBranch: .requestEditBranch
            case .cancelEditBranch: .cancelEditBranch
            case .setEditBranchInput(let value): .setEditBranchInput(value)
            case .confirmEditBranch: .confirmEditBranch
            case .pull: .pull
            case .confirmPull: .confirmPull
            case .cancelPull: .cancelPull
            case .commit: .commit
            case .openPR: .openPR
            }
        }
    }

    public static func initialState(with _: Void) -> State { .init() }

    // Every action here is a Command (fire → complete) — nothing in this feature is
    // long-lived or state-gated, so there's no Subscription/`.supervise` case (unlike
    // AIChatFeature's `startListening`).
    public static func behavior() -> Behavior<Action, State, Environment> {
        .handle { action, context in
            switch action {
            case .setPath(let routes):
                return .reduce { $0.path = routes }

            // Both are pure triggers for `AppFeature`'s fold, which owns this sheet's
            // presentation — same shape as `ArticleEditorFeature.openChat`.
            case .requestClose, .firstSyncCompleted:
                return .doNothing

            case .loadSettings:
                return .produce { ctx in ctx.environment.loadGitHubSettings().asEffect { Action.settingsLoaded($0) } }

            case .settingsLoaded(let settings):
                return .reduce { $0.settings = settings }

            // Clearing the form on the way in is what lets the inputs stay flat fields
            // rather than travelling in the path element: a pushed screen always starts
            // empty, so leftovers from a previous visit are unobservable.
            case .requestLink:
                return .reduce { state in
                    state.path = [.link]
                    state.linkRepoInput = ""
                    state.linkBranchInput = "main"
                    state.linkTokenInput = ""
                    state.linkError = nil
                }

            case .cancelLink:
                return .reduce { $0.path = [] }

            case .setLinkRepoInput(let value):
                return .reduce { $0.linkRepoInput = value }

            case .setLinkBranchInput(let value):
                return .reduce { $0.linkBranchInput = value }

            case .setLinkTokenInput(let value):
                return .reduce { $0.linkTokenInput = value }

            case .confirmLink:
                guard let state = context.stateBefore else { return .doNothing }
                guard !state.linkRepoInput.isEmpty, !state.linkBranchInput.isEmpty, !state.linkTokenInput.isEmpty else {
                    return .reduce { $0.linkError = "Fill in the repo, branch, and token." }
                }
                let settings = GitHubSettings(repoURL: state.linkRepoInput, branch: state.linkBranchInput, token: state.linkTokenInput)
                return .reduce { state in
                    state.isLinking = true
                    state.linkError = nil
                }
                .produce { ctx in
                    ctx.environment.linkRepository(settings).asEffect { (result: Result<Void, GitHubError>) in
                        Action.linked(result.map { settings })
                    }
                }

            case .linked(.success(let settings)):
                return .reduce { state in
                    state.settings = settings
                    state.isLinking = false
                    state.path = []
                    state.linkRepoInput = ""
                    state.linkBranchInput = ""
                    state.linkTokenInput = ""
                }
                .produce { ctx in
                    ctx.environment.isArticlesDirEmpty().asEffect { isEmpty in
                        Action.firstSyncDecided(isArticlesDirEmpty: isEmpty, settings)
                    }
                }

            case .linked(.failure(let error)):
                return .reduce { state in
                    state.isLinking = false
                    state.linkError = error.readableDescription
                }

            // A freshly-linked repo's first sync: an empty local Articles/ pulls remote
            // content down (nothing local to lose); a non-empty one pushes local up
            // instead of destructively overwriting it — reuses the exact same
            // preview/commit machinery + reducers as a manual Pull/Commit tap, so the
            // linked screen's own busy/outcome UI just works for this automatic step too.
            case .firstSyncDecided(let isEmpty, let settings):
                if isEmpty {
                    return .reduce { state in
                        state.isPulling = true
                        state.isPerformingFirstSync = true
                        state.lastError = nil
                    }
                    .produce { ctx in ctx.environment.previewPull(settings).asEffect { Action.pullPreviewed($0) } }
                } else {
                    return .reduce { state in
                        state.isCommitting = true
                        state.isPerformingFirstSync = true
                        state.lastError = nil
                    }
                    .produce { ctx in ctx.environment.commitLocalChanges(settings).asEffect { Action.committed($0) } }
                }

            case .requestUnlink:
                return .reduce { $0.isConfirmingUnlink = true }

            case .cancelUnlink:
                return .reduce { $0.isConfirmingUnlink = false }

            case .confirmUnlink:
                return .reduce { state in
                    state.isConfirmingUnlink = false
                    state.isUnlinking = true
                }
                .produce { ctx in ctx.environment.unlinkRepository().asEffect { Action.unlinked($0) } }

            case .unlinked(.success):
                return .reduce { state in
                    state.isUnlinking = false
                    state.settings = nil
                    state.lastCommitOutcome = nil
                    state.lastPRURL = nil
                    state.pendingPullPreview = nil
                }

            case .unlinked(.failure(let error)):
                return .reduce { state in
                    state.isUnlinking = false
                    state.lastError = error.readableDescription
                }

            case .requestEditBranch:
                guard let settings = context.stateBefore?.settings else { return .doNothing }
                return .reduce { state in
                    state.path = [.editBranch]
                    state.editBranchInput = settings.branch
                }

            case .cancelEditBranch:
                return .reduce { $0.path = [] }

            case .setEditBranchInput(let value):
                return .reduce { $0.editBranchInput = value }

            case .confirmEditBranch:
                guard let branch = context.stateBefore?.editBranchInput, !branch.isEmpty else { return .doNothing }
                return .reduce { $0.isSavingBranch = true }
                    .produce { ctx in
                        ctx.environment.updateBranch(branch).asEffect { (result: Result<Void, GitHubError>) in
                            Action.branchUpdated(result.map { branch })
                        }
                    }

            case .branchUpdated(.success(let branch)):
                return .reduce { state in
                    state.isSavingBranch = false
                    state.path = []
                    state.settings?.branch = branch
                }

            case .branchUpdated(.failure(let error)):
                return .reduce { state in
                    state.isSavingBranch = false
                    state.lastError = error.readableDescription
                }

            case .pull:
                guard let settings = context.stateBefore?.settings else {
                    return .reduce { $0.lastError = GitHubError.notConfigured.readableDescription }
                }
                return .reduce { state in
                    state.isPulling = true
                    state.lastError = nil
                }
                .produce { ctx in ctx.environment.previewPull(settings).asEffect { Action.pullPreviewed($0) } }

            case .pullPreviewed(.success(let preview)):
                guard preview.localOnlyChanges.isEmpty else {
                    return .reduce { state in
                        state.isPulling = false
                        state.isPerformingFirstSync = false
                        state.pendingPullPreview = preview
                    }
                }
                return .reduce { $0.pendingPullPreview = nil }
                    .produce { ctx in ctx.environment.applyPull(preview).asEffect { Action.pullApplied($0) } }

            case .pullPreviewed(.failure(let error)):
                return .reduce { state in
                    state.isPulling = false
                    state.isPerformingFirstSync = false
                    state.lastError = error.readableDescription
                }

            case .confirmPull:
                guard let preview = context.stateBefore?.pendingPullPreview else { return .doNothing }
                return .reduce { $0.pendingPullPreview = nil }
                    .produce { ctx in ctx.environment.applyPull(preview).asEffect { Action.pullApplied($0) } }

            case .cancelPull:
                return .reduce { state in
                    state.pendingPullPreview = nil
                    state.isPulling = false
                }

            case .pullApplied(.success):
                guard context.stateBefore?.isPerformingFirstSync == true else {
                    return .reduce { $0.isPulling = false }
                }
                return .reduce { state in
                    state.isPulling = false
                    state.isPerformingFirstSync = false
                }
                .produce { _ in Self.immediateDispatch(.firstSyncCompleted) }

            case .pullApplied(.failure(let error)):
                return .reduce { state in
                    state.isPulling = false
                    state.isPerformingFirstSync = false
                    state.lastError = error.readableDescription
                }

            case .commit:
                guard let settings = context.stateBefore?.settings else {
                    return .reduce { $0.lastError = GitHubError.notConfigured.readableDescription }
                }
                return .reduce { state in
                    state.isCommitting = true
                    state.lastError = nil
                }
                .produce { ctx in ctx.environment.commitLocalChanges(settings).asEffect { Action.committed($0) } }

            case .committed(.success(let outcome)):
                guard context.stateBefore?.isPerformingFirstSync == true else {
                    return .reduce { state in
                        state.isCommitting = false
                        state.lastCommitOutcome = outcome
                    }
                }
                return .reduce { state in
                    state.isCommitting = false
                    state.lastCommitOutcome = outcome
                    state.isPerformingFirstSync = false
                }
                .produce { _ in Self.immediateDispatch(.firstSyncCompleted) }

            case .committed(.failure(let error)):
                return .reduce { state in
                    state.isCommitting = false
                    state.isPerformingFirstSync = false
                    state.lastError = error.readableDescription
                }

            case .openPR:
                guard let settings = context.stateBefore?.settings else {
                    return .reduce { $0.lastError = GitHubError.notConfigured.readableDescription }
                }
                return .reduce { state in
                    state.isOpeningPR = true
                    state.lastError = nil
                }
                .produce { ctx in ctx.environment.openPullRequest(settings).asEffect { Action.prOpened($0) } }

            case .prOpened(.success(let url)):
                return .reduce { state in
                    state.isOpeningPR = false
                    state.lastPRURL = url
                }

            case .prOpened(.failure(let error)):
                return .reduce { state in
                    state.isOpeningPR = false
                    state.lastError = error.readableDescription
                }
            }
        }
    }

    /// Fires `action` as an immediate follow-up dispatch from within a `.produce` step —
    /// the same "wrap a pure value in a one-shot Effect" trick used elsewhere in the app.
    private static func immediateDispatch(_ action: Action) -> Effect<Action> {
        let transform: @Sendable (()) -> Action = const(action)
        return Publisher<Void, Never>.just(()).asEffect(transform)
    }

    public typealias Content = GitHubSyncView
}

extension GitHubError {
    var readableDescription: String {
        switch self {
        case .notConfigured: "Link a repo first."
        case .invalidRepoURL: "That doesn't look like a valid GitHub repo URL."
        case .network(let reason): "Network error: \(reason)"
        case .badStatus(let code): "GitHub returned HTTP \(code)."
        case .decoding(let reason): "Couldn't read GitHub's response: \(reason)"
        }
    }
}
