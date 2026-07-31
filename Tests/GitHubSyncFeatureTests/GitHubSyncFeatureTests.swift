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
        saveGitHubSettings: @escaping @Sendable (GitHubSettings) -> Publisher<Void, GitHubError> = { _ in .just(()) },
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
                saveGitHubSettings: saveGitHubSettings,
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

    @Test("commit/pull/openPR are no-ops when not configured yet")
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

    @Test("saveSettings persists the form fields and updates settings on success")
    func saveSettingsSucceeds() async throws {
        let store = makeStore(saveGitHubSettings: { _ in .just(()) })

        store.dispatch(.setRepoURLInput(settings.repoURL)) { $0.repoURLInput = settings.repoURL }
        store.dispatch(.setBranchInput(settings.branch)) { $0.branchInput = settings.branch }
        store.dispatch(.setTokenInput(settings.token)) { $0.tokenInput = settings.token }
        store.dispatch(.saveSettings) { state in
            state.isSavingSettings = true
            state.lastError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.settingsSaved) { result, state in
            guard case .success = result else {
                Issue.record("expected settingsSaved(.success)")
                return
            }
            state.isSavingSettings = false
            state.settings = settings
            // The token field is cleared after a successful save — it's a secret, never
            // left sitting in a visible field once it's safely stored.
            state.tokenInput = ""
        }
    }

    /// Test-only spy — exercised serially within a single `@MainActor` test function, so
    /// the lack of real synchronization is safe despite `@unchecked Sendable`.
    private final class SettingsRecorder: @unchecked Sendable {
        private(set) var saved: [GitHubSettings] = []
        func record(_ settings: GitHubSettings) { saved.append(settings) }
    }

    @Test("saving with a blank token keeps the previously-stored token, doesn't erase it")
    func saveSettingsWithBlankTokenKeepsExistingToken() async throws {
        let recorder = SettingsRecorder()
        let store = makeStore(saveGitHubSettings: { settings in
            recorder.record(settings)
            return .just(())
        })

        store.dispatch(.setRepoURLInput(settings.repoURL)) { $0.repoURLInput = settings.repoURL }
        store.dispatch(.setBranchInput(settings.branch)) { $0.branchInput = settings.branch }
        store.dispatch(.setTokenInput(settings.token)) { $0.tokenInput = settings.token }
        store.dispatch(.saveSettings) { state in
            state.isSavingSettings = true
            state.lastError = nil
        }
        await store.runEffects()
        store.receive(GitHubSyncFeature.Action.prism.settingsSaved) { _, state in
            state.isSavingSettings = false
            state.settings = settings
            state.tokenInput = ""
        }

        // Editing just the branch and saving again, with the token field left blank,
        // must reuse the already-stored token rather than overwriting it with "".
        let updatedBranch = "\(settings.branch)-updated"
        store.dispatch(.setBranchInput(updatedBranch)) { $0.branchInput = updatedBranch }
        store.dispatch(.saveSettings) { state in
            state.isSavingSettings = true
            state.lastError = nil
        }
        await store.runEffects()
        store.receive(GitHubSyncFeature.Action.prism.settingsSaved) { _, state in
            state.isSavingSettings = false
            state.settings = GitHubSettings(repoURL: settings.repoURL, branch: updatedBranch, token: settings.token)
        }

        #expect(recorder.saved.last?.token == settings.token)
        #expect(recorder.saved.last?.branch == updatedBranch)
    }

    @Test("setPresented toggles the sheet's store-backed presentation flag")
    func setPresentedTogglesFlag() async throws {
        let store = makeStore()
        store.dispatch(.setPresented(true)) { $0.isPresented = true }
        store.dispatch(.setPresented(false)) { $0.isPresented = false }
    }
}
