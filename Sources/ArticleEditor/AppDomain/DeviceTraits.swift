import Foundation

/// What the screen the app is on is like: the facts a layout depends on, as values.
///
/// They come from the world (`World.deviceTraits`), are kept in state, and reach a view only as
/// what its projection makes of them. No view asks the device: a view is what its state says.
public struct DeviceTraits: Sendable, Equatable, Hashable {
    /// Drawn dark: the appearance the system reports.
    public var isDark: Bool
    /// A narrow width (a phone, a pad in a small split): one stack rather than two columns.
    public var isCompactWidth: Bool

    public init(isDark: Bool, isCompactWidth: Bool) {
        self.isDark = isDark
        self.isCompactWidth = isCompactWidth
    }

    /// Before the world has said anything: light and wide, what the first frame draws in until
    /// the first report arrives a moment later.
    public static let initial = DeviceTraits(isDark: false, isCompactWidth: false)
}

/// Where the app is in its life: in front, half there, or gone.
public enum AppPhase: Sendable, Equatable, Hashable {
    case active
    case inactive
    case background
}
