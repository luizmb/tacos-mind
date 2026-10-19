import Localization
import AppDomain
import SwiftUI
import Vitral
import VitralTokens

public struct AIChatContent: View {
    let isAvailable: Bool
    let isListening: Bool
    let isResponding: Bool
    let isMuted: Bool
    let draftText: Binding<String>
    let isFieldEditable: Bool
    let turns: [ChatTurn]
    let lastError: LocalizedStringResource?
    let isConfirmingClose: Binding<Bool>
    let onSend: () -> Void
    let onToggleListening: () -> Void
    let onToggleMute: () -> Void
    let onSaveToNotes: () -> Void
    let onClose: () -> Void
    let onConfirmCloseAndDiscard: () -> Void
    let onConfirmCloseAndSave: () -> Void

    public var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            if !isAvailable {
                EmptyState(
                    L.Chat.assistantUnavailable,
                    message: Text(L.Chat.theOnDeviceAssistantIsnt),
                    icon: Image(systemName: "apple.intelligence")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                turnsList
                composer
            }
            if let lastError {
                Banner(Text(lastError), style: .error)
                    .padding(Space.small)
            }
        }
        .background { Backdrop(.grid()) }
        .confirmationDialog(
            L.Chat.saveThisConversationToBrainstorming,
            isPresented: isConfirmingClose,
            titleVisibility: .visible
        ) {
            Button(L.Chat.saveToNotesAndClose, action: onConfirmCloseAndSave)
            Button(L.Chat.discardAndClose, role: .destructive, action: onConfirmCloseAndDiscard)
            Button(L.Common.cancel, role: .cancel) {}
        } message: {
            Text(L.Chat.closingEndsThisConversationSave)
        }
    }

    private var header: some View {
        HStack {
            Text(L.Chat.assistant)
                .font(.bodyStrong)
                .foregroundStyle(.ink)
            Spacer()
            // Dispatches `.close` rather than SwiftUI's `dismiss()`. `dismiss()` hides
            // the container directly, behind the store's back, so the "save this
            // conversation?" gate below never got its chance — the panel just vanished
            // with the conversation in it.
            Button(L.Common.done, action: onClose)
            Button(action: onToggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.plain)
            .help(isMuted ? L.Chat.unmuteReplies : L.Chat.muteReplies)
            Button(action: onSaveToNotes) {
                Label(L.Chat.saveToNotes, systemImage: "note.text.badge.plus")
            }
            .disabled(turns.isEmpty)
        }
        .padding()
    }

    private var turnsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(turns.enumerated()), id: \.offset) { _, turn in
                    TurnRow(turn: turn)
                }
            }
            .padding()
        }
    }

    private var composer: some View {
        Composer(L.Chat.saySomething, text: draftText, isEditable: isFieldEditable, isBusy: isResponding) {
            Pill(isActive: isListening, action: isFieldEditable ? onToggleListening : nil) {
                Image(systemName: isListening ? "mic.fill" : "mic")
                    .frame(width: Size.controlSmall, height: Size.controlSmall)
            }
            .accessibilityLabel(Text(isListening ? L.Chat.stopListening : L.Chat.dictate))
        } send: {
            onSend()
        }
        .padding()
    }
}

private struct TurnRow: View {
    let turn: ChatTurn

    var body: some View {
        MessageBubble(
            Text(verbatim: turn.text),
            author: Text(turn.role == .user ? L.Chat.you : L.Chat.assistant),
            side: turn.role == .user ? .mine : .theirs
        )
    }
}
