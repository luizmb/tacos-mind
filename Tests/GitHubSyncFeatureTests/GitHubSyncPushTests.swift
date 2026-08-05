import AppDomain
import Foundation
import ReactiveConcurrency
import SwiftRex
import SwiftRexTesting
import Testing

@testable import GitHubSyncFeature

/// Everything behind the Push button: previewing what's dirty, the form that names the
/// branch/commit/PR, and confirming it.
@Suite("GitHubSyncFeature — push")
@MainActor
struct GitHubSyncPushTests: GitHubSyncTestHarness {
    @Test("push with nothing dirty reports .nothingToPush without opening the form")
    func pushNothingToPush() async throws {
        let store = makeStore(
            initial: configured(),
            previewPush: { _ in .just(PushPreview(files: [], suggestedBranch: "articles/2026-08-05-1432")) }
        )

        store.dispatch(.push) { state in
            state.isPushing = true
            state.lastPushOutcome = nil
            state.lastError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.pushPreviewed) { _, state in
            state.isPushing = false
            state.isPerformingFirstSync = false
            state.lastPushOutcome = .nothingToPush
        }
        // `path` stays empty — TestStore's exhaustive check confirms no form was pushed.
    }

    @Test("push with changes seeds every form field and pushes the form")
    func pushSeedsTheForm() async throws {
        let preview = PushPreview(
            files: [
                SyncFileChange(name: "a.json", content: Data("a".utf8)),
                SyncFileChange(name: "b.json", content: Data("b".utf8))
            ],
            suggestedBranch: "articles/2026-08-05-1432"
        )
        let store = makeStore(initial: configured(), previewPush: { _ in .just(preview) })

        store.dispatch(.push) { state in
            state.isPushing = true
            state.lastPushOutcome = nil
            state.lastError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.pushPreviewed) { _, state in
            state.isPushing = false
            state.pendingPushPreview = preview
            state.pushBranchInput = "articles/2026-08-05-1432"
            state.pushCommitMessageInput = "Update 2 articles"
            state.pushPRTitleInput = "Update 2 articles"
            state.pushPRBodyInput = "- a.json\n- b.json"
            state.path = [.push]
        }
    }

    @Test("confirmPush sends the edited form values and the previewed bytes")
    func confirmPushSendsTheRequest() async throws {
        let preview = PushPreview(
            files: [SyncFileChange(name: "a.json", content: Data("a".utf8))],
            suggestedBranch: "articles/2026-08-05-1432"
        )
        let outcome = PushOutcome.pushed(
            files: ["a.json"],
            branch: "my-branch",
            commitURL: URL(string: "https://github.com/luizmb/ios.lu/commit/abc")!,
            prURL: URL(string: "https://github.com/luizmb/ios.lu/pull/42")!
        )
        let sent = Recorder<PushRequest>()

        var initial = configured()
        initial.path = [.push]
        initial.pendingPushPreview = preview
        initial.pushBranchInput = "my-branch"
        initial.pushCommitMessageInput = "Custom message"
        initial.pushPRTitleInput = "Custom title"
        initial.pushPRBodyInput = "Custom body"

        let store = makeStore(
            initial: initial,
            performPush: { _, request, requestedPreview in
                sent.record(request)
                #expect(requestedPreview == preview)
                return .just(outcome)
            }
        )

        store.dispatch(.confirmPush) { state in
            state.isPushing = true
            state.lastError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.pushed) { result, state in
            #expect(result == .success(outcome))
            state.isPushing = false
            state.lastPushOutcome = outcome
            state.pendingPushPreview = nil
            state.path = []
        }

        #expect(
            sent.values == [
                PushRequest(
                    branch: "my-branch",
                    commitMessage: "Custom message",
                    prTitle: "Custom title",
                    prBody: "Custom body"
                )
            ]
        )
    }

    @Test("confirmPush with a blank branch name does nothing")
    func confirmPushRequiresABranchName() async throws {
        var initial = configured()
        initial.path = [.push]
        initial.pendingPushPreview = PushPreview(
            files: [SyncFileChange(name: "a.json", content: Data("a".utf8))],
            suggestedBranch: "articles/x"
        )
        initial.pushBranchInput = ""
        let store = makeStore(initial: initial)

        store.dispatch(.confirmPush) { _ in }
    }

    @Test("push failure keeps the form up with its inputs intact")
    func pushFailureKeepsTheForm() async throws {
        var initial = configured()
        initial.path = [.push]
        initial.pendingPushPreview = PushPreview(
            files: [SyncFileChange(name: "a.json", content: Data("a".utf8))],
            suggestedBranch: "articles/x"
        )
        initial.pushBranchInput = "articles/x"

        let store = makeStore(initial: initial, performPush: { _, _, _ in .fail(.badStatus(422)) })

        store.dispatch(.confirmPush) { state in
            state.isPushing = true
            state.lastError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.pushed) { _, state in
            state.isPushing = false
            state.isPerformingFirstSync = false
            state.lastError = GitHubError.badStatus(422).readableDescription
        }
        // `path`, `pendingPushPreview` and every input survive — retrying is one edit away.
    }

    @Test("cancelPush drops the form and the pending preview")
    func cancelPushDropsTheForm() async throws {
        var initial = configured()
        initial.path = [.push]
        initial.isPerformingFirstSync = true
        initial.pendingPushPreview = PushPreview(files: [], suggestedBranch: "articles/x")
        let store = makeStore(initial: initial)

        store.dispatch(.cancelPush) { state in
            state.path = []
            state.pendingPushPreview = nil
            state.isPushing = false
            state.isPerformingFirstSync = false
        }
    }

    @Test("pull/push are no-ops when not linked yet")
    func actionsNoOpWithoutSettings() async throws {
        let store = makeStore()
        store.dispatch(.push) { $0.lastError = GitHubError.notConfigured.readableDescription }
        store.dispatch(.pull) { $0.lastError = GitHubError.notConfigured.readableDescription }
    }
}
