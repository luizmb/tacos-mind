import AppDomain
import Foundation
import ReactiveConcurrency
import SwiftRex
import SwiftRexTesting
import Testing

@testable import GitHubSyncFeature

/// Captures what an environment closure was actually called with, so a test can assert on
/// the *arguments* a reducer produced and not just the state it landed in. `@unchecked
/// Sendable` is safe here for the ordinary reason: every access to `storage` goes through
/// `lock`, and the environment closures this is used from are `@Sendable`.
final class Recorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    func record(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(value)
    }

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// The shared fixture for every `GitHubSyncFeature` suite. A protocol rather than a base
/// type or a free function so conforming suites call `makeStore(...)`/`configured()`
/// unqualified — the suites are split across files only to keep each one readable, and
/// they should not have to say so at every call site.
@MainActor
protocol GitHubSyncTestHarness {}

extension GitHubSyncTestHarness {
    var settings: GitHubSettings {
        GitHubSettings(repoURL: "https://github.com/luizmb/ios.lu", baseBranch: "main", token: "tok")
    }

    /// Every dependency defaults to the boring success case, so each test overrides only
    /// the one or two closures it is actually about.
    func makeStore(
        initial: GitHubSyncFeature.State = .init(),
        loadGitHubSettings: @escaping @Sendable () -> Publisher<GitHubSettings?, Never> = { .just(nil) },
        linkRepository: @escaping @Sendable (GitHubSettings) -> Publisher<Void, GitHubError> = { _ in .just(()) },
        updateBranch: @escaping @Sendable (String) -> Publisher<Void, GitHubError> = { _ in .just(()) },
        unlinkRepository: @escaping @Sendable () -> Publisher<Void, GitHubError> = { .just(()) },
        isArticlesDirEmpty: @escaping @Sendable () -> Publisher<Bool, Never> = { .just(true) },
        previewPull: @escaping @Sendable (GitHubSettings) -> Publisher<PullPreview, GitHubError> = { _ in
            .just(PullPreview(toAdd: [], toUpdate: []))
        },
        applyPull: @escaping @Sendable (PullPreview) -> Publisher<Int, GitHubError> = { _ in .just(0) },
        previewPush: @escaping @Sendable (GitHubSettings) -> Publisher<PushPreview, GitHubError> = { _ in
            .just(PushPreview(files: [], suggestedBranch: "articles/2026-08-05-1432"))
        },
        performPush: @escaping @Sendable (
            GitHubSettings,
            PushRequest,
            PushPreview
        ) -> Publisher<PushOutcome, GitHubError> = { _, _, _ in .just(.nothingToPush) }
    ) -> TestStore<GitHubSyncFeature.Action, GitHubSyncFeature.State, GitHubSyncFeature.Environment> {
        TestStore(
            initial: initial,
            behavior: GitHubSyncFeature.behavior(),
            environment: GitHubSyncFeature.Environment(
                loadGitHubSettings: loadGitHubSettings,
                linkRepository: linkRepository,
                updateBranch: updateBranch,
                unlinkRepository: unlinkRepository,
                isArticlesDirEmpty: isArticlesDirEmpty,
                previewPull: previewPull,
                applyPull: applyPull,
                previewPush: previewPush,
                performPush: performPush
            )
        )
    }

    /// An already-linked starting state — the precondition for everything except the link
    /// flow itself.
    func configured() -> GitHubSyncFeature.State {
        var state = GitHubSyncFeature.State()
        state.settings = settings
        return state
    }

    /// A filled-in link form, ready to confirm.
    func linkFormState() -> GitHubSyncFeature.State {
        var state = GitHubSyncFeature.State()
        state.path = [.link]
        state.linkRepoInput = settings.repoURL
        state.linkBranchInput = settings.baseBranch
        state.linkTokenInput = settings.token
        return state
    }

    /// Confirms the link form and walks the `linked` step, leaving the store poised on
    /// `firstSyncDecided`. Every first-sync test starts with this identical preamble; what
    /// each is actually about is what happens *after* it.
    func confirmLinkAndSettle(
        _ store: TestStore<GitHubSyncFeature.Action, GitHubSyncFeature.State, GitHubSyncFeature.Environment>
    ) async {
        let settings = settings
        store.dispatch(.confirmLink) { state in
            state.isLinking = true
            state.linkError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.linked) { _, state in
            state.settings = settings
            state.isLinking = false
            state.path = []
            state.linkRepoInput = ""
            state.linkBranchInput = ""
            state.linkTokenInput = ""
        }

        await store.runEffects()
    }
}
