import Foundation

/// The local articles a push would send, computed against the base branch before anything
/// is created on GitHub — carries the bytes so confirming doesn't re-read them off disk.
public struct PushPreview: Equatable, Sendable {
    public var files: [SyncFileChange]
    /// A date-stamped default like `articles/2026-08-05-1432`, stamped in `World` where
    /// the clock lives. It arrives here pre-computed so the reducer that seeds the push
    /// form stays pure — the rest of the form's defaults derive from `files` alone.
    public var suggestedBranch: String

    public init(files: [SyncFileChange], suggestedBranch: String) {
        self.files = files
        self.suggestedBranch = suggestedBranch
    }
}

/// The four things a push needs from the user, all pre-filled from a ``PushPreview``.
public struct PushRequest: Equatable, Sendable {
    public var branch: String
    public var commitMessage: String
    public var prTitle: String
    public var prBody: String

    public init(branch: String, commitMessage: String, prTitle: String, prBody: String) {
        self.branch = branch
        self.commitMessage = commitMessage
        self.prTitle = prTitle
        self.prBody = prBody
    }
}

/// A push never writes to the base branch: it commits to `branch` and opens (or reuses) a
/// pull request from there, so `prURL` is always present on success.
public enum PushOutcome: Equatable, Sendable {
    case nothingToPush
    case pushed(files: [String], branch: String, commitURL: URL, prURL: URL)
}
