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
            path: viewStore.binding(.state(\.path), dispatch: .action(\.setPath)),
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
            // A genuine `Optional` — `.presence` is correct here, and `pendingPullPreview`
            // is the *only* field in this feature it was ever correct for. The three
            // sibling calls that used to sit alongside it were reading plain `Bool`s,
            // which `.presence` silently promotes to `Bool?`, making the getter
            // `Optional(false) != nil` — permanently true. Those flags are gone: two are
            // pushed routes now, and the third uses `.binding`.
            isConfirmingPull: viewStore.presence(.state(\.pendingPullPreview), dismiss: .cancelPull),
            onDone: { dispatch(.requestClose) },
            onRequestLink: { dispatch(.requestLink) },
            onRequestUnlink: { dispatch(.requestUnlink) },
            onRequestEditBranch: { dispatch(.requestEditBranch) },
            onPull: { dispatch(.pull) },
            onConfirmPull: { dispatch(.confirmPull) },
            onCommit: { dispatch(.commit) },
            onOpenPR: { dispatch(.openPR) },
            isConfirmingUnlink: viewStore.binding(
                .state(\.isConfirmingUnlink),
                dispatch: .action(review: { _ in .cancelUnlink })
            ),
            isUnlinking: viewStore.state.isUnlinking,
            onConfirmUnlink: { dispatch(.confirmUnlink) },
            linkScreen: LinkRepositoryContent(
                repoInput: viewStore.binding(.state(\.linkRepoInput), dispatch: .action(\.setLinkRepoInput)),
                branchInput: viewStore.binding(.state(\.linkBranchInput), dispatch: .action(\.setLinkBranchInput)),
                tokenInput: viewStore.binding(.state(\.linkTokenInput), dispatch: .action(\.setLinkTokenInput)),
                isLinking: viewStore.state.isLinking,
                error: viewStore.state.linkError,
                onCancel: { dispatch(.cancelLink) },
                onConfirm: { dispatch(.confirmLink) }
            ),
            editBranchScreen: EditBranchContent(
                branchInput: viewStore.binding(.state(\.editBranchInput), dispatch: .action(\.setEditBranchInput)),
                isSaving: viewStore.state.isSavingBranch,
                onCancel: { dispatch(.cancelEditBranch) },
                onConfirm: { dispatch(.confirmEditBranch) }
            )
        )
        .onAppear { dispatch(.loadSettings) }
    }
}
