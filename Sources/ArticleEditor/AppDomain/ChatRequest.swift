/// A single turn's worth of input to the on-device language model: `instructions` carries
/// long-term context (the article's Brainstorming field plus recent conversation turns),
/// `prompt` is what the user just said. Kept as one value rather than a raw `String` so
/// `World.chatRespond` never has to guess which part is memory versus the live question.
public struct ChatRequest: Equatable, Sendable {
    public let instructions: String
    public let prompt: String

    public init(instructions: String, prompt: String) {
        self.instructions = instructions
        self.prompt = prompt
    }
}
