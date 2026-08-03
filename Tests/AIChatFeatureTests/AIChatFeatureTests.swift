import AppDomain
import ReactiveConcurrency
import SwiftRex
import SwiftRexTesting
import Testing

@testable import AIChatFeature

@Suite("AIChatFeature")
@MainActor
struct AIChatFeatureTests {
    private func makeStore(
        chatRespond: @escaping @Sendable (ChatRequest) -> Publisher<ChatStreamEvent, ChatError> = { _ in
            Publisher { continuation throws(ChatError) in continuation.yieldAll([.chunk("Hi"), .finished]) }
        },
        speak: @escaping @Sendable (String) -> Publisher<Void, SpeechError> = { _ in
            Publisher { continuation throws(SpeechError) in continuation.yield(()) }
        },
        startListening: @escaping @Sendable () -> Publisher<TranscriptUpdate, SpeechError> = { .empty() },
        available: Bool = true
    ) -> TestStore<AIChatFeature.Action, AIChatFeature.State, AIChatFeature.Environment> {
        var initial = AIChatFeature.State()
        initial.isAvailable = available
        return TestStore(
            initial: initial,
            behavior: AIChatFeature.behavior(),
            environment: AIChatFeature.Environment(
                isAssistantAvailable: { available },
                chatRespond: chatRespond,
                speak: speak,
                startListening: startListening
            )
        )
    }

    @Test("send appends the user turn and a placeholder reply, streams into that turn (not draftText), then speaks it")
    func sendStreamsAndSpeaks() async throws {
        let store = makeStore()

        store.dispatch(.setDraftText("Hello there")) { $0.draftText = "Hello there" }
        store.dispatch(.send) { state in
            // `draftText` is cleared and never touched again — the reply streams into
            // the placeholder turn appended right alongside the user's own.
            state.turns = [ChatTurn(role: .user, text: "Hello there"), ChatTurn(role: .assistant, text: "")]
            state.draftText = ""
            state.fieldMode = .assistantSpeaking
            state.isResponding = true
        }

        await store.runEffects()

        store.receive(AIChatFeature.Action.prism.chatStreamEvent) { result, state in
            guard case .success(.chunk(let text)) = result else {
                Issue.record("expected a chunk")
                return
            }
            state.turns[1] = ChatTurn(role: .assistant, text: text)
        }
        store.receive(AIChatFeature.Action.prism.chatStreamEvent) { _, state in
            state.isResponding = false
        }

        await store.runEffects()

        store.receive(AIChatFeature.Action.prism.speakingFinished) { _, state in
            state.fieldMode = .userWriting
        }

        // draftText must still be empty — never repopulated by the assistant's reply.
        #expect(store.state.draftText.isEmpty)
    }

    @Test("muted: the reply is finalized but speak() never fires")
    func mutedSkipsSpeaking() async throws {
        let store = makeStore()
        store.dispatch(.toggleMute) { $0.isMuted = true }
        store.dispatch(.setDraftText("Quiet please")) { $0.draftText = "Quiet please" }
        store.dispatch(.send) { state in
            state.turns = [ChatTurn(role: .user, text: "Quiet please"), ChatTurn(role: .assistant, text: "")]
            state.draftText = ""
            state.fieldMode = .assistantSpeaking
            state.isResponding = true
        }

        await store.runEffects()

        store.receive(AIChatFeature.Action.prism.chatStreamEvent) { _, state in state.turns[1] = ChatTurn(role: .assistant, text: "Hi") }
        store.receive(AIChatFeature.Action.prism.chatStreamEvent) { _, state in
            state.isResponding = false
            state.fieldMode = .userWriting
        }

        // No `runEffects()`/`receive` for `speakingFinished` here — if `speak()` had fired
        // anyway, TestStore's exhaustive end-of-test check would fail on deinit.
    }

    @Test("a typed send doesn't reopen the mic once the reply finishes speaking")
    func typedSendDoesNotReopenMic() async throws {
        let store = makeStore()

        store.dispatch(.setDraftText("Hello there")) { $0.draftText = "Hello there" }
        store.dispatch(.send) { state in
            state.turns = [ChatTurn(role: .user, text: "Hello there"), ChatTurn(role: .assistant, text: "")]
            state.draftText = ""
            state.fieldMode = .assistantSpeaking
            state.isResponding = true
        }

        await store.runEffects()

        store.receive(AIChatFeature.Action.prism.chatStreamEvent) { _, state in state.turns[1] = ChatTurn(role: .assistant, text: "Hi") }
        store.receive(AIChatFeature.Action.prism.chatStreamEvent) { _, state in state.isResponding = false }

        await store.runEffects()

        store.receive(AIChatFeature.Action.prism.speakingFinished) { _, state in
            state.fieldMode = .userWriting
        }

        #expect(!store.state.isListening)
    }

    @Test("send is a no-op when the draft is blank")
    func sendIgnoresBlankDraft() async throws {
        let store = makeStore()
        store.dispatch(.send) { _ in }
    }

    @Test("send is a no-op when the assistant isn't available")
    func sendIgnoresWhenUnavailable() async throws {
        let store = makeStore(available: false)
        store.dispatch(.setDraftText("Hello")) { $0.draftText = "Hello" }
        store.dispatch(.send) { _ in }
    }

    @Test("a non-final transcript update only updates the draft text")
    func partialTranscriptUpdatesDraftOnly() async throws {
        let store = makeStore()
        store.dispatch(.toggleListening) { $0.isListening = true }
        store.dispatch(.transcriptReceived(.success(TranscriptUpdate(text: "Hel", isFinal: false)))) {
            $0.draftText = "Hel"
        }
    }

    @Test("a final transcript update stops listening and auto-sends, and reopens the mic once the reply finishes")
    func finalTranscriptAutoSends() async throws {
        let store = makeStore()
        store.dispatch(.toggleListening) { $0.isListening = true }
        store.dispatch(.transcriptReceived(.success(TranscriptUpdate(text: "Hello there", isFinal: true)))) { state in
            state.draftText = "Hello there"
            state.isListening = false
            state.lastInputWasVoice = true
        }

        await store.runEffects()

        store.receive(AIChatFeature.Action.prism.send) { state in
            state.turns = [ChatTurn(role: .user, text: "Hello there"), ChatTurn(role: .assistant, text: "")]
            state.draftText = ""
            state.fieldMode = .assistantSpeaking
            state.isResponding = true
        }

        await store.runEffects()

        store.receive(AIChatFeature.Action.prism.chatStreamEvent) { _, state in state.turns[1] = ChatTurn(role: .assistant, text: "Hi") }
        store.receive(AIChatFeature.Action.prism.chatStreamEvent) { _, state in state.isResponding = false }

        await store.runEffects()

        // `lastInputWasVoice` is still true (nothing since reset it) — the mic reopens
        // automatically once the reply is done, for a continuous hands-free exchange.
        store.receive(AIChatFeature.Action.prism.speakingFinished) { _, state in
            state.fieldMode = .userWriting
            state.isListening = true
        }
    }

    @Test("saveToNotes is a no-op with no active session")
    func saveToNotesIsNoOpWithoutTurns() async throws {
        let store = makeStore()
        store.dispatch(.setDraftText("note")) { $0.draftText = "note" }
        store.dispatch(.saveToNotes) { _ in }
    }

    @Test("saveToNotes compacts the session into notesCompacted without ending it")
    func saveToNotesCompactsWithoutClosing() async throws {
        var initial = AIChatFeature.State()
        initial.isAvailable = true
        initial.turns = [ChatTurn(role: .user, text: "Hi"), ChatTurn(role: .assistant, text: "Hello")]
        let store = TestStore(
            initial: initial,
            behavior: AIChatFeature.behavior(),
            environment: AIChatFeature.Environment(
                isAssistantAvailable: { true },
                chatRespond: { _ in .empty() },
                speak: { _ in .empty() },
                startListening: { .empty() }
            )
        )

        store.dispatch(.saveToNotes) { _ in }

        await store.runEffects()

        store.receive(AIChatFeature.Action.prism.notesCompacted) { text, _ in
            #expect(text == "You: Hi\nAssistant: Hello")
        }
    }

    /// The panel cannot dismiss itself — the app owns its presentation — so "closes
    /// immediately" now means "raises no gate". `AppFeature`'s `when: hasNoLiveChatSession`
    /// bridge is what turns this into an actual dismissal.
    @Test("close with no active session raises no confirmation gate")
    func closeWithEmptySessionRaisesNoGate() async throws {
        var initial = AIChatFeature.State()
        initial.isAvailable = true
        let store = TestStore(
            initial: initial,
            behavior: AIChatFeature.behavior(),
            environment: AIChatFeature.Environment(
                isAssistantAvailable: { true },
                chatRespond: { _ in .empty() },
                speak: { _ in .empty() },
                startListening: { .empty() }
            )
        )

        store.dispatch(.close) { $0.isListening = false }
    }

    @Test("close with an active session asks for confirmation instead of closing")
    func closeWithActiveSessionAsksFirst() async throws {
        var initial = AIChatFeature.State()
        initial.isAvailable = true
        initial.turns = [ChatTurn(role: .user, text: "Hi")]
        let store = TestStore(
            initial: initial,
            behavior: AIChatFeature.behavior(),
            environment: AIChatFeature.Environment(
                isAssistantAvailable: { true },
                chatRespond: { _ in .empty() },
                speak: { _ in .empty() },
                startListening: { .empty() }
            )
        )

        store.dispatch(.close) { $0.isConfirmingClose = true }
    }

    @Test("cancelClose keeps the session and the panel open")
    func cancelCloseKeepsSession() async throws {
        var initial = AIChatFeature.State()
        initial.turns = [ChatTurn(role: .user, text: "Hi")]
        initial.isConfirmingClose = true
        let store = TestStore(
            initial: initial,
            behavior: AIChatFeature.behavior(),
            environment: AIChatFeature.Environment(
                isAssistantAvailable: { true },
                chatRespond: { _ in .empty() },
                speak: { _ in .empty() },
                startListening: { .empty() }
            )
        )

        store.dispatch(.cancelClose) { $0.isConfirmingClose = false }
    }

    @Test("confirmCloseAndDiscard closes and drops the session with no save")
    func confirmCloseAndDiscardClearsSession() async throws {
        var initial = AIChatFeature.State()
        initial.turns = [ChatTurn(role: .user, text: "Hi")]
        initial.draftText = "typing…"
        initial.isConfirmingClose = true
        let store = TestStore(
            initial: initial,
            behavior: AIChatFeature.behavior(),
            environment: AIChatFeature.Environment(
                isAssistantAvailable: { true },
                chatRespond: { _ in .empty() },
                speak: { _ in .empty() },
                startListening: { .empty() }
            )
        )

        store.dispatch(.confirmCloseAndDiscard) { state in
            state.isListening = false
            state.isConfirmingClose = false
            state.turns = []
            state.draftText = ""
            state.fieldMode = .userWriting
        }
    }

    @Test("confirmCloseAndSave closes, clears the session, and fires notesCompacted")
    func confirmCloseAndSaveClearsAndCompacts() async throws {
        var initial = AIChatFeature.State()
        initial.turns = [ChatTurn(role: .user, text: "Hi"), ChatTurn(role: .assistant, text: "Hello")]
        initial.isConfirmingClose = true
        let store = TestStore(
            initial: initial,
            behavior: AIChatFeature.behavior(),
            environment: AIChatFeature.Environment(
                isAssistantAvailable: { true },
                chatRespond: { _ in .empty() },
                speak: { _ in .empty() },
                startListening: { .empty() }
            )
        )

        store.dispatch(.confirmCloseAndSave) { state in
            state.isListening = false
            state.isConfirmingClose = false
            state.turns = []
            state.draftText = ""
            state.fieldMode = .userWriting
        }

        await store.runEffects()

        store.receive(AIChatFeature.Action.prism.notesCompacted) { text, _ in
            #expect(text == "You: Hi\nAssistant: Hello")
        }
    }

    /// Every open is a fresh session, but that is no longer something `.start` has to
    /// remember to do: presenting the panel *constructs* the state, so there is never a
    /// leftover session for it to reset. All `.start` does is ask whether the on-device
    /// assistant exists.
    @Test("a freshly constructed session carries only the article's notes")
    func aFreshSessionCarriesOnlyTheNotes() async throws {
        let initial = AIChatFeature.State(brainstorming: "Notes for this article")
        #expect(initial.turns.isEmpty)
        #expect(initial.draftText.isEmpty)
        #expect(initial.isConfirmingClose == false)
        #expect(initial.lastInputWasVoice == false)
        #expect(initial.brainstorming == "Notes for this article")

        let store = TestStore(
            initial: initial,
            behavior: AIChatFeature.behavior(),
            environment: AIChatFeature.Environment(
                isAssistantAvailable: { true },
                chatRespond: { _ in .empty() },
                speak: { _ in .empty() },
                startListening: { .empty() }
            )
        )

        store.dispatch(.start) { _ in }
        await store.runEffects()

        store.receive(AIChatFeature.Action.prism.setAvailability) { available, state in
            state.isAvailable = available
        }
    }
}
