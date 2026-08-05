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
        /// True while `firstSyncDecided`'s automatic first sync is in flight — lets
        /// `pullApplied`/`pushed` tell a first-link sync apart from a manual Pull/Push tap,
        /// since only the former should auto-close the sheet. It survives across the push
        /// *form*, because a first sync with local content now ends at a form the user has
        /// to confirm rather than a commit that fires by itself.
        public var isPerformingFirstSync: Bool
        /// Non-nil ⇒ linked. Only one repo can be linked at a time; `baseBranch` is the
        /// only field editable afterward (see `GitHubSyncRoute.editBranch`) — changing
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
        /// What the last pull did, including anything it deliberately left alone.
        public var lastPullOutcome: PullOutcome?
        /// Non-nil ⇒ the last pull skipped locally-modified files, and these are the remote
        /// bytes it declined to write. Held so `overwriteKeptLocal` can apply them without
        /// a second round-trip; it is the *only* thing keeping the discard option live.
        public var overwritablePull: PullPreview?
        /// Non-nil ⇒ the "discard your local changes?" confirmation is up. Store-owned like
        /// `isConfirmingUnlink`, for the same reason: the two destructive actions in this
        /// feature both gate on state the reducer can see, not on view-local flags.
        public var isConfirmingOverwrite: Bool

        public var isPushing: Bool
        public var lastPushOutcome: PushOutcome?
        /// The local bytes a push is about to send, captured at preview time so confirming
        /// the form doesn't re-read the disk (and can't pick up an edit made mid-form).
        public var pendingPushPreview: PushPreview?
        public var pushBranchInput: String
        public var pushCommitMessageInput: String
        public var pushPRTitleInput: String
        public var pushPRBodyInput: String

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
            lastPullOutcome = nil
            overwritablePull = nil
            isConfirmingOverwrite = false
            isPushing = false
            lastPushOutcome = nil
            pendingPushPreview = nil
            pushBranchInput = ""
            pushCommitMessageInput = ""
            pushPRTitleInput = ""
            pushPRBodyInput = ""
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
        case pullApplied(Result<PullOutcome, GitHubError>)
        case requestOverwriteKeptLocal
        case cancelOverwriteKeptLocal
        /// Discards the local edits the last pull preserved, replacing them with the remote
        /// bytes already sitting in `overwritablePull`. The one destructive path in a pull,
        /// and never automatic.
        case overwriteKeptLocal

        case push
        case pushPreviewed(Result<PushPreview, GitHubError>)
        case setPushBranchInput(String)
        case setPushCommitMessageInput(String)
        case setPushPRTitleInput(String)
        case setPushPRBodyInput(String)
        case confirmPush
        case cancelPush
        case pushed(Result<PushOutcome, GitHubError>)
    }

    public struct Environment: Sendable {
        public let loadGitHubSettings: @Sendable () -> Publisher<GitHubSettings?, Never>
        public let linkRepository: @Sendable (GitHubSettings) -> Publisher<Void, GitHubError>
        public let updateBranch: @Sendable (String) -> Publisher<Void, GitHubError>
        public let unlinkRepository: @Sendable () -> Publisher<Void, GitHubError>
        public let isArticlesDirEmpty: @Sendable () -> Publisher<Bool, Never>
        public let previewPull: @Sendable (GitHubSettings) -> Publisher<PullPreview, GitHubError>
        public let applyPull: @Sendable (PullPreview) -> Publisher<Int, GitHubError>
        public let previewPush: @Sendable (GitHubSettings) -> Publisher<PushPreview, GitHubError>
        public let performPush: @Sendable (GitHubSettings, PushRequest, PushPreview) -> Publisher<PushOutcome, GitHubError>

        public init(
            loadGitHubSettings: @escaping @Sendable () -> Publisher<GitHubSettings?, Never>,
            linkRepository: @escaping @Sendable (GitHubSettings) -> Publisher<Void, GitHubError>,
            updateBranch: @escaping @Sendable (String) -> Publisher<Void, GitHubError>,
            unlinkRepository: @escaping @Sendable () -> Publisher<Void, GitHubError>,
            isArticlesDirEmpty: @escaping @Sendable () -> Publisher<Bool, Never>,
            previewPull: @escaping @Sendable (GitHubSettings) -> Publisher<PullPreview, GitHubError>,
            applyPull: @escaping @Sendable (PullPreview) -> Publisher<Int, GitHubError>,
            previewPush: @escaping @Sendable (GitHubSettings) -> Publisher<PushPreview, GitHubError>,
            performPush: @escaping @Sendable (GitHubSettings, PushRequest, PushPreview) -> Publisher<PushOutcome, GitHubError>
        ) {
            self.loadGitHubSettings = loadGitHubSettings
            self.linkRepository = linkRepository
            self.updateBranch = updateBranch
            self.unlinkRepository = unlinkRepository
            self.isArticlesDirEmpty = isArticlesDirEmpty
            self.previewPull = previewPull
            self.applyPull = applyPull
            self.previewPush = previewPush
            self.performPush = performPush
        }
    }

    public struct ViewState: Sendable, Equatable {
        public var path: [GitHubSyncRoute]
        public var isConfigured: Bool
        public var repoURL: String
        public var baseBranch: String

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
        public var lastPullOutcome: PullOutcome?
        /// Only whether the discard option is available — the view has no use for the
        /// bytes themselves, just the names, which `lastPullOutcome.keptLocal` already has.
        public var canOverwriteKeptLocal: Bool
        public var isConfirmingOverwrite: Bool

        public var isPushing: Bool
        public var lastPushOutcome: PushOutcome?
        public var pushBranchInput: String
        public var pushCommitMessageInput: String
        public var pushPRTitleInput: String
        public var pushPRBodyInput: String
        /// How many articles the pending push would send — the form's footer copy, and the
        /// only thing the view needs from `pendingPushPreview`.
        public var pushFileCount: Int

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
        case requestOverwriteKeptLocal
        case cancelOverwriteKeptLocal
        case overwriteKeptLocal
        case push
        case setPushBranchInput(String)
        case setPushCommitMessageInput(String)
        case setPushPRTitleInput(String)
        case setPushPRBodyInput(String)
        case confirmPush
        case cancelPush
    }

    public static let mapState = Reader<Environment, @MainActor @Sendable (State) -> ViewState> { _ in
        { state in
            ViewState(
                path: state.path,
                isConfigured: state.settings != nil,
                repoURL: state.settings?.repoURL ?? "",
                baseBranch: state.settings?.baseBranch ?? "",
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
                lastPullOutcome: state.lastPullOutcome,
                canOverwriteKeptLocal: state.overwritablePull != nil,
                isConfirmingOverwrite: state.isConfirmingOverwrite,
                isPushing: state.isPushing,
                lastPushOutcome: state.lastPushOutcome,
                pushBranchInput: state.pushBranchInput,
                pushCommitMessageInput: state.pushCommitMessageInput,
                pushPRTitleInput: state.pushPRTitleInput,
                pushPRBodyInput: state.pushPRBodyInput,
                pushFileCount: state.pendingPushPreview?.files.count ?? 0,
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
            case .requestOverwriteKeptLocal: .requestOverwriteKeptLocal
            case .cancelOverwriteKeptLocal: .cancelOverwriteKeptLocal
            case .overwriteKeptLocal: .overwriteKeptLocal
            case .push: .push
            case .setPushBranchInput(let value): .setPushBranchInput(value)
            case .setPushCommitMessageInput(let value): .setPushCommitMessageInput(value)
            case .setPushPRTitleInput(let value): .setPushPRTitleInput(value)
            case .setPushPRBodyInput(let value): .setPushPRBodyInput(value)
            case .confirmPush: .confirmPush
            case .cancelPush: .cancelPush
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
                let settings = GitHubSettings(
                    repoURL: state.linkRepoInput,
                    baseBranch: state.linkBranchInput,
                    token: state.linkTokenInput
                )
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
            // content down (nothing local to lose); a non-empty one heads for a push
            // instead of destructively overwriting it. Both reuse the exact same
            // preview machinery + reducers as a manual Pull/Push tap, so the linked
            // screen's busy/outcome UI just works for this automatic step too.
            //
            // The push arm stops at the form rather than pushing outright — a first link
            // shouldn't invent a branch name, a commit message and a PR body on the user's
            // behalf and open a pull request before they've seen any of it.
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
                        state.isPushing = true
                        state.isPerformingFirstSync = true
                        state.lastError = nil
                    }
                    .produce { ctx in ctx.environment.previewPush(settings).asEffect { Action.pushPreviewed($0) } }
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
                    state.lastPullOutcome = nil
                    state.overwritablePull = nil
                    state.isConfirmingOverwrite = false
                    state.lastPushOutcome = nil
                    state.pendingPushPreview = nil
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
                    state.editBranchInput = settings.baseBranch
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
                    state.settings?.baseBranch = branch
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
                    state.lastPullOutcome = nil
                    state.overwritablePull = nil
                    state.isConfirmingOverwrite = false
                    state.lastError = nil
                }
                .produce { ctx in ctx.environment.previewPull(settings).asEffect { Action.pullPreviewed($0) } }

            // Local always wins, so a pull never stops to ask: `toAdd` (nothing local to
            // lose) is applied immediately and `toUpdate` is dropped from what gets
            // written. The remote bytes for those files aren't thrown away though — they
            // stay in `overwritablePull`, which is what makes the discard option on the
            // next screen instant rather than another round-trip.
            case .pullPreviewed(.success(let preview)):
                let keepLocal = preview.toUpdate.isEmpty ? nil : preview
                let keptNames = preview.toUpdate.map(\.name)
                let applying = PullPreview(toAdd: preview.toAdd, toUpdate: [])
                return .reduce { $0.overwritablePull = keepLocal }
                    .produce { ctx in
                        ctx.environment.applyPull(applying).asEffect { (result: Result<Int, GitHubError>) in
                            Action.pullApplied(result.map { PullOutcome(applied: $0, keptLocal: keptNames) })
                        }
                    }

            case .pullPreviewed(.failure(let error)):
                return .reduce { state in
                    state.isPulling = false
                    state.isPerformingFirstSync = false
                    state.lastError = error.readableDescription
                }

            // Applies the whole retained preview, `toUpdate` included — the one place local
            // edits are discarded. `keptLocal` is empty by construction: nothing is being
            // held back this time, which is what takes the discard option back off screen.
            case .requestOverwriteKeptLocal:
                guard context.stateBefore?.overwritablePull != nil else { return .doNothing }
                return .reduce { $0.isConfirmingOverwrite = true }

            case .cancelOverwriteKeptLocal:
                return .reduce { $0.isConfirmingOverwrite = false }

            case .overwriteKeptLocal:
                guard let preview = context.stateBefore?.overwritablePull else { return .doNothing }
                return .reduce { state in
                    state.isPulling = true
                    state.isConfirmingOverwrite = false
                    state.overwritablePull = nil
                    state.lastError = nil
                }
                .produce { ctx in
                    ctx.environment.applyPull(preview).asEffect { (result: Result<Int, GitHubError>) in
                        Action.pullApplied(result.map { PullOutcome(applied: $0, keptLocal: []) })
                    }
                }

            case .pullApplied(.success(let outcome)):
                guard context.stateBefore?.isPerformingFirstSync == true else {
                    return .reduce { state in
                        state.isPulling = false
                        state.lastPullOutcome = outcome
                    }
                }
                return .reduce { state in
                    state.isPulling = false
                    state.lastPullOutcome = outcome
                    state.isPerformingFirstSync = false
                }
                .produce { _ in Self.immediateDispatch(.firstSyncCompleted) }

            case .pullApplied(.failure(let error)):
                return .reduce { state in
                    state.isPulling = false
                    state.isPerformingFirstSync = false
                    state.lastError = error.readableDescription
                }

            case .push:
                guard let settings = context.stateBefore?.settings else {
                    return .reduce { $0.lastError = GitHubError.notConfigured.readableDescription }
                }
                return .reduce { state in
                    state.isPushing = true
                    state.lastPushOutcome = nil
                    state.lastError = nil
                }
                .produce { ctx in ctx.environment.previewPush(settings).asEffect { Action.pushPreviewed($0) } }

            // Nothing dirty short-circuits before the form: a form whose only possible
            // outcome is "nothing to push" is a form worth not showing. Otherwise every
            // field is seeded here — the branch name from the preview (the one piece that
            // needed a clock), the rest derived from the file list.
            case .pushPreviewed(.success(let preview)):
                guard !preview.files.isEmpty else {
                    return .reduce { state in
                        state.isPushing = false
                        state.isPerformingFirstSync = false
                        state.lastPushOutcome = .nothingToPush
                    }
                }
                let summary = Self.pushSummary(preview.files.count)
                return .reduce { state in
                    state.isPushing = false
                    state.pendingPushPreview = preview
                    state.pushBranchInput = preview.suggestedBranch
                    state.pushCommitMessageInput = summary
                    state.pushPRTitleInput = summary
                    state.pushPRBodyInput = preview.files.map { "- \($0.name)" }.joined(separator: "\n")
                    state.path = [.push]
                }

            case .pushPreviewed(.failure(let error)):
                return .reduce { state in
                    state.isPushing = false
                    state.isPerformingFirstSync = false
                    state.lastError = error.readableDescription
                }

            case .setPushBranchInput(let value):
                return .reduce { $0.pushBranchInput = value }

            case .setPushCommitMessageInput(let value):
                return .reduce { $0.pushCommitMessageInput = value }

            case .setPushPRTitleInput(let value):
                return .reduce { $0.pushPRTitleInput = value }

            case .setPushPRBodyInput(let value):
                return .reduce { $0.pushPRBodyInput = value }

            case .confirmPush:
                guard
                    let state = context.stateBefore,
                    let settings = state.settings,
                    let preview = state.pendingPushPreview,
                    !state.pushBranchInput.isEmpty
                else {
                    return .doNothing
                }
                let request = PushRequest(
                    branch: state.pushBranchInput,
                    commitMessage: state.pushCommitMessageInput,
                    prTitle: state.pushPRTitleInput,
                    prBody: state.pushPRBodyInput
                )
                return .reduce { state in
                    state.isPushing = true
                    state.lastError = nil
                }
                .produce { ctx in
                    ctx.environment.performPush(settings, request, preview).asEffect { Action.pushed($0) }
                }

            case .cancelPush:
                return .reduce { state in
                    state.path = []
                    state.pendingPushPreview = nil
                    state.isPushing = false
                    state.isPerformingFirstSync = false
                }

            case .pushed(.success(let outcome)):
                guard context.stateBefore?.isPerformingFirstSync == true else {
                    return .reduce { state in
                        state.isPushing = false
                        state.lastPushOutcome = outcome
                        state.pendingPushPreview = nil
                        state.path = []
                    }
                }
                return .reduce { state in
                    state.isPushing = false
                    state.lastPushOutcome = outcome
                    state.pendingPushPreview = nil
                    state.path = []
                    state.isPerformingFirstSync = false
                }
                .produce { _ in Self.immediateDispatch(.firstSyncCompleted) }

            // The form stays up on failure, inputs intact, so a rejected branch name or a
            // dropped connection is one correction away from retrying.
            case .pushed(.failure(let error)):
                return .reduce { state in
                    state.isPushing = false
                    state.isPerformingFirstSync = false
                    state.lastError = error.readableDescription
                }
            }
        }
    }

    /// The default commit message and PR title for a push of `count` articles. Pure, and
    /// deliberately the same string for both: they're one thought, and anyone who wants
    /// them to differ can edit either field.
    private static func pushSummary(_ count: Int) -> String {
        "Update \(count) article\(count == 1 ? "" : "s")"
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
