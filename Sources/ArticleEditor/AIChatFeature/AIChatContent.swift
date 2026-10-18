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
    let lastError: String?
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
                    "Assistant Unavailable",
                    message: Text("The on-device assistant isn't available on this device."),
                    icon: Image(systemName: "apple.intelligence")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                turnsList
                composer
            }
            if let lastError {
                Banner(Text(verbatim: lastError), style: .error)
                    .padding(Space.small)
            }
        }
        .background { Backdrop(.grid()) }
        .confirmationDialog(
            "Save this conversation to Brainstorming before closing?",
            isPresented: isConfirmingClose,
            titleVisibility: .visible
        ) {
            Button("Save to Notes and Close", action: onConfirmCloseAndSave)
            Button("Discard and Close", role: .destructive, action: onConfirmCloseAndDiscard)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Closing ends this conversation — save it to Brainstorming first if you want to keep it.")
        }
    }

    private var header: some View {
        HStack {
            Text("Assistant")
                .font(.bodyStrong)
                .foregroundStyle(.ink)
            Spacer()
            // Dispatches `.close` rather than SwiftUI's `dismiss()`. `dismiss()` hides
            // the container directly, behind the store's back, so the "save this
            // conversation?" gate below never got its chance — the panel just vanished
            // with the conversation in it.
            Button("Done", action: onClose)
            Button(action: onToggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.plain)
            .help(isMuted ? "Unmute replies" : "Mute replies")
            Button(action: onSaveToNotes) {
                Label("Save to Notes", systemImage: "note.text.badge.plus")
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
        Composer("Say something…", text: draftText, isEditable: isFieldEditable, isBusy: isResponding) {
            Pill(isActive: isListening, action: isFieldEditable ? onToggleListening : nil) {
                Image(systemName: isListening ? "mic.fill" : "mic")
                    .frame(width: Size.controlSmall, height: Size.controlSmall)
            }
            .accessibilityLabel(Text(isListening ? "Stop listening" : "Dictate"))
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
            author: Text(turn.role == .user ? "You" : "Assistant"),
            side: turn.role == .user ? .mine : .theirs
        )
    }
}
