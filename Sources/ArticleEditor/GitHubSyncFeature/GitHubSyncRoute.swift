/// The screens reachable from inside the GitHub Sync sheet.
///
/// Payload-free, for the same reason ``AppRoute`` is: `NavigationStack` keys destinations
/// by element value, so a route says *which* screen and nothing about what it currently
/// shows. Both forms' inputs stay flat fields on `GitHubSyncFeature.State`, reset on the
/// push that opens them — they are forms, not features with their own lifetime, and
/// carrying them in the path element would buy nothing but an affine binding per text
/// field.
///
/// These were sheets until they weren't. Two `.sheet`s and two `.confirmationDialog`s
/// presented from one sheet is more presentation bookkeeping than SwiftUI reliably
/// tracks; pushing instead means the only modal left in this feature is a confirmation
/// dialog, which is what a confirmation dialog is for.
public enum GitHubSyncRoute: Hashable, Sendable, Codable {
    case link
    case editBranch
}
