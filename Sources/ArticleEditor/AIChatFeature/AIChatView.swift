import AppDomain
import SwiftRexArchitecture
import SwiftUI

@BoundTo(AIChatFeature.self, strategy: .observationSimple)
public struct AIChatView: View {
    public var body: some View {
        // `dispatch(_:file:function:line:)` has magic-literal defaults, so it can't be
        // bare-referenced — see ArticleEditorView for the same unavoidable closure.
        let dispatch: (AIChatFeature.ViewAction) -> Void = { viewStore.dispatch($0) }
        AIChatContent(
            isAvailable: viewStore.state.isAvailable,
            isListening: viewStore.state.isListening,
            isResponding: viewStore.state.isResponding,
            isMuted: viewStore.state.isMuted,
            draftText: viewStore.binding(.state(\.draftText), dispatch: .action(\.setDraftText)),
            isFieldEditable: viewStore.state.isFieldEditable,
            turns: viewStore.state.turns,
            lastError: viewStore.state.lastError,
            // `.presence` only covers `Optional<T>`/`Presentation<T>` state — for a plain
            // `Bool` like this, `.binding` is the correct primitive (see ArticleEditorView's
            // `isConfirmingRevert` for the full story on why `.presence` silently always
            // reads `true` for a non-Optional field).
            isConfirmingClose: viewStore.binding(
                .state(\.isConfirmingClose),
                dispatch: .action(review: { _ in .cancelClose })
            ),
            onSend: { dispatch(.send) },
            onToggleListening: { dispatch(.toggleListening) },
            onToggleMute: { dispatch(.toggleMute) },
            onSaveToNotes: { dispatch(.saveToNotes) },
            onConfirmCloseAndDiscard: { dispatch(.confirmCloseAndDiscard) },
            onConfirmCloseAndSave: { dispatch(.confirmCloseAndSave) }
        )
        .onAppear { dispatch(.open) }
        .onDisappear { dispatch(.close) }
    }
}
