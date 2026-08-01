import AppDomain
import SwiftRexArchitecture
import SwiftUI

@BoundTo(GitHubSyncFeature.self, strategy: .observationSimple)
public struct GitHubSyncView: View {
    public var body: some View {
        // `dispatch(_:file:function:line:)` has magic-literal defaults, so it can't be
        // bare-referenced — see ArticleEditorView for the same unavoidable closure.
        let dispatch: (GitHubSyncFeature.ViewAction) -> Void = { viewStore.dispatch($0) }
        GitHubSyncContent(
            isConfigured: viewStore.state.isConfigured,
            repoURLInput: viewStore.binding(.state(\.repoURLInput), dispatch: .action(\.setRepoURLInput)),
            branchInput: viewStore.binding(.state(\.branchInput), dispatch: .action(\.setBranchInput)),
            tokenInput: viewStore.binding(.state(\.tokenInput), dispatch: .action(\.setTokenInput)),
            isSavingSettings: viewStore.state.isSavingSettings,
            isPulling: viewStore.state.isPulling,
            pendingPullPreview: viewStore.state.pendingPullPreview,
            isCommitting: viewStore.state.isCommitting,
            lastCommitOutcome: viewStore.state.lastCommitOutcome,
            isOpeningPR: viewStore.state.isOpeningPR,
            lastPRURL: viewStore.state.lastPRURL,
            lastError: viewStore.state.lastError,
            isConfirmingPull: viewStore.presence(.state(\.pendingPullPreview), dismiss: .cancelPull),
            onSaveSettings: { dispatch(.saveSettings) },
            onPull: { dispatch(.pull) },
            onConfirmPull: { dispatch(.confirmPull) },
            onCommit: { dispatch(.commit) },
            onOpenPR: { dispatch(.openPR) }
        )
        .onAppear { dispatch(.loadSettings) }
    }
}
