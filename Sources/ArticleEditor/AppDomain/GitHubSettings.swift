import Foundation

/// User-supplied GitHub sync configuration — never bundled with the app, always entered
/// by the user and persisted locally (`token` in the Keychain, `repoURL`/`baseBranch` in a
/// plain settings file — see `World+Live.swift`).
public struct GitHubSettings: Codable, Equatable, Sendable {
    public var repoURL: String
    /// The branch pull reads from and pushes open their pull request *against* — never a
    /// branch this app writes to. Every push commits to its own feature branch instead,
    /// so nothing here is ever force-moved under the user.
    public var baseBranch: String
    public var token: String

    public init(repoURL: String, baseBranch: String, token: String) {
        self.repoURL = repoURL
        self.baseBranch = baseBranch
        self.token = token
    }

    public var repository: GitHubRepository? {
        GitHubRepository(parsing: repoURL)
    }
}

/// An `{owner, name}` pair parsed from whatever form of GitHub URL the user pasted in.
public struct GitHubRepository: Equatable, Sendable {
    public let owner: String
    public let name: String

    /// Accepts `https://github.com/owner/repo`, the same with a trailing `.git`,
    /// `git@github.com:owner/repo.git`, or a bare `owner/repo` shorthand. Returns `nil`
    /// for anything that doesn't resolve to exactly two non-empty path components.
    public init?(parsing repoURL: String) {
        var trimmed = repoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasSuffix(".git") {
            trimmed.removeLast(4)
        }

        let path: String
        if trimmed.hasPrefix("git@github.com:") {
            path = String(trimmed.dropFirst("git@github.com:".count))
        } else if let url = URL(string: trimmed), let host = url.host, host.lowercased().contains("github.com") {
            path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            path = trimmed
        }

        let components = path.split(separator: "/").map(String.init)
        guard components.count == 2, !components[0].isEmpty, !components[1].isEmpty else { return nil }
        owner = components[0]
        name = components[1]
    }
}
