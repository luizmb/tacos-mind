import AppDomain
import Foundation
import ReactiveConcurrency
import SwiftRex
import SwiftRexTesting
import Testing

@testable import GitHubSyncFeature

/// The one-time link flow, including what a freshly-linked repo does for its first sync —
/// pull when there's nothing local to lose, the pre-filled push form when there is.
@Suite("GitHubSyncFeature — link")
@MainActor
struct GitHubSyncLinkTests: GitHubSyncTestHarness {
    @Test("requestLink opens the modal with a blank form defaulting to branch main")
    func requestLinkOpensModal() async throws {
        let store = makeStore()
        store.dispatch(.requestLink) { state in
            state.path = [.link]
            state.linkRepoInput = ""
            state.linkBranchInput = "main"
            state.linkTokenInput = ""
            state.linkError = nil
        }
    }

    @Test("cancelLink closes the modal without linking anything")
    func cancelLinkClosesModal() async throws {
        var initial = GitHubSyncFeature.State()
        initial.path = [.link]
        let store = makeStore(initial: initial)
        store.dispatch(.cancelLink) { $0.path = [] }
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
        initial.path = [.link]
        initial.linkRepoInput = settings.repoURL
        initial.linkBranchInput = settings.baseBranch
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
        // `path` stays `[.link]` — TestStore's exhaustive check confirms nothing else
        // (like popping the form out from under the user) happened on failure.
    }

    @Test("confirmLink success on an empty Articles dir pulls remote content down")
    func confirmLinkSuccessEmptyDirPulls() async throws {
        let preview = PullPreview(
            toAdd: [SyncFileChange(name: "a.json", content: Data("a".utf8))],
            toUpdate: []
        )
        let store = makeStore(
            initial: linkFormState(),
            linkRepository: { _ in .just(()) },
            isArticlesDirEmpty: { .just(true) },
            previewPull: { _ in .just(preview) },
            applyPull: { _ in .just(1) }
        )

        await confirmLinkAndSettle(store)

        store.receive(GitHubSyncFeature.Action.prism.firstSyncDecided) { _, state in
            state.isPulling = true
            state.isPerformingFirstSync = true
            state.lastError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.pullPreviewed) { _, state in
            state.overwritablePull = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.pullApplied) { _, state in
            state.isPulling = false
            state.lastPullOutcome = PullOutcome(applied: 1, keptLocal: [])
            state.isPerformingFirstSync = false
        }

        // The sheet does not close itself — it says the first sync is done and the app
        // dismisses it, because the app is what owns this sheet's presentation.
        await store.runEffects()
        store.receive(GitHubSyncFeature.Action.prism.firstSyncCompleted) { _ in }
    }

    /// A non-empty local `Articles/` no longer commits itself on link — it stops at the
    /// pre-filled push form, because a first link shouldn't open a pull request the user
    /// has never seen. `isPerformingFirstSync` stays true across the form so confirming it
    /// still auto-closes the sheet.
    @Test("confirmLink success on a non-empty Articles dir opens the push form pre-filled")
    func confirmLinkSuccessNonEmptyDirOpensPushForm() async throws {
        let preview = PushPreview(
            files: [SyncFileChange(name: "local.json", content: Data("local".utf8))],
            suggestedBranch: "articles/2026-08-05-1432"
        )
        let outcome = PushOutcome.pushed(
            files: ["local.json"],
            branch: "articles/2026-08-05-1432",
            commitURL: URL(string: "https://github.com/x/y/commit/1")!,
            prURL: URL(string: "https://github.com/x/y/pull/1")!
        )
        let store = makeStore(
            initial: linkFormState(),
            linkRepository: { _ in .just(()) },
            isArticlesDirEmpty: { .just(false) },
            previewPush: { _ in .just(preview) },
            performPush: { _, _, _ in .just(outcome) }
        )

        await confirmLinkAndSettle(store)

        store.receive(GitHubSyncFeature.Action.prism.firstSyncDecided) { _, state in
            state.isPushing = true
            state.isPerformingFirstSync = true
            state.lastError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.pushPreviewed) { _, state in
            state.isPushing = false
            state.pendingPushPreview = preview
            state.pushBranchInput = "articles/2026-08-05-1432"
            state.pushCommitMessageInput = "Update 1 article"
            state.pushPRTitleInput = "Update 1 article"
            state.pushPRBodyInput = "- local.json"
            state.path = [.push]
        }

        // Nothing has been pushed yet — the sheet is waiting on the user, and does not
        // close itself until they confirm.
        store.dispatch(.confirmPush) { state in
            state.isPushing = true
            state.lastError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.pushed) { _, state in
            state.isPushing = false
            state.lastPushOutcome = outcome
            state.pendingPushPreview = nil
            state.path = []
            state.isPerformingFirstSync = false
        }

        await store.runEffects()
        store.receive(GitHubSyncFeature.Action.prism.firstSyncCompleted) { _ in }
    }
}
