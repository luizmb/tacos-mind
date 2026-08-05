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
            baseBranch: viewStore.state.baseBranch,
            isPulling: viewStore.state.isPulling,
            lastPullOutcome: viewStore.state.lastPullOutcome,
            canOverwriteKeptLocal: viewStore.state.canOverwriteKeptLocal,
            isPushing: viewStore.state.isPushing,
            lastPushOutcome: viewStore.state.lastPushOutcome,
            lastError: viewStore.state.lastError,
            // A plain `Bool`, so `.binding` — never `.presence`, which silently promotes a
            // `Bool` to `Bool?` and makes the getter `Optional(false) != nil`, i.e.
            // permanently true. Same shape as `isConfirmingUnlink` below.
            isConfirmingOverwrite: viewStore.binding(
                .state(\.isConfirmingOverwrite),
                dispatch: .action(review: { _ in .cancelOverwriteKeptLocal })
            ),
            onDone: { dispatch(.requestClose) },
            onRequestLink: { dispatch(.requestLink) },
            onRequestUnlink: { dispatch(.requestUnlink) },
            onRequestEditBranch: { dispatch(.requestEditBranch) },
            onPull: { dispatch(.pull) },
            onRequestOverwriteKeptLocal: { dispatch(.requestOverwriteKeptLocal) },
            onConfirmOverwriteKeptLocal: { dispatch(.overwriteKeptLocal) },
            onPush: { dispatch(.push) },
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
            ),
            pushScreen: PushContent(
                branchInput: viewStore.binding(.state(\.pushBranchInput), dispatch: .action(\.setPushBranchInput)),
                commitMessageInput: viewStore.binding(
                    .state(\.pushCommitMessageInput),
                    dispatch: .action(\.setPushCommitMessageInput)
                ),
                prTitleInput: viewStore.binding(.state(\.pushPRTitleInput), dispatch: .action(\.setPushPRTitleInput)),
                prBodyInput: viewStore.binding(.state(\.pushPRBodyInput), dispatch: .action(\.setPushPRBodyInput)),
                fileCount: viewStore.state.pushFileCount,
                baseBranch: viewStore.state.baseBranch,
                isPushing: viewStore.state.isPushing,
                onCancel: { dispatch(.cancelPush) },
                onConfirm: { dispatch(.confirmPush) }
            )
        )
        .onAppear { dispatch(.loadSettings) }
    }
}
