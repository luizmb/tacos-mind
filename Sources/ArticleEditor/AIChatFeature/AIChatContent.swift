import AppDomain
import SwiftUI

public struct AIChatContent: View {
    @Environment(\.dismiss) private var dismiss

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
    let onConfirmCloseAndDiscard: () -> Void
    let onConfirmCloseAndSave: () -> Void

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !isAvailable {
                ContentUnavailableView(
                    "Assistant Unavailable",
                    systemImage: "apple.intelligence",
                    description: Text("The on-device assistant isn't available on this device.")
                )
            } else {
                turnsList
                Divider()
                composer
            }
            if let lastError {
                Text(lastError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity)
            }
        }
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
                .font(.headline)
            Spacer()
            // `dismiss()` goes through the same `isChatOpen` binding the toolbar toggle
            // uses, so it dispatches `.chat(.close)` — not a raw "hide the sheet" — which
            // is what makes the unsaved-conversation confirmation dialog above still
            // fire correctly instead of silently discarding an in-progress chat.
            Button("Done") { dismiss() }
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
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Say something…", text: draftText, axis: .vertical)
                .disabled(!isFieldEditable)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Button(action: onToggleListening) {
                Image(systemName: isListening ? "mic.fill" : "mic")
                    .foregroundStyle(isListening ? Color.red : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(!isFieldEditable)
            Button(action: onSend) {
                if isResponding {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                }
            }
            .buttonStyle(.plain)
            .disabled(isResponding || !isFieldEditable || draftText.wrappedValue.isEmpty)
        }
        .padding()
    }
}

private struct TurnRow: View {
    let turn: ChatTurn

    private var alignment: HorizontalAlignment { turn.role == .user ? .trailing : .leading }
    private var frameAlignment: Alignment { turn.role == .user ? .trailing : .leading }

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(turn.role == .user ? "You" : "Assistant")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(turn.text)
                .padding(8)
                .background(turn.role == .user ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }
}
