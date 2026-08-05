import Foundation

/// What a pull from GitHub *would* do, computed before anything is written to disk —
/// carries the already-downloaded bytes so applying it doesn't re-fetch them.
public struct PullPreview: Equatable, Sendable {
    /// Articles on GitHub with no local counterpart. Always safe to write: there is
    /// nothing local to lose.
    public var toAdd: [SyncFileChange]
    /// Articles that exist locally with *different* bytes — the remote version of each,
    /// held aside. Writing these would discard local edits, so the default pull skips
    /// them entirely (local wins) and only ``GitHubSyncFeature/Action/overwriteKeptLocal``
    /// applies them, using these very bytes rather than fetching again.
    public var toUpdate: [SyncFileChange]

    public init(toAdd: [SyncFileChange], toUpdate: [SyncFileChange]) {
        self.toAdd = toAdd
        self.toUpdate = toUpdate
    }
}

/// What a pull actually did. `keptLocal` is empty unless local edits were skipped, which
/// is what puts the "overwrite these with GitHub's version" affordance on screen.
public struct PullOutcome: Equatable, Sendable {
    public var applied: Int
    public var keptLocal: [String]

    public init(applied: Int, keptLocal: [String]) {
        self.applied = applied
        self.keptLocal = keptLocal
    }
}
