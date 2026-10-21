import AppDomain
import Foundation
import ReactiveConcurrency
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// The screen's traits and the app's life, from the system's notifications and callbacks, as
// publishers of pure values. **Cold**, like every factory behind `World`: observers are made when a
// subscription starts and dropped when it ends.

#if os(iOS)
/// The traits of the window scene in front: seeded from the scenes already connected, then
/// whichever activates, following each one's appearance and width class while it is the latest.
func makeDeviceTraitsStream() -> Publisher<DeviceTraits, Never> {
    NotificationCenter.default
        .notifications(named: UIScene.didActivateNotification) { $0.object as? UIWindowScene }
        .compactMap { $0 }
        .prepend(connectedScenes())
        .map(traits(of:))
        .switchToLatest()
        .removeDuplicates()
}

/// The app's life: where it is now, then each move the application reports.
func makeAppPhaseStream() -> Publisher<AppPhase, Never> {
    Publisher<AppPhase, Never>
        .merge([
            NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification).map { AppPhase.active },
            NotificationCenter.default.notifications(named: UIApplication.willResignActiveNotification).map { AppPhase.inactive },
            NotificationCenter.default.notifications(named: UIApplication.willEnterForegroundNotification).map { AppPhase.inactive },
            NotificationCenter.default.notifications(named: UIApplication.didEnterBackgroundNotification).map { AppPhase.background },
        ])
        .prepend(Publisher { continuation in
            continuation.yield(await MainActor.run { AppPhase(UIApplication.shared.applicationState) })
        })
}

/// The window scenes connected when the subscription starts.
private func connectedScenes() -> Publisher<UIWindowScene, Never> {
    Publisher { continuation in
        await MainActor.run { UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene } }
            .forEach(continuation.yield)
    }
}

/// One scene's traits: what it has now, then every change UIKit reports, until unsubscribed.
/// UIKit posts no notification for a trait change, so this is the one callback bridge.
private func traits(of scene: UIWindowScene) -> Publisher<DeviceTraits, Never> {
    // On the main actor throughout: the scene and its registration live there, and waiting is an
    // `await`, so it holds nothing up.
    Publisher { @MainActor continuation in
        continuation.yield(DeviceTraits(scene.traitCollection))
        let registration = scene.registerForTraitChanges(
            [UITraitUserInterfaceStyle.self, UITraitHorizontalSizeClass.self]
        ) { (scene: UIWindowScene, _: UITraitCollection) in
            continuation.yield(DeviceTraits(scene.traitCollection))
        }
        await continuation.suspendUntilCancelled()
        scene.unregisterForTraitChanges(registration)
    }
}

private extension DeviceTraits {
    init(_ traits: UITraitCollection) {
        self.init(isDark: traits.userInterfaceStyle == .dark, isCompactWidth: traits.horizontalSizeClass == .compact)
    }
}

private extension AppPhase {
    init(_ state: UIApplication.State) {
        self = switch state {
        case .active: .active
        case .inactive: .inactive
        case .background: .background
        @unknown default: .active
        }
    }
}
#elseif os(macOS)
/// The app's appearance: what it is now, then again each time the system's theme changes. A Mac
/// window is never a phone's width.
func makeDeviceTraitsStream() -> Publisher<DeviceTraits, Never> {
    DistributedNotificationCenter.default()
        .notifications(named: Notification.Name("AppleInterfaceThemeChangedNotification"))
        .prepend(())
        .flatMap { _ in currentTraits() }
        .removeDuplicates()
}

/// The app's life: in front or not, as the application reports it. A Mac app is not sent to the
/// background.
func makeAppPhaseStream() -> Publisher<AppPhase, Never> {
    Publisher<AppPhase, Never>
        .merge([
            NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification).map { AppPhase.active },
            NotificationCenter.default.notifications(named: NSApplication.didResignActiveNotification).map { AppPhase.inactive },
        ])
        .prepend(Publisher { continuation in
            continuation.yield(await MainActor.run { NSApplication.shared.isActive ? AppPhase.active : .inactive })
        })
}

/// The application's effective appearance, read where it lives.
private func currentTraits() -> Publisher<DeviceTraits, Never> {
    Publisher { continuation in
        continuation.yield(await MainActor.run {
            DeviceTraits(
                isDark: NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
                isCompactWidth: false
            )
        })
    }
}
#else
/// No screen to watch (the Linux build): light and wide.
func makeDeviceTraitsStream() -> Publisher<DeviceTraits, Never> {
    .just(.initial)
}

func makeAppPhaseStream() -> Publisher<AppPhase, Never> {
    .just(.active)
}
#endif
