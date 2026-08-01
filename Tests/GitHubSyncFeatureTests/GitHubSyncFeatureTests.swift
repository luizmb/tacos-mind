import AppDomain
import Foundation
import ReactiveConcurrency
import SwiftRex
import SwiftRexTesting
import Testing

@testable import GitHubSyncFeature

@Suite("GitHubSyncFeature")
@MainActor
struct GitHubSyncFeatureTests {
    private let settings = GitHubSettings(repoURL: "https://github.com/luizmb/ios.lu", branch: "feature/x", token: "tok")

    private func makeStore(
        initial: GitHubSyncFeature.State = .init(),
        loadGitHubSettings: @escaping @Sendable () -> Publisher<GitHubSettings?, Never> = { .just(nil) },
        linkRepository: @escaping @Sendable (GitHubSettings) -> Publisher<Void, GitHubError> = { _ in .just(()) },
        updateBranch: @escaping @Sendable (String) -> Publisher<Void, GitHubError> = { _ in .just(()) },
        unlinkRepository: @escaping @Sendable () -> Publisher<Void, GitHubError> = { .just(()) },
        isArticlesDirEmpty: @escaping @Sendable () -> Publisher<Bool, Never> = { .just(true) },
        previewPull: @escaping @Sendable (GitHubSettings) -> Publisher<PullPreview, GitHubError> = { _ in
            .just(PullPreview(toAdd: [], toUpdate: [], localOnlyChanges: []))
        },
        applyPull: @escaping @Sendable (PullPreview) -> Publisher<Int, GitHubError> = { _ in .just(0) },
        commitLocalChanges: @escaping @Sendable (GitHubSettings) -> Publisher<CommitOutcome, GitHubError> = { _ in
            .just(.nothingToCommit)
        },
        openPullRequest: @escaping @Sendable (GitHubSettings) -> Publisher<URL, GitHubError> = { _ in
            .just(URL(string: "https://github.com/luizmb/ios.lu/pull/1")!)
        }
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
                commitLocalChanges: commitLocalChanges,
                openPullRequest: openPullRequest
            )
        )
    }

    private func configured() -> GitHubSyncFeature.State {
        var state = GitHubSyncFeature.State()
        state.settings = settings
        return state
    }

    @Test("pull with no local conflicts applies immediately")
    func pullNoConflictsAppliesImmediately() async throws {
        let preview = PullPreview(
            toAdd: [PullPreview.FileChange(name: "new.json", content: Data("new".utf8))],
            toUpdate: [],
            localOnlyChanges: []
        )
        let store = makeStore(
            initial: configured(),
            previewPull: { _ in .just(preview) },
            applyPull: { _ in .just(1) }
        )

        store.dispatch(.pull) { state in
            state.isPulling = true
            state.lastError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.pullPreviewed) { result, state in
            guard case .success(let received) = result else {
                Issue.record("expected a successful preview")
                return
            }
            #expect(received == preview)
            state.pendingPullPreview = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.pullApplied) { _, state in
            state.isPulling = false
        }
    }

    @Test("pull with local conflicts waits for confirmation")
    func pullWithConflictsGates() async throws {
        let preview = PullPreview(
            toAdd: [],
            toUpdate: [PullPreview.FileChange(name: "changed.json", content: Data("remote".utf8))],
            localOnlyChanges: ["changed.json"]
        )
        let store = makeStore(initial: configured(), previewPull: { _ in .just(preview) })

        store.dispatch(.pull) { state in
            state.isPulling = true
            state.lastError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.pullPreviewed) { _, state in
            state.isPulling = false
            state.pendingPullPreview = preview
        }
        // No further runEffects()/receive — applyPull must NOT have fired; TestStore's
        // exhaustive end-of-test check would fail here if it had.
    }

    @Test("confirmPull applies the already-downloaded preview without re-fetching")
    func confirmPullApplies() async throws {
        let preview = PullPreview(
            toAdd: [],
            toUpdate: [PullPreview.FileChange(name: "changed.json", content: Data("remote".utf8))],
            localOnlyChanges: ["changed.json"]
        )
        var initial = configured()
        initial.pendingPullPreview = preview

        let store = makeStore(initial: initial, applyPull: { _ in .just(1) })

        store.dispatch(.confirmPull) { $0.pendingPullPreview = nil }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.pullApplied) { _, state in state.isPulling = false }
    }

    @Test("cancelPull drops the pending preview without applying anything")
    func cancelPullDropsPreview() async throws {
        var initial = configured()
        initial.pendingPullPreview = PullPreview(toAdd: [], toUpdate: [], localOnlyChanges: ["x.json"])
        let store = makeStore(initial: initial)

        store.dispatch(.cancelPull) { state in
            state.pendingPullPreview = nil
            state.isPulling = false
        }
    }

    @Test("commit with nothing to commit reports .nothingToCommit")
    func commitNothingToCommit() async throws {
        let store = makeStore(initial: configured(), commitLocalChanges: { _ in .just(.nothingToCommit) })

        store.dispatch(.commit) { state in
            state.isCommitting = true
            state.lastError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.committed) { result, state in
            #expect(result == .success(.nothingToCommit))
            state.isCommitting = false
            state.lastCommitOutcome = .nothingToCommit
        }
    }

    @Test("commit with changes reports the committed outcome")
    func commitWithChanges() async throws {
        let commitURL = URL(string: "https://github.com/luizmb/ios.lu/commit/abc123")!
        let outcome = CommitOutcome.committed(files: ["pure-functions.json"], commitURL: commitURL)
        let store = makeStore(initial: configured(), commitLocalChanges: { _ in .just(outcome) })

        store.dispatch(.commit) { state in
            state.isCommitting = true
            state.lastError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.committed) { result, state in
            #expect(result == .success(outcome))
            state.isCommitting = false
            state.lastCommitOutcome = outcome
        }
    }

    @Test("commit/pull/openPR are no-ops when not linked yet")
    func actionsNoOpWithoutSettings() async throws {
        let store = makeStore()
        store.dispatch(.commit) { $0.lastError = GitHubError.notConfigured.readableDescription }
    }

    @Test("openPR succeeds and stores the PR URL")
    func openPRSucceeds() async throws {
        let prURL = URL(string: "https://github.com/luizmb/ios.lu/pull/42")!
        let store = makeStore(initial: configured(), openPullRequest: { _ in .just(prURL) })

        store.dispatch(.openPR) { state in
            state.isOpeningPR = true
            state.lastError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.prOpened) { result, state in
            #expect(result == .success(prURL))
            state.isOpeningPR = false
            state.lastPRURL = prURL
        }
    }

    @Test("setPresented toggles the sheet's store-backed presentation flag")
    func setPresentedTogglesFlag() async throws {
        let store = makeStore()
        store.dispatch(.setPresented(true)) { $0.isPresented = true }
        store.dispatch(.setPresented(false)) { $0.isPresented = false }
    }

    // MARK: - Link flow

    @Test("requestLink opens the modal with a blank form defaulting to branch main")
    func requestLinkOpensModal() async throws {
        let store = makeStore()
        store.dispatch(.requestLink) { state in
            state.isLinkPresented = true
            state.linkRepoInput = ""
            state.linkBranchInput = "main"
            state.linkTokenInput = ""
            state.linkError = nil
        }
    }

    @Test("cancelLink closes the modal without linking anything")
    func cancelLinkClosesModal() async throws {
        var initial = GitHubSyncFeature.State()
        initial.isLinkPresented = true
        let store = makeStore(initial: initial)
        store.dispatch(.cancelLink) { $0.isLinkPresented = false }
    }

    @Test("confirmLink with a blank field shows an error and does nothing else")
    func confirmLinkRequiresAllFields() async throws {
        var initial = GitHubSyncFeature.State()
        initial.linkRepoInput = settings.repoURL
        initial.linkBranchInput = ""
        initial.linkTokenInput = settings.token
        let store = makeStore(initial: initial)

        store.dispatch(.confirmLink) { $0.linkError = "Fill in the repo, branch, and token." }
    }

    @Test("confirmLink failure surfaces the error and leaves the modal open")
    func confirmLinkFailureKeepsModalOpen() async throws {
        var initial = GitHubSyncFeature.State()
        initial.isLinkPresented = true
        initial.linkRepoInput = settings.repoURL
        initial.linkBranchInput = settings.branch
        initial.linkTokenInput = settings.token
        let store = makeStore(initial: initial, linkRepository: { _ in .fail(.badStatus(401)) })

        store.dispatch(.confirmLink) { state in
            state.isLinking = true
            state.linkError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.linked) { result, state in
            guard case .failure(let error) = result else {
                Issue.record("expected linked(.failure)")
                return
            }
            state.isLinking = false
            state.linkError = error.readableDescription
        }
        // isLinkPresented stays true — TestStore's exhaustive check confirms nothing
        // else (like closing the modal) happened on failure.
    }

    @Test("confirmLink success on an empty Articles dir pulls remote content down")
    func confirmLinkSuccessEmptyDirPulls() async throws {
        var initial = GitHubSyncFeature.State()
        initial.isLinkPresented = true
        initial.linkRepoInput = settings.repoURL
        initial.linkBranchInput = settings.branch
        initial.linkTokenInput = settings.token

        let preview = PullPreview(
            toAdd: [PullPreview.FileChange(name: "a.json", content: Data("a".utf8))],
            toUpdate: [],
            localOnlyChanges: []
        )
        let store = makeStore(
            initial: initial,
            linkRepository: { _ in .just(()) },
            isArticlesDirEmpty: { .just(true) },
            previewPull: { _ in .just(preview) },
            applyPull: { _ in .just(1) }
        )

        store.dispatch(.confirmLink) { state in
            state.isLinking = true
            state.linkError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.linked) { _, state in
            state.settings = settings
            state.isLinking = false
            state.isLinkPresented = false
            state.linkRepoInput = ""
            state.linkBranchInput = ""
            state.linkTokenInput = ""
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.firstSyncDecided) { _, state in
            state.isPulling = true
            state.lastError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.pullPreviewed) { _, state in
            state.pendingPullPreview = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.pullApplied) { _, state in
            state.isPulling = false
        }
    }

    @Test("confirmLink success on a non-empty Articles dir pushes local content up instead")
    func confirmLinkSuccessNonEmptyDirPushes() async throws {
        var initial = GitHubSyncFeature.State()
        initial.isLinkPresented = true
        initial.linkRepoInput = settings.repoURL
        initial.linkBranchInput = settings.branch
        initial.linkTokenInput = settings.token

        let outcome = CommitOutcome.committed(files: ["local.json"], commitURL: URL(string: "https://github.com/x/y/commit/1")!)
        let store = makeStore(
            initial: initial,
            linkRepository: { _ in .just(()) },
            isArticlesDirEmpty: { .just(false) },
            commitLocalChanges: { _ in .just(outcome) }
        )

        store.dispatch(.confirmLink) { state in
            state.isLinking = true
            state.linkError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.linked) { _, state in
            state.settings = settings
            state.isLinking = false
            state.isLinkPresented = false
            state.linkRepoInput = ""
            state.linkBranchInput = ""
            state.linkTokenInput = ""
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.firstSyncDecided) { _, state in
            state.isCommitting = true
            state.lastError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.committed) { _, state in
            state.isCommitting = false
            state.lastCommitOutcome = outcome
        }
    }

    // MARK: - Unlink flow

    @Test("requestUnlink/cancelUnlink toggle the confirmation without unlinking")
    func requestAndCancelUnlink() async throws {
        let store = makeStore(initial: configured())
        store.dispatch(.requestUnlink) { $0.isConfirmingUnlink = true }
        store.dispatch(.cancelUnlink) { $0.isConfirmingUnlink = false }
    }

    @Test("confirmUnlink clears settings and any leftover sync state")
    func confirmUnlinkClearsSettings() async throws {
        var initial = configured()
        initial.isConfirmingUnlink = true
        initial.lastCommitOutcome = .nothingToCommit
        initial.lastPRURL = URL(string: "https://github.com/x/y/pull/1")!
        let store = makeStore(initial: initial, unlinkRepository: { .just(()) })

        store.dispatch(.confirmUnlink) { state in
            state.isConfirmingUnlink = false
            state.isUnlinking = true
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.unlinked) { _, state in
            state.isUnlinking = false
            state.settings = nil
            state.lastCommitOutcome = nil
            state.lastPRURL = nil
            state.pendingPullPreview = nil
        }
    }

    @Test("confirmUnlink failure surfaces the error and keeps settings linked")
    func confirmUnlinkFailureKeepsSettings() async throws {
        var initial = configured()
        initial.isConfirmingUnlink = true
        let store = makeStore(initial: initial, unlinkRepository: { .fail(.network("boom")) })

        store.dispatch(.confirmUnlink) { state in
            state.isConfirmingUnlink = false
            state.isUnlinking = true
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.unlinked) { result, state in
            guard case .failure(let error) = result else {
                Issue.record("expected unlinked(.failure)")
                return
            }
            state.isUnlinking = false
            state.lastError = error.readableDescription
        }
        // settings stays set — TestStore's exhaustive check confirms nothing else changed.
    }

    // MARK: - Edit branch flow

    @Test("requestEditBranch seeds the form with the current branch")
    func requestEditBranchSeedsForm() async throws {
        let store = makeStore(initial: configured())
        store.dispatch(.requestEditBranch) { state in
            state.isEditingBranch = true
            state.editBranchInput = settings.branch
        }
    }

    @Test("requestEditBranch is a no-op when not linked yet")
    func requestEditBranchNoOpWithoutSettings() async throws {
        let store = makeStore()
        store.dispatch(.requestEditBranch) { _ in }
    }

    @Test("confirmEditBranch updates the stored branch and closes the modal")
    func confirmEditBranchSucceeds() async throws {
        var initial = configured()
        initial.isEditingBranch = true
        initial.editBranchInput = "main"
        let store = makeStore(initial: initial, updateBranch: { _ in .just(()) })

        store.dispatch(.confirmEditBranch) { $0.isSavingBranch = true }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.branchUpdated) { _, state in
            state.isSavingBranch = false
            state.isEditingBranch = false
            state.settings?.branch = "main"
        }
    }

    @Test("confirmEditBranch failure surfaces the error and keeps the modal open")
    func confirmEditBranchFailureKeepsModalOpen() async throws {
        var initial = configured()
        initial.isEditingBranch = true
        initial.editBranchInput = "main"
        let store = makeStore(initial: initial, updateBranch: { _ in .fail(.network("boom")) })

        store.dispatch(.confirmEditBranch) { $0.isSavingBranch = true }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.branchUpdated) { result, state in
            guard case .failure(let error) = result else {
                Issue.record("expected branchUpdated(.failure)")
                return
            }
            state.isSavingBranch = false
            state.lastError = error.readableDescription
        }
    }
}
