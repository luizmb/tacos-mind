public enum ArticleEditorError: Error, Equatable, Sendable {
    case fileReadFailed(path: String, reason: String)
    case fileWriteFailed(path: String, reason: String)
    case parseFailed(path: String, reason: String)
}
