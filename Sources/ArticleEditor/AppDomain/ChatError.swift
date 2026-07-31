public enum ChatError: Error, Equatable, Sendable {
    case modelUnavailable
    case generationFailed(reason: String)
}
