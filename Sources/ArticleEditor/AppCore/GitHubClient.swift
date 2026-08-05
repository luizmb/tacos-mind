import AppDomain
import Foundation
import NetworkClient
import ReactiveConcurrency

// MARK: - Wire types (GitHub REST API JSON shapes — explicit CodingKeys throughout, no
// `.convertFromSnakeCase`, since that would mangle `download_url`/`html_url` into
// `downloadUrl`/`htmlUrl` instead of the Swift-idiomatic `downloadURL`/`htmlURL`).

struct GitHubRepoInfo: Decodable, Sendable {
    let defaultBranch: String
    enum CodingKeys: String, CodingKey { case defaultBranch = "default_branch" }
}

struct GitHubContentEntry: Decodable, Sendable {
    let name: String
    let type: String
    let downloadURL: URL?
    enum CodingKeys: String, CodingKey {
        case name, type
        case downloadURL = "download_url"
    }
}

struct GitHubFileContent: Decodable, Sendable {
    let content: String
    let encoding: String
}

struct GitHubRefObject: Decodable, Sendable {
    let sha: String
}

struct GitHubRef: Decodable, Sendable {
    let object: GitHubRefObject
}

struct GitHubCommitObject: Decodable, Sendable {
    let tree: GitHubRefObject
}

struct GitHubPullRequest: Decodable, Sendable {
    let number: Int
    let htmlURL: URL
    enum CodingKeys: String, CodingKey {
        case number
        case htmlURL = "html_url"
    }
}

private struct CreateBlobRequest: Encodable {
    let content: String
    let encoding: String
}

private struct CreateTreeRequest: Encodable {
    struct Entry: Encodable {
        let path: String
        let mode: String
        let type: String
        let sha: String
    }
    let baseTree: String
    let tree: [Entry]
    enum CodingKeys: String, CodingKey {
        case baseTree = "base_tree"
        case tree
    }
}

private struct CreateCommitRequest: Encodable {
    let message: String
    let tree: String
    let parents: [String]
}

private struct CreateRefRequest: Encodable {
    let ref: String
    let sha: String
}

private struct UpdateRefRequest: Encodable {
    let sha: String
}

private struct CreatePullRequestRequest: Encodable {
    let title: String
    let head: String
    let base: String
    let body: String
}

// MARK: - Client

/// A thin, purpose-built GitHub REST API client — every call needed by pull/commit/open
/// PR, built on NetworkTools' `HTTPClient` (already `ReactiveConcurrency`-native). Every
/// method throws `GitHubError` — the app's own domain error, never a raw `HTTPError`.
enum GitHubClient {
    private static let httpClient = HTTPClient.live(session: .shared)
    private static let jsonDecoder = JSONDecoder()

    static func repoInfo(_ settings: GitHubSettings, repo: GitHubRepository) async throws(GitHubError) -> GitHubRepoInfo {
        try await call("repos/\(repo.owner)/\(repo.name)", settings: settings)
    }

    static func listArticles(
        _ settings: GitHubSettings,
        repo: GitHubRepository
    ) async throws(GitHubError) -> [GitHubContentEntry] {
        try await call(
            "repos/\(repo.owner)/\(repo.name)/contents/Articles",
            settings: settings,
            query: ["ref": settings.baseBranch]
        )
    }

    /// The raw bytes at a (pre-signed) `download_url` — no GitHub auth headers, different
    /// host (`raw.githubusercontent.com`), the signature in the URL already grants access.
    static func downloadRaw(_ url: URL) async throws(GitHubError) -> Data {
        let request = URLRequest(url: url)
        guard let result = await httpClient(request).validateStatusCode().firstResult() else {
            throw .network("no response")
        }
        switch result {
        case .success(let data): return data
        case .failure(let error): throw mapHTTPError(error)
        }
    }

    /// The current file content + sha at `path` on the base branch — `nil` if it doesn't
    /// exist there yet (a 404 is a normal, expected outcome here, not an error).
    static func fileContent(
        _ settings: GitHubSettings,
        repo: GitHubRepository,
        path: String
    ) async throws(GitHubError) -> Data? {
        let content: GitHubFileContent? = try await callOptional(
            "repos/\(repo.owner)/\(repo.name)/contents/\(path)",
            settings: settings,
            query: ["ref": settings.baseBranch]
        )
        guard let content else { return nil }
        guard let data = Data(base64Encoded: content.content, options: .ignoreUnknownCharacters) else {
            throw .decoding("couldn't base64-decode \(path)")
        }
        return data
    }

    static func branchTipSHA(
        _ settings: GitHubSettings,
        repo: GitHubRepository,
        branch: String
    ) async throws(GitHubError) -> String? {
        let ref: GitHubRef? = try await callOptional("repos/\(repo.owner)/\(repo.name)/git/ref/heads/\(branch)", settings: settings)
        return ref?.object.sha
    }

    static func createBranch(
        _ settings: GitHubSettings,
        repo: GitHubRepository,
        branch: String,
        atSHA sha: String
    ) async throws(GitHubError) {
        let body = CreateRefRequest(ref: "refs/heads/\(branch)", sha: sha)
        let _: GitHubRef = try await call(
            "repos/\(repo.owner)/\(repo.name)/git/refs",
            settings: settings,
            method: "POST",
            body: body
        )
    }

    static func baseTreeSHA(_ settings: GitHubSettings, repo: GitHubRepository, commitSHA: String) async throws(GitHubError) -> String {
        let commit: GitHubCommitObject = try await call("repos/\(repo.owner)/\(repo.name)/git/commits/\(commitSHA)", settings: settings)
        return commit.tree.sha
    }

    static func createBlob(_ settings: GitHubSettings, repo: GitHubRepository, content: Data) async throws(GitHubError) -> String {
        let body = CreateBlobRequest(content: content.base64EncodedString(), encoding: "base64")
        let blob: GitHubRefObject = try await call(
            "repos/\(repo.owner)/\(repo.name)/git/blobs",
            settings: settings,
            method: "POST",
            body: body
        )
        return blob.sha
    }

    static func createTree(
        _ settings: GitHubSettings,
        repo: GitHubRepository,
        baseTreeSHA: String,
        entries: [(path: String, blobSHA: String)]
    ) async throws(GitHubError) -> String {
        let body = CreateTreeRequest(
            baseTree: baseTreeSHA,
            tree: entries.map { CreateTreeRequest.Entry(path: $0.path, mode: "100644", type: "blob", sha: $0.blobSHA) }
        )
        let tree: GitHubRefObject = try await call(
            "repos/\(repo.owner)/\(repo.name)/git/trees",
            settings: settings,
            method: "POST",
            body: body
        )
        return tree.sha
    }

    static func createCommit(
        _ settings: GitHubSettings,
        repo: GitHubRepository,
        message: String,
        treeSHA: String,
        parentSHA: String
    ) async throws(GitHubError) -> String {
        let body = CreateCommitRequest(message: message, tree: treeSHA, parents: [parentSHA])
        let commit: GitHubRefObject = try await call(
            "repos/\(repo.owner)/\(repo.name)/git/commits",
            settings: settings,
            method: "POST",
            body: body
        )
        return commit.sha
    }

    static func updateBranchRef(
        _ settings: GitHubSettings,
        repo: GitHubRepository,
        branch: String,
        toSHA sha: String
    ) async throws(GitHubError) {
        let body = UpdateRefRequest(sha: sha)
        let _: GitHubRef = try await call(
            "repos/\(repo.owner)/\(repo.name)/git/refs/heads/\(branch)",
            settings: settings,
            method: "PATCH",
            body: body
        )
    }

    /// An already-open PR for `branch`, if one exists — checked first so opening a PR is
    /// idempotent (re-running it just returns the existing PR instead of erroring).
    static func existingPullRequest(
        _ settings: GitHubSettings,
        repo: GitHubRepository,
        branch: String
    ) async throws(GitHubError) -> GitHubPullRequest? {
        let prs: [GitHubPullRequest] = try await call(
            "repos/\(repo.owner)/\(repo.name)/pulls",
            settings: settings,
            query: ["head": "\(repo.owner):\(branch)", "state": "open"]
        )
        return prs.first
    }

    /// The head branch and the PR's title/body all come from `request` — the push's own
    /// feature branch — and `base` is the configured base branch. Keeping the two sides
    /// separate is the point: reading both off `settings` is what made every PR fail with
    /// a 422, since the one configured branch was being passed as head *and* base.
    static func createPullRequest(
        _ settings: GitHubSettings,
        repo: GitHubRepository,
        request: PushRequest,
        base: String
    ) async throws(GitHubError) -> GitHubPullRequest {
        let requestBody = CreatePullRequestRequest(
            title: request.prTitle,
            head: request.branch,
            base: base,
            body: request.prBody
        )
        return try await call(
            "repos/\(repo.owner)/\(repo.name)/pulls",
            settings: settings,
            method: "POST",
            body: requestBody
        )
    }

    // MARK: - Request plumbing

    private static func call<Response: Decodable & Sendable>(
        _ path: String,
        settings: GitHubSettings,
        method: String = "GET",
        query: [String: String] = [:]
    ) async throws(GitHubError) -> Response {
        try await call(path, settings: settings, method: method, query: query, bodyData: nil)
    }

    private static func call<Response: Decodable & Sendable, Body: Encodable>(
        _ path: String,
        settings: GitHubSettings,
        method: String,
        body: Body
    ) async throws(GitHubError) -> Response {
        guard let bodyData = try? JSONEncoder().encode(body) else { throw .decoding("couldn't encode request body") }
        return try await call(path, settings: settings, method: method, query: [:], bodyData: bodyData)
    }

    /// `nil` on a 404, since several call sites (does this file/branch/PR exist yet?)
    /// treat "not found" as a normal, expected outcome rather than a failure.
    private static func callOptional<Response: Decodable & Sendable>(
        _ path: String,
        settings: GitHubSettings,
        query: [String: String] = [:]
    ) async throws(GitHubError) -> Response? {
        do {
            return try await call(path, settings: settings, query: query) as Response
        } catch GitHubError.badStatus(404) {
            return nil
        }
    }

    private static func call<Response: Decodable & Sendable>(
        _ path: String,
        settings: GitHubSettings,
        method: String,
        query: [String: String],
        bodyData: Data?
    ) async throws(GitHubError) -> Response {
        guard var components = URLComponents(string: "https://api.github.com/\(path)") else { throw .invalidRepoURL }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw .invalidRepoURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(settings.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        guard let result = await httpClient(request).validateStatusCode().decode(using: jsonDecoder, type: Response.self).firstResult()
        else {
            throw .network("no response")
        }
        switch result {
        case .success(let value): return value
        case .failure(let error): throw mapHTTPError(error)
        }
    }

    private static func mapHTTPError(_ error: HTTPError) -> GitHubError {
        switch error {
        case .network(let underlying): .network(underlying.localizedDescription)
        case .badStatus(let code, _): .badStatus(code)
        case .decoding(let underlying): .decoding(underlying.localizedDescription)
        }
    }
}
