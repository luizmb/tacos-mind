public enum GitHubError: Error, Equatable, Sendable {
    case notConfigured
    case invalidRepoURL
    case network(String)
    case badStatus(Int)
    case decoding(String)
}
