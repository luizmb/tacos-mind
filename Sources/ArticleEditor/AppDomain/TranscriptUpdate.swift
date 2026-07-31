/// One emission from `World.startListening`: `text` is the recognizer's current best guess
/// for the whole utterance so far (not just the newest word), and `isFinal` marks the point
/// the recognizer considers the utterance complete — the trigger for auto-sending it.
public struct TranscriptUpdate: Equatable, Sendable {
    public let text: String
    public let isFinal: Bool

    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}
