import AppCore
import SwiftUI

#if os(macOS)
import AppKit

/// Translates AppKit's quit callback into a single dispatch — every actual decision
/// (show the "unsaved changes" alert, wait for a save, tell AppKit whether to proceed)
/// lives in `AppFeature`'s `quitBehavior()`. Always returns `.terminateLater`; the store
/// calls back into `World.completeTermination` once a decision is reached, whichever way.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: MainStoreType?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }
        store.dispatch(.quitRequested)
        return .terminateLater
    }

    // Installing a custom NSApplicationDelegate replaces SwiftUI's own implicit one —
    // without this override, AppKit's default is `false`, so clicking the window's close
    // button just closes the window (the app keeps running invisibly) instead of
    // actually terminating, and applicationShouldTerminate — our whole confirmation
    // flow — never runs at all. This makes closing the window go through the same path
    // as Cmd+Q.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#endif

@main
struct TacosMindApp: App {
    private let world = World.real
    private let store: MainStoreType
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        store = MainStore.app(world: world)
        #if os(macOS)
        appDelegate.store = store
        #endif
    }

    var body: some Scene {
        // The app's life and its screen's traits are the world's to report (`World.appPhases`,
        // `World.deviceTraits`), not this scene's to read; going to the background is handled in
        // `AppFeature`.
        AppScene.scene(store: store, world: world)
    }
}
