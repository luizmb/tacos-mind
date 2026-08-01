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
            repoURL: viewStore.state.repoURL,
            branch: viewStore.state.branch,
            isPulling: viewStore.state.isPulling,
            pendingPullPreview: viewStore.state.pendingPullPreview,
            isCommitting: viewStore.state.isCommitting,
            lastCommitOutcome: viewStore.state.lastCommitOutcome,
            isOpeningPR: viewStore.state.isOpeningPR,
            lastPRURL: viewStore.state.lastPRURL,
            lastError: viewStore.state.lastError,
            isConfirmingPull: viewStore.presence(.state(\.pendingPullPreview), dismiss: .cancelPull),
            onRequestLink: { dispatch(.requestLink) },
            onRequestUnlink: { dispatch(.requestUnlink) },
            onRequestEditBranch: { dispatch(.requestEditBranch) },
            onPull: { dispatch(.pull) },
            onConfirmPull: { dispatch(.confirmPull) },
            onCommit: { dispatch(.commit) },
            onOpenPR: { dispatch(.openPR) },
            isConfirmingUnlink: viewStore.presence(.state(\.isConfirmingUnlink), dismiss: .cancelUnlink),
            isUnlinking: viewStore.state.isUnlinking,
            onConfirmUnlink: { dispatch(.confirmUnlink) },
            linkSheet: LinkRepositoryContent(
                repoInput: viewStore.binding(.state(\.linkRepoInput), dispatch: .action(\.setLinkRepoInput)),
                branchInput: viewStore.binding(.state(\.linkBranchInput), dispatch: .action(\.setLinkBranchInput)),
                tokenInput: viewStore.binding(.state(\.linkTokenInput), dispatch: .action(\.setLinkTokenInput)),
                isLinking: viewStore.state.isLinking,
                error: viewStore.state.linkError,
                onCancel: { dispatch(.cancelLink) },
                onConfirm: { dispatch(.confirmLink) }
            ),
            isLinkPresented: viewStore.presence(.state(\.isLinkPresented), dismiss: .cancelLink),
            editBranchSheet: EditBranchContent(
                branchInput: viewStore.binding(.state(\.editBranchInput), dispatch: .action(\.setEditBranchInput)),
                isSaving: viewStore.state.isSavingBranch,
                onCancel: { dispatch(.cancelEditBranch) },
                onConfirm: { dispatch(.confirmEditBranch) }
            ),
            isEditingBranch: viewStore.presence(.state(\.isEditingBranch), dismiss: .cancelEditBranch)
        )
        .onAppear { dispatch(.loadSettings) }
    }
}
