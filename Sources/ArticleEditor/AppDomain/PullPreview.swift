import Foundation

/// What a pull from GitHub *would* do, computed before anything is written to disk —
/// carries the already-downloaded bytes so confirming doesn't re-fetch them.
public struct PullPreview: Equatable, Sendable {
    public struct FileChange: Equatable, Sendable {
        public let name: String
        public let content: Data

        public init(name: String, content: Data) {
            self.name = name
            self.content = content
        }
    }

    public var toAdd: [FileChange]
    public var toUpdate: [FileChange]
    /// Filenames whose *local* bytes differ from what's about to be pulled — applying
    /// the pull would silently discard these. Drives the confirmation dialog.
    public var localOnlyChanges: [String]

    public init(toAdd: [FileChange], toUpdate: [FileChange], localOnlyChanges: [String]) {
        self.toAdd = toAdd
        self.toUpdate = toUpdate
        self.localOnlyChanges = localOnlyChanges
    }
}
