import Foundation

/// One article's bytes, named by its filename inside `Articles/`. Shared by both directions
/// of sync: a ``PullPreview`` carries the remote bytes it would write locally, a
/// ``PushPreview`` the local bytes it would send to GitHub. Same shape, same meaning —
/// one type rather than two identical nested ones.
public struct SyncFileChange: Equatable, Sendable {
    public let name: String
    public let content: Data

    public init(name: String, content: Data) {
        self.name = name
        self.content = content
    }
}
