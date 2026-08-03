import AppDomain
import CoreFP
import CoreFPOperators
import Foundation
import ReactiveConcurrency
import SwiftRex
import SwiftRexArchitecture
import SwiftRexOperators
import SwiftRexReactiveConcurrency
import SwiftUI

@Feature(strategy: .observationSimple)
public enum AIChatFeature {
    /// Which side of the conversation currently owns the shared chat field — the same
    /// text view alternates between "you're writing" and "you're reading/hearing the
    /// assistant's reply" rather than using two separate fields.
    public enum FieldMode: Sendable, Equatable {
        case userWriting
        case assistantSpeaking
    }

    public struct State: Sendable, Equatable {
        public var isAvailable: Bool
        public var isListening: Bool
        public var isResponding: Bool
        public var isMuted: Bool
        public var draftText: String
        public var fieldMode: FieldMode
        public var turns: [ChatTurn]
        public var lastError: String?
        /// Mirrors the open article's Brainstorming field — seeded when the panel is
        /// presented and kept current by an app-level bridge (see `AppFeature.swift`),
        /// never edited directly from this feature.
        public var brainstorming: String
        /// `true` while the "save this conversation before closing?" dialog is up — set by
        /// `.close` whenever there's an active session (`turns` non-empty) to lose,
        /// whether the close was requested by toggling the panel or by an app-level
        /// article switch waiting on this same decision.
        public var isConfirmingClose: Bool
        /// Whether the last message the user sent came from dictation rather than typing —
        /// drives auto-reopening the mic once the assistant's reply finishes, for a
        /// continuous hands-free conversation. Reset by typing (`.setDraftText`) or by
        /// opening a fresh session.
        public var lastInputWasVoice: Bool

        /// A fresh session for whichever article is open. Presenting the panel builds one
        /// of these; dismissing it throws it away — so "every open is a new conversation"
        /// is a property of the state's lifetime rather than a reset the reducer has to
        /// remember to perform.
        public init(brainstorming: String = "") {
            isAvailable = false
            isListening = false
            isResponding = false
            isMuted = false
            draftText = ""
            fieldMode = .userWriting
            turns = []
            lastError = nil
            self.brainstorming = brainstorming
            isConfirmingClose = false
            lastInputWasVoice = false
        }
    }

    @Prisms
    public enum Action: Sendable {
        /// Dispatched by the view's `onAppear`. The session is already fresh by
        /// construction, so this only asks the world whether the assistant exists.
        case start
        case setAvailability(Bool)
        /// Requests closing the panel. A panel cannot dismiss itself — the parent owns
        /// its presentation — so this either raises the "save this conversation?" gate
        /// (an active session) or falls through for the app to dismiss on. See
        /// `confirmCloseAndSave`/`confirmCloseAndDiscard`/`cancelClose`.
        case close
        case cancelClose
        case confirmCloseAndDiscard
        case confirmCloseAndSave
        case setDraftText(String)
        case send
        case chatStreamEvent(Result<ChatStreamEvent, ChatError>)
        case toggleListening
        case transcriptReceived(Result<TranscriptUpdate, SpeechError>)
        case toggleMute
        case speakingFinished(Result<Void, SpeechError>)
        /// Compacts the current session and fires `notesCompacted` — used both by the
        /// standalone "Save to Notes" button (session keeps going) and by
        /// `confirmCloseAndSave` (session ends right after).
        case saveToNotes
        /// The actual write into the article's Brainstorming field happens at the app
        /// level (only it can reach `ArticleEditorFeature`'s state) — this just carries
        /// the already-compacted text there.
        case notesCompacted(String)
    }

    public struct Environment: Sendable {
        public let isAssistantAvailable: @Sendable () -> Bool
        public let chatRespond: @Sendable (ChatRequest) -> Publisher<ChatStreamEvent, ChatError>
        public let speak: @Sendable (String) -> Publisher<Void, SpeechError>
        public let startListening: @Sendable () -> Publisher<TranscriptUpdate, SpeechError>

        public init(
            isAssistantAvailable: @escaping @Sendable () -> Bool,
            chatRespond: @escaping @Sendable (ChatRequest) -> Publisher<ChatStreamEvent, ChatError>,
            speak: @escaping @Sendable (String) -> Publisher<Void, SpeechError>,
            startListening: @escaping @Sendable () -> Publisher<TranscriptUpdate, SpeechError>
        ) {
            self.isAssistantAvailable = isAssistantAvailable
            self.chatRespond = chatRespond
            self.speak = speak
            self.startListening = startListening
        }
    }

    public struct ViewState: Sendable, Equatable {
        public var isAvailable: Bool
        public var isListening: Bool
        public var isResponding: Bool
        public var isMuted: Bool
        public var draftText: String
        public var isFieldEditable: Bool
        public var turns: [ChatTurn]
        public var lastError: String?
        public var isConfirmingClose: Bool
    }

    @Prisms
    public enum ViewAction: Sendable {
        case onAppear
        case close
        case cancelClose
        case confirmCloseAndDiscard
        case confirmCloseAndSave
        case setDraftText(String)
        case send
        case toggleListening
        case toggleMute
        case saveToNotes
    }

    public static let mapState = Reader<Environment, @MainActor @Sendable (State) -> ViewState> { _ in
        { state in
            ViewState(
                isAvailable: state.isAvailable,
                isListening: state.isListening,
                isResponding: state.isResponding,
                isMuted: state.isMuted,
                draftText: state.draftText,
                isFieldEditable: state.fieldMode == .userWriting,
                turns: state.turns,
                lastError: state.lastError,
                isConfirmingClose: state.isConfirmingClose
            )
        }
    }

    public static let mapAction = Reader<Environment, @Sendable (ViewAction) -> Action> { _ in
        { viewAction in
            switch viewAction {
            case .onAppear: .start
            case .close: .close
            case .cancelClose: .cancelClose
            case .confirmCloseAndDiscard: .confirmCloseAndDiscard
            case .confirmCloseAndSave: .confirmCloseAndSave
            case .setDraftText(let value): .setDraftText(value)
            case .send: .send
            case .toggleListening: .toggleListening
            case .toggleMute: .toggleMute
            case .saveToNotes: .saveToNotes
            }
        }
    }

    public static func initialState(with brainstorming: String) -> State { .init(brainstorming: brainstorming) }

    public static func behavior() -> Behavior<Action, State, Environment> {
        chatBehavior() <> listeningSupervisor()
    }

    // MARK: - Chat + speech (Commands)

    private static func chatBehavior() -> Behavior<Action, State, Environment> {
        .handle { action, context in
            switch action {
            // Nothing to reset — presenting the panel built this state a moment ago, so
            // the session is fresh by construction. All that's left is to ask the world
            // whether the on-device assistant is actually there.
            case .start:
                return .produce { ctx in
                    let transform: @Sendable (()) -> Action = const(.setAvailability(ctx.environment.isAssistantAvailable()))
                    return Publisher<Void, Never>.just(()).asEffect(transform)
                }

            case .setAvailability(let available):
                return .reduce { $0.isAvailable = available }

            // With no session to lose there is nothing to ask, so this falls through to
            // the app, which dismisses the panel. With one, the gate goes up first and
            // the app dismisses on whichever answer comes back.
            case .close:
                guard let state = context.stateBefore, !state.turns.isEmpty else {
                    return .reduce { $0.isListening = false }
                }
                return .reduce { $0.isConfirmingClose = true }

            case .cancelClose:
                return .reduce { $0.isConfirmingClose = false }

            // Clearing `turns` here (rather than leaving it to the state being thrown
            // away) keeps the gate closed for the frame between the answer and the
            // dismissal — otherwise `close` could re-raise it on the way out.
            case .confirmCloseAndDiscard:
                return .reduce { state in
                    state.isListening = false
                    state.isConfirmingClose = false
                    state.turns = []
                    state.draftText = ""
                    state.fieldMode = .userWriting
                }

            case .confirmCloseAndSave:
                guard let state = context.stateBefore else { return .doNothing }
                let compacted = Self.compactNotes(state.turns)
                return .reduce { state in
                    state.isListening = false
                    state.isConfirmingClose = false
                    state.turns = []
                    state.draftText = ""
                    state.fieldMode = .userWriting
                }
                .produce { _ in Self.immediateDispatch(.notesCompacted(compacted)) }

            case .setDraftText(let value):
                return .reduce { state in
                    state.draftText = value
                    state.lastInputWasVoice = false
                }

            case .send:
                guard let state = context.stateBefore, state.isAvailable else { return .doNothing }
                let prompt = state.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !prompt.isEmpty else { return .doNothing }
                let instructions = Self.buildInstructions(brainstorming: state.brainstorming, turns: state.turns)
                return .reduce { s in
                    s.turns.append(ChatTurn(role: .user, text: prompt))
                    // A placeholder bubble, updated in place as chunks arrive (see
                    // `.chatStreamEvent(.chunk)`) — the reply streams into the turns list,
                    // not into `draftText`. `draftText` is the compose field ONLY; it must
                    // never hold anything but what the user is about to send next.
                    s.turns.append(ChatTurn(role: .assistant, text: ""))
                    s.draftText = ""
                    s.fieldMode = .assistantSpeaking
                    s.isResponding = true
                    s.lastError = nil
                }
                .produce { ctx in
                    ctx.environment.chatRespond(ChatRequest(instructions: instructions, prompt: prompt))
                        .asEffect { Action.chatStreamEvent($0) }
                }

            case .chatStreamEvent(.success(.chunk(let text))):
                return .reduce { state in
                    guard let lastIndex = state.turns.indices.last else { return }
                    state.turns[lastIndex] = ChatTurn(role: .assistant, text: text)
                }

            case .chatStreamEvent(.success(.finished)):
                guard let state = context.stateBefore else { return .doNothing }
                let finalText = state.turns.last?.text ?? ""
                guard !state.isMuted else {
                    return .reduce { s in
                        s.isResponding = false
                        s.fieldMode = .userWriting
                    }
                }
                return .reduce { $0.isResponding = false }
                    .produce { ctx in ctx.environment.speak(finalText).asEffect { Action.speakingFinished($0) } }

            case .chatStreamEvent(.failure(let error)):
                return .reduce { state in
                    state.isResponding = false
                    state.fieldMode = .userWriting
                    state.lastError = error.readableDescription
                    // Don't strand a hands-free conversation on a single failed reply —
                    // reopen the mic so the user can just try again.
                    if state.lastInputWasVoice { state.isListening = true }
                }

            case .toggleListening:
                return .reduce { $0.isListening.toggle() }

            // `update.isFinal` means "the user stopped talking" (a silence timeout in
            // `World.startListening`, independent of the recognizer's own per-segment
            // revision tracking) — not "this one segment is done," which `update.text`
            // already folds in as the running total. See `TranscriptUpdate`'s doc.
            case .transcriptReceived(.success(let update)):
                guard update.isFinal else {
                    return .reduce { $0.draftText = update.text }
                }
                return .reduce { state in
                    state.draftText = update.text
                    state.isListening = false
                    state.lastInputWasVoice = true
                }
                .produce { _ in Self.immediateDispatch(.send) }

            case .transcriptReceived(.failure(let error)):
                return .reduce { state in
                    state.isListening = false
                    state.lastError = error.readableDescription
                }

            case .toggleMute:
                return .reduce { $0.isMuted.toggle() }

            case .speakingFinished(.success):
                return .reduce { state in
                    state.fieldMode = .userWriting
                    if state.lastInputWasVoice { state.isListening = true }
                }

            case .speakingFinished(.failure(let error)):
                return .reduce { state in
                    state.fieldMode = .userWriting
                    state.lastError = error.readableDescription
                    if state.lastInputWasVoice { state.isListening = true }
                }

            // Standalone "Save to Notes" button — compacts and fires `notesCompacted`
            // without ending the session (unlike `confirmCloseAndSave`, which does both).
            case .saveToNotes:
                guard let state = context.stateBefore, !state.turns.isEmpty else { return .doNothing }
                let compacted = Self.compactNotes(state.turns)
                return .produce { _ in Self.immediateDispatch(.notesCompacted(compacted)) }

            // The actual write happens in the app-level bridge (it alone can reach
            // ArticleEditorFeature's state) — nothing left to do locally.
            case .notesCompacted:
                return .doNothing
            }
        }
    }

    private static func compactNotes(_ turns: [ChatTurn]) -> String {
        turns
            .map { turn in "\(turn.role == .user ? "You" : "Assistant"): \(turn.text)" }
            .joined(separator: "\n")
    }

    /// Pointers to where FP/category-theory material actually lives — not retrieval (the
    /// on-device model can't browse to these), just naming the ecosystem so it can
    /// reference something concrete and current instead of reasoning about these topics
    /// in a vacuum, and point Luiz back to the right place. A stopgap ahead of proper
    /// retrieval or adapter training (see the FP-training conversation this came from).
    private static let knowledgeHints = """
        Relevant material on functional programming and category theory, worth referencing \
        by name when it fits the conversation:
        - The FP Swift package (github.com/luizmb/FP): CoreFP/CoreFPOperators (map, flatMap, \
        compose, curry, Reader/Stateful/Writer monads) and DataStructure/DataStructureOperators \
        (Either, Validation, NonEmpty, optics) — the concepts implemented as real Swift code.
        - SwiftRex (github.com/SwiftRex/SwiftRex) and ReactiveConcurrency: the same ideas \
        applied in a production unidirectional-dataflow architecture — reducers, monadic \
        effect handling, functor/applicative composition.
        - The ios.lu article series itself (this site): a public "Functional Programming for \
        Swift Developers" series already covering purity, composition, algebraic data types, \
        functors, and category theory fundamentals (categories, natural transformations, \
        initial/terminal objects, why Swift can't express higher-kinded types).
        """

    /// Long-term memory (Brainstorming) plus a short window of recent turns, joined into
    /// one instructions string — `LanguageModelSession`'s context window is small, so the
    /// full history isn't carried forever, just enough for the conversation to feel
    /// continuous within a session.
    private static func buildInstructions(brainstorming: String, turns: [ChatTurn]) -> String {
        let recentTurns = turns.suffix(10).map { turn in
            "\(turn.role == .user ? "User" : "Assistant"): \(turn.text)"
        }.joined(separator: "\n")
        return [knowledgeHints, brainstorming, recentTurns]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// Fires `action` as an immediate follow-up dispatch from within a `.produce` step —
    /// same trick as `AppAction.immediateDispatch` in `AppFeature.swift`, scoped locally
    /// to this feature's own action type.
    private static func immediateDispatch(_ action: Action) -> Effect<Action> {
        let transform: @Sendable (()) -> Action = const(action)
        return Publisher<Void, Never>.just(()).asEffect(transform)
    }

    // MARK: - Listening (Subscription)

    private static func listeningSupervisor() -> Behavior<Action, State, Environment> {
        .supervise { state in
            Supervision { env in
                guard state.isListening else { return [] }
                return [env.startListening().asChannel(id: "chat-listening") { Action.transcriptReceived($0) }]
            }
        }
    }

    public typealias Content = AIChatView
}

extension ChatError {
    var readableDescription: String {
        switch self {
        case .modelUnavailable: "The on-device assistant isn't available right now."
        case .generationFailed(let reason): "The assistant couldn't reply: \(reason)"
        }
    }
}

extension SpeechError {
    var readableDescription: String {
        switch self {
        case .recognizerUnavailable: "Speech recognition isn't available right now."
        case .microphoneUnavailable(let reason): "Couldn't use the microphone: \(reason)"
        case .recognitionFailed(let reason): "Couldn't understand that: \(reason)"
        case .synthesisFailed(let reason): "Couldn't speak the reply: \(reason)"
        }
    }
}
