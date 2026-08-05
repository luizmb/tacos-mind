import AppDomain
import Foundation
import ReactiveConcurrency
import SwiftRex
import SwiftRexTesting
import Testing

@testable import GitHubSyncFeature

/// Everything behind the Pull button, including the local-wins rule and the explicit
/// discard that undoes it.
@Suite("GitHubSyncFeature — pull")
@MainActor
struct GitHubSyncPullTests: GitHubSyncTestHarness {
    @Test("pull applies remote-only additions with no confirmation")
    func pullAppliesAdditionsImmediately() async throws {
        let preview = PullPreview(
            toAdd: [SyncFileChange(name: "new.json", content: Data("new".utf8))],
            toUpdate: []
        )
        let store = makeStore(
            initial: configured(),
            previewPull: { _ in .just(preview) },
            applyPull: { _ in .just(1) }
        )

        store.dispatch(.pull) { state in
            state.isPulling = true
            state.lastPullOutcome = nil
            state.overwritablePull = nil
            state.isConfirmingOverwrite = false
            state.lastError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.pullPreviewed) { result, state in
            guard case .success(let received) = result else {
                Issue.record("expected a successful preview")
                return
            }
            #expect(received == preview)
            // Nothing was held back, so no discard option is armed.
            state.overwritablePull = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.pullApplied) { _, state in
            state.isPulling = false
            state.lastPullOutcome = PullOutcome(applied: 1, keptLocal: [])
        }
    }

    /// The heart of the local-wins rule: a file that differs locally is *not* written, the
    /// pull still completes, and the remote bytes are retained for an explicit discard.
    @Test("pull keeps locally-modified files and applies only the rest")
    func pullKeepsLocalChanges() async throws {
        let remote = SyncFileChange(name: "changed.json", content: Data("remote".utf8))
        let preview = PullPreview(
            toAdd: [SyncFileChange(name: "new.json", content: Data("new".utf8))],
            toUpdate: [remote]
        )
        let applied = Recorder<PullPreview>()
        let store = makeStore(
            initial: configured(),
            previewPull: { _ in .just(preview) },
            applyPull: { requested in
                applied.record(requested)
                return .just(1)
            }
        )

        store.dispatch(.pull) { state in
            state.isPulling = true
            state.lastPullOutcome = nil
            state.overwritablePull = nil
            state.isConfirmingOverwrite = false
            state.lastError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.pullPreviewed) { _, state in
            state.overwritablePull = preview
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.pullApplied) { _, state in
            state.isPulling = false
            state.lastPullOutcome = PullOutcome(applied: 1, keptLocal: ["changed.json"])
        }

        // What actually reached the disk: the addition only, with `toUpdate` stripped.
        #expect(applied.values == [PullPreview(toAdd: preview.toAdd, toUpdate: [])])
    }

    @Test("requestOverwriteKeptLocal is a no-op when nothing was kept local")
    func requestOverwriteWithoutKeptFilesDoesNothing() async throws {
        let store = makeStore(initial: configured())
        store.dispatch(.requestOverwriteKeptLocal) { _ in }
    }

    @Test("requestOverwriteKeptLocal/cancel toggle the confirmation without writing")
    func requestAndCancelOverwrite() async throws {
        var initial = configured()
        initial.overwritablePull = PullPreview(
            toAdd: [],
            toUpdate: [SyncFileChange(name: "changed.json", content: Data("remote".utf8))]
        )
        let store = makeStore(initial: initial)

        store.dispatch(.requestOverwriteKeptLocal) { $0.isConfirmingOverwrite = true }
        store.dispatch(.cancelOverwriteKeptLocal) { $0.isConfirmingOverwrite = false }
    }

    @Test("overwriteKeptLocal re-applies the retained bytes without re-fetching")
    func overwriteKeptLocalApplies() async throws {
        let preview = PullPreview(
            toAdd: [],
            toUpdate: [SyncFileChange(name: "changed.json", content: Data("remote".utf8))]
        )
        var initial = configured()
        initial.overwritablePull = preview
        initial.isConfirmingOverwrite = true
        initial.lastPullOutcome = PullOutcome(applied: 0, keptLocal: ["changed.json"])

        let applied = Recorder<PullPreview>()
        let previewed = Recorder<Void>()
        let store = makeStore(
            initial: initial,
            previewPull: { _ in
                previewed.record(())
                return .just(PullPreview(toAdd: [], toUpdate: []))
            },
            applyPull: { requested in
                applied.record(requested)
                return .just(1)
            }
        )

        store.dispatch(.overwriteKeptLocal) { state in
            state.isPulling = true
            state.isConfirmingOverwrite = false
            state.overwritablePull = nil
            state.lastError = nil
        }

        await store.runEffects()

        store.receive(GitHubSyncFeature.Action.prism.pullApplied) { _, state in
            state.isPulling = false
            state.lastPullOutcome = PullOutcome(applied: 1, keptLocal: [])
        }

        // The full preview — `toUpdate` included this time — and no second network trip.
        #expect(applied.values == [preview])
        #expect(previewed.values.isEmpty)
    }
}
