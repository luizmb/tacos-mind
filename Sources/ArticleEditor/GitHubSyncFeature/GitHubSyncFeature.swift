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
        /// Whether the settings/actions sheet is showing — store state, not local
        /// SwiftUI `@State`, so `AppRootView` never owns a shadow copy of its own.
        public var isPresented: Bool
        public var settings: GitHubSettings?
        public var repoURLInput: String
        public var branchInput: String
        public var tokenInput: String
        public var isSavingSettings: Bool
        public var isPulling: Bool
        /// Non-nil ⇒ the "this will overwrite local changes" confirmation is up.
        public var pendingPullPreview: PullPreview?
        public var isCommitting: Bool
        public var lastCommitOutcome: CommitOutcome?
        public var isOpeningPR: Bool
        public var lastPRURL: URL?
        public var lastError: String?

        public init() {
            isPresented = false
            settings = nil
            repoURLInput = ""
            branchInput = ""
            tokenInput = ""
            isSavingSettings = false
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
        /// Not on `ViewAction` — `AppRootView` dispatches this directly (it holds the raw
        /// `MainStoreType`, not a `GitHubSyncFeature`-scoped `ViewStore`), the same way it
        /// already drives the chat inspector's `.open`/`.close`.
        case setPresented(Bool)
        case loadSettings
        case settingsLoaded(GitHubSettings?)
        case setRepoURLInput(String)
        case setBranchInput(String)
        case setTokenInput(String)
        case saveSettings
        case settingsSaved(Result<Void, GitHubError>)
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
        public let saveGitHubSettings: @Sendable (GitHubSettings) -> Publisher<Void, GitHubError>
        public let previewPull: @Sendable (GitHubSettings) -> Publisher<PullPreview, GitHubError>
        public let applyPull: @Sendable (PullPreview) -> Publisher<Int, GitHubError>
        public let commitLocalChanges: @Sendable (GitHubSettings) -> Publisher<CommitOutcome, GitHubError>
        public let openPullRequest: @Sendable (GitHubSettings) -> Publisher<URL, GitHubError>

        public init(
            loadGitHubSettings: @escaping @Sendable () -> Publisher<GitHubSettings?, Never>,
            saveGitHubSettings: @escaping @Sendable (GitHubSettings) -> Publisher<Void, GitHubError>,
            previewPull: @escaping @Sendable (GitHubSettings) -> Publisher<PullPreview, GitHubError>,
            applyPull: @escaping @Sendable (PullPreview) -> Publisher<Int, GitHubError>,
            commitLocalChanges: @escaping @Sendable (GitHubSettings) -> Publisher<CommitOutcome, GitHubError>,
            openPullRequest: @escaping @Sendable (GitHubSettings) -> Publisher<URL, GitHubError>
        ) {
            self.loadGitHubSettings = loadGitHubSettings
            self.saveGitHubSettings = saveGitHubSettings
            self.previewPull = previewPull
            self.applyPull = applyPull
            self.commitLocalChanges = commitLocalChanges
            self.openPullRequest = openPullRequest
        }
    }

    public struct ViewState: Sendable, Equatable {
        public var isConfigured: Bool
        public var repoURLInput: String
        public var branchInput: String
        public var tokenInput: String
        public var isSavingSettings: Bool
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
        case setRepoURLInput(String)
        case setBranchInput(String)
        case setTokenInput(String)
        case saveSettings
        case pull
        case confirmPull
        case cancelPull
        case commit
        case openPR
    }

    public static let mapState = Reader<Environment, @MainActor @Sendable (State) -> ViewState> { _ in
        { state in
            ViewState(
                isConfigured: state.settings != nil,
                repoURLInput: state.repoURLInput,
                branchInput: state.branchInput,
                tokenInput: state.tokenInput,
                isSavingSettings: state.isSavingSettings,
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
            case .setRepoURLInput(let value): .setRepoURLInput(value)
            case .setBranchInput(let value): .setBranchInput(value)
            case .setTokenInput(let value): .setTokenInput(value)
            case .saveSettings: .saveSettings
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
            case .setPresented(let value):
                return .reduce { $0.isPresented = value }

            case .loadSettings:
                return .produce { ctx in ctx.environment.loadGitHubSettings().asEffect { Action.settingsLoaded($0) } }

            case .settingsLoaded(let settings):
                // The token is deliberately never round-tripped back into `tokenInput` —
                // it's a secret, not something to redisplay. `isConfigured` (derived from
                // `settings != nil`) drives the field's placeholder instead; leaving it
                // blank on Save keeps whatever token is already stored (see `.saveSettings`).
                return .reduce { state in
                    state.settings = settings
                    state.repoURLInput = settings?.repoURL ?? ""
                    state.branchInput = settings?.branch ?? ""
                    state.tokenInput = ""
                }

            case .setRepoURLInput(let value):
                return .reduce { $0.repoURLInput = value }

            case .setBranchInput(let value):
                return .reduce { $0.branchInput = value }

            case .setTokenInput(let value):
                return .reduce { $0.tokenInput = value }

            case .saveSettings:
                guard let state = context.stateBefore else { return .doNothing }
                let settings = Self.effectiveSettings(from: state)
                return .reduce { state in
                    state.isSavingSettings = true
                    state.lastError = nil
                }
                .produce { ctx in ctx.environment.saveGitHubSettings(settings).asEffect { Action.settingsSaved($0) } }

            case .settingsSaved(.success):
                guard let state = context.stateBefore else { return .doNothing }
                let settings = Self.effectiveSettings(from: state)
                return .reduce { state in
                    state.isSavingSettings = false
                    state.settings = settings
                    // Never keep the just-typed secret sitting in a visible field after
                    // it's safely stored — same reasoning as `.settingsLoaded` never
                    // seeding it in the first place.
                    state.tokenInput = ""
                }

            case .settingsSaved(.failure(let error)):
                return .reduce { state in
                    state.isSavingSettings = false
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
                        state.pendingPullPreview = preview
                    }
                }
                return .reduce { $0.pendingPullPreview = nil }
                    .produce { ctx in ctx.environment.applyPull(preview).asEffect { Action.pullApplied($0) } }

            case .pullPreviewed(.failure(let error)):
                return .reduce { state in
                    state.isPulling = false
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
                return .reduce { $0.isPulling = false }

            case .pullApplied(.failure(let error)):
                return .reduce { state in
                    state.isPulling = false
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
                return .reduce { state in
                    state.isCommitting = false
                    state.lastCommitOutcome = outcome
                }

            case .committed(.failure(let error)):
                return .reduce { state in
                    state.isCommitting = false
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

    public typealias Content = GitHubSyncView

    /// Builds the settings to save: an empty `tokenInput` means "leave the stored token
    /// alone," not "erase it" — the field is never pre-filled with the real secret, so
    /// blank is the normal, expected state for a Save that isn't rotating the token.
    private static func effectiveSettings(from state: State) -> GitHubSettings {
        let token = state.tokenInput.isEmpty ? (state.settings?.token ?? "") : state.tokenInput
        return GitHubSettings(repoURL: state.repoURLInput, branch: state.branchInput, token: token)
    }
}

extension GitHubError {
    var readableDescription: String {
        switch self {
        case .notConfigured: "Set a repo URL, branch, and token first."
        case .invalidRepoURL: "That doesn't look like a valid GitHub repo URL."
        case .network(let reason): "Network error: \(reason)"
        case .badStatus(let code): "GitHub returned HTTP \(code)."
        case .decoding(let reason): "Couldn't read GitHub's response: \(reason)"
        }
    }
}
