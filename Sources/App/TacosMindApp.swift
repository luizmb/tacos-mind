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
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif

    init() {
        store = MainStore.app(world: world)
        #if os(macOS)
        appDelegate.store = store
        #endif
    }

    var body: some Scene {
        AppScene.scene(store: store, world: world)
            #if os(iOS)
            // iOS gives apps no way to block termination — backgrounding is the closest
            // signal we get, so it's the only real protection available there. The
            // decision (save only if there are unsaved changes) lives in
            // ArticleEditorFeature's own reducer, not here.
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .background else { return }
                store.dispatch(.articleEditor(.appDidEnterBackground))
            }
            #endif
    }
}
