import AppKit
import SwiftUI


//ariz salamm

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    let store: AppStore

    init(store: AppStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        super.init()

        store.onClosePopover = { [weak self] in
            self?.closePopover()
        }

        configureStatusItem()
        configurePopover()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        if let image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Check") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "CP"
        }

        button.toolTip = "Check"
        button.action = #selector(togglePopover(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.contentSize = NSSize(width: 390, height: 560)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PanelView(store: store)
                .frame(width: 390)
        )
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            closePopover()
            return
        }

        Task {
            await store.refreshProjectAccess()
            await store.refreshLiveGit(includeDiff: false)
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() {
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        Task { await store.persist() }
    }
}
