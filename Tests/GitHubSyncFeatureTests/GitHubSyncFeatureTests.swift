import AppDomain
import Foundation
import ReactiveConcurrency
import SwiftRex
import SwiftRexTesting
import Testing

@testable import GitHubSyncFeature

/// Navigation inside the sheet. The flows themselves live in the sibling suites.
@Suite("GitHubSyncFeature — navigation")
@MainActor
struct GitHubSyncFeatureTests: GitHubSyncTestHarness {
    /// The back button and back-swipe inside the sheet arrive as `setPath`, the same
    /// action a programmatic push uses, so there is only one writer either way.
    @Test("setPath is what an interactive pop delivers")
    func setPathAcceptsAnInteractivePop() async throws {
        var initial = GitHubSyncFeature.State()
        initial.path = [.link]
        let store = makeStore(initial: initial)
        store.dispatch(.setPath([])) { $0.path = [] }
    }

    /// Whether the *sheet* is up is not this feature's business — `AppFeature` owns that
    /// presentation, so asking to close is a pure trigger with no local effect.
    @Test("requestClose is a pure trigger — no local state change, no effect")
    func requestCloseIsAPureTrigger() async throws {
        let store = makeStore()
        store.dispatch(.requestClose) { _ in }
        await store.runEffects()
        #expect(store.receivedActions.isEmpty)
    }
}
