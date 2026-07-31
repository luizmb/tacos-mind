import Foundation

public enum CommitOutcome: Equatable, Sendable {
    case nothingToCommit
    case committed(files: [String], commitURL: URL)
}
