import AppDomain
import SwiftRexArchitecture
import SwiftUI

@BoundTo(ArticleEditorFeature.self, strategy: .observationSimple)
public struct ArticleEditorView: View {
    public var body: some View {
        // `dispatch(_:file:function:line:)` has magic-literal defaults (`#file`/`#line`),
        // which Swift can only resolve via a literal call — there's no way to reference it
        // as a bare function value. This is the one unavoidable closure boundary; every
        // `onXxx` below is a thin, direct call off of it.
        let dispatch: (ArticleEditorFeature.ViewAction) -> Void = { viewStore.dispatch($0) }
        ArticleEditorContent(
            isDocumentOpen: viewStore.state.isDocumentOpen,
            title: viewStore.binding(.state(\.title), dispatch: .action(\.setTitle)),
            slug: viewStore.binding(.state(\.slug), dispatch: .action(\.setSlug)),
            author: viewStore.binding(.state(\.author), dispatch: .action(\.setAuthor)),
            emphasis: viewStore.binding(.state(\.emphasis), dispatch: .action(\.setEmphasis)),
            draft: viewStore.binding(.state(\.draft), dispatch: .action(\.setDraft)),
            number: viewStore.binding(.state(\.number), dispatch: .action(\.setNumber)),
            published: viewStore.binding(.state(\.published), dispatch: .action(\.setPublished)),
            tags: viewStore.state.tags,
            allTags: viewStore.state.allTags,
            brainstorming: viewStore.binding(.state(\.brainstorming), dispatch: .action(\.setBrainstorming)),
            blocks: viewStore.state.blocks,
            allBlockKinds: viewStore.state.allBlockKinds,
            allSummaries: viewStore.state.allSummaries,
            hasUnsavedChanges: viewStore.state.hasUnsavedChanges,
            // `.presence` only has overloads for `Optional<T>`/`Presentation<T>` state — for
            // a plain `Bool` like this, Swift still type-checks it via an implicit optional
            // promotion, but the resulting getter becomes "is this now-wrapped Bool non-nil,"
            // which is always true. `.binding` is the correct primitive for a plain Bool;
            // the toolbar's `onRequestRevert` sets it true directly, so this dispatch only
            // ever needs to handle the dismiss (false) case SwiftUI drives.
            isConfirmingRevert: viewStore.binding(
                .state(\.isConfirmingRevert),
                dispatch: .action(review: { _ in .cancelRevertConfirmation })
            ),
            canUndo: viewStore.state.canUndo,
            canRedo: viewStore.state.canRedo,
            isSaving: viewStore.state.isSaving,
            saveError: viewStore.state.saveError,
            conflict: viewStore.state.conflict,
            isBuilding: viewStore.state.isBuilding,
            buildStatus: viewStore.state.buildStatus,
            onToggleTag: { dispatch(.toggleTag($0)) },
            onAddBlock: { kind, index in dispatch(.addBlock(kind, at: index)) },
            onRemoveBlock: { dispatch(.removeBlock($0)) },
            onMoveBlocks: { source, destination in dispatch(.moveBlocks(source, destination)) },
            onUpdateBlock: { id, block in dispatch(.updateBlock(id, block)) },
            onSave: { dispatch(.save) },
            onRequestRevert: { dispatch(.requestRevert) },
            onRevert: { dispatch(.revertChanges) },
            onUndo: { dispatch(.undo) },
            onRedo: { dispatch(.redo) },
            onKeepMine: { dispatch(.keepMine) },
            onReloadTheirs: { dispatch(.reloadTheirs) },
            onBuild: { dispatch(.build) },
            onRun: { dispatch(.run) },
            onOpenChat: { dispatch(.openChat) }
        )
        .onAppear { dispatch(.onAppear) }
    }
}
