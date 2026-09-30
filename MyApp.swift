import AppKit
import SwiftUI

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

    // salam azerbaycan
    // ariz oglan deyil

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    let store = AppStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController(store: store)

        Task {
            await store.bootstrap(checkpointBundleID: Bundle.main.bundleIdentifier)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.handleAppTermination()
        BookmarkManager.shared.stopAllAccess()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
