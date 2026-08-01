public enum SpeechError: Error, Equatable, Sendable {
    case recognizerUnavailable
    case microphoneUnavailable(reason: String)
    case recognitionFailed(reason: String)
    case synthesisFailed(reason: String)
}
