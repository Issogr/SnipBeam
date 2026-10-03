import AppKit

@MainActor
final class MenuBarController: NSObject {
    var onSelect: (() -> Void)?
    var onPause: (() -> Void)?
    var onCursor: (() -> Void)?
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let selectItem = NSMenuItem(title: "Select Region…", action: #selector(selectRegion), keyEquivalent: "s")
    private let pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")
    private let cursorItem = NSMenuItem(title: "Show Cursor", action: #selector(toggleCursor), keyEquivalent: "")

    override init() {
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "SnipBeam")
        statusItem.button?.toolTip = "SnipBeam — share a screen region"
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in [selectItem, pauseItem, cursorItem] {
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit SnipBeam", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        statusItem.menu = menu

        // A standard app menu also makes Command-Q work while the preview is key.
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "SnipBeam")
        appMenu.addItem(withTitle: "Quit SnipBeam", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }

    func update(state: CaptureState, busy: Bool, showsCursor: Bool) {
        selectItem.isEnabled = !busy && !state.isSelecting
        pauseItem.title = state.isPaused ? "Resume" : "Pause"
        pauseItem.isEnabled = !busy && state.region != nil
        cursorItem.state = showsCursor ? .on : .off
        cursorItem.isEnabled = !busy && !state.isSelecting
    }

    @objc private func selectRegion() { onSelect?() }
    @objc private func togglePause() { onPause?() }
    @objc private func toggleCursor() { onCursor?() }
}
