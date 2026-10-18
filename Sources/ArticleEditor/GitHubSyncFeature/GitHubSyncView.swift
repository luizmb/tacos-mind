import AppDomain
import SwiftRexArchitecture
import SwiftUI

@BoundTo(GitHubSyncFeature.self)
public struct GitHubSyncView: View {
    public var body: some View {
        // `dispatch(_:file:function:line:)` has magic-literal defaults, so it can't be
        // bare-referenced — see ArticleEditorView for the same unavoidable closure.
        let dispatch: (GitHubSyncFeature.ViewAction) -> Void = { viewStore.dispatch($0) }
        GitHubSyncContent(
            path: viewStore.binding(.state(\.path).action(\.setPath)),
            isConfigured: viewStore.state.isConfigured,
            repoURL: viewStore.state.repoURL,
            baseBranch: viewStore.state.baseBranch,
            isPulling: viewStore.state.isPulling,
            lastPullOutcome: viewStore.state.lastPullOutcome.value,
            canOverwriteKeptLocal: viewStore.state.canOverwriteKeptLocal,
            isPushing: viewStore.state.isPushing,
            lastPushOutcome: viewStore.state.lastPushOutcome.value,
            lastError: viewStore.state.lastError,
            // A plain `Bool`, so `.binding` — never `.presence`, which silently promotes a
            // `Bool` to `Bool?` and makes the getter `Optional(false) != nil`, i.e.
            // permanently true. Same shape as `isConfirmingUnlink` below.
            isConfirmingOverwrite: viewStore.binding(.state(\.isConfirmingOverwrite).action(review: { _ in .cancelOverwriteKeptLocal })),
            onDone: { dispatch(.requestClose) },
            onRequestLink: { dispatch(.requestLink) },
            onRequestUnlink: { dispatch(.requestUnlink) },
            onRequestEditBranch: { dispatch(.requestEditBranch) },
            onPull: { dispatch(.pull) },
            onRequestOverwriteKeptLocal: { dispatch(.requestOverwriteKeptLocal) },
            onConfirmOverwriteKeptLocal: { dispatch(.overwriteKeptLocal) },
            onPush: { dispatch(.push) },
            isConfirmingUnlink: viewStore.binding(.state(\.isConfirmingUnlink).action(review: { _ in .cancelUnlink })),
            isUnlinking: viewStore.state.isUnlinking,
            onConfirmUnlink: { dispatch(.confirmUnlink) },
            linkScreen: LinkRepositoryContent(
                repoInput: viewStore.binding(.state(\.linkRepoInput).action(\.setLinkRepoInput)),
                branchInput: viewStore.binding(.state(\.linkBranchInput).action(\.setLinkBranchInput)),
                tokenInput: viewStore.binding(.state(\.linkTokenInput).action(\.setLinkTokenInput)),
                isLinking: viewStore.state.isLinking,
                error: viewStore.state.linkError,
                onCancel: { dispatch(.cancelLink) },
                onConfirm: { dispatch(.confirmLink) }
            ),
            editBranchScreen: EditBranchContent(
                branchInput: viewStore.binding(.state(\.editBranchInput).action(\.setEditBranchInput)),
                isSaving: viewStore.state.isSavingBranch,
                onCancel: { dispatch(.cancelEditBranch) },
                onConfirm: { dispatch(.confirmEditBranch) }
            ),
            pushScreen: PushContent(
                branchInput: viewStore.binding(.state(\.pushBranchInput).action(\.setPushBranchInput)),
                commitMessageInput: viewStore.binding(.state(\.pushCommitMessageInput).action(\.setPushCommitMessageInput)),
                prTitleInput: viewStore.binding(.state(\.pushPRTitleInput).action(\.setPushPRTitleInput)),
                prBodyInput: viewStore.binding(.state(\.pushPRBodyInput).action(\.setPushPRBodyInput)),
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
