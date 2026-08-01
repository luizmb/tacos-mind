/// `World.chatRespond`'s emissions. A silent `Publisher` completion carries no action on
/// its own (only successful values and terminating failures do — see `asEffect`), so
/// "the reply is done" has to be a value in the stream, not inferred from completion:
/// `.chunk` fires once per cumulative-text update, `.finished` is always the last value
/// before the effect completes, and is what actually finalizes the turn and (unless
/// muted) triggers speaking it aloud.
public enum ChatStreamEvent: Equatable, Sendable {
    case chunk(String)
    case finished
}
