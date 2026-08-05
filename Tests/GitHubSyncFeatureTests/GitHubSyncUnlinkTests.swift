import AppDomain
import Foundation
import ReactiveConcurrency
import SwiftRex
import SwiftRexTesting
import Testing

@testable import GitHubSyncFeature

/// Unlinking a repo, and changing the base branch on one that stays linked — the two
/// mutations allowed after the one-time link.
@Suite("GitHubSyncFeature — unlink & base branch")
@MainActor
struct GitHubSyncUnlinkTests: GitHubSyncTestHarness {
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
        initial.lastPushOutcome = .nothingToPush
        initial.lastPullOutcome = PullOutcome(applied: 2, keptLocal: ["x.json"])
        initial.overwritablePull = PullPreview(toAdd: [], toUpdate: [])
        initial.isConfirmingOverwrite = true
        let store = makeStore(initial: initial, unlinkRepository: { .just(()) })

        store.dispatch(.confirmUnlink) { state in
            state.isConfirmingUnlink = false
            state.isUnlinking = true
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.unlinked) { _, state in
            state.isUnlinking = false
            state.settings = nil
            state.lastPullOutcome = nil
            state.overwritablePull = nil
            state.isConfirmingOverwrite = false
            state.lastPushOutcome = nil
            state.pendingPushPreview = nil
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
            state.path = [.editBranch]
            state.editBranchInput = settings.baseBranch
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
        initial.path = [.editBranch]
        initial.editBranchInput = "main"
        let store = makeStore(initial: initial, updateBranch: { _ in .just(()) })

        store.dispatch(.confirmEditBranch) { $0.isSavingBranch = true }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.branchUpdated) { _, state in
            state.isSavingBranch = false
            state.path = []
            state.settings?.baseBranch = "main"
        }
    }

    @Test("confirmEditBranch failure surfaces the error and keeps the modal open")
    func confirmEditBranchFailureKeepsModalOpen() async throws {
        var initial = configured()
        initial.path = [.editBranch]
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
