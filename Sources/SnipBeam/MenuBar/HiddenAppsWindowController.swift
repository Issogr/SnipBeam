import AppKit

@MainActor
final class HiddenAppsWindowController: NSWindowController {
    private final class AppList: NSStackView {
        override var isFlipped: Bool { true }
    }

    var onChange: ((String, Bool) -> Void)?
    private let appList = AppList()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 420),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Hidden Apps"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 320, height: 240)
        super.init(window: window)

        let explanation = NSTextField(wrappingLabelWithString:
            "Checked apps stay visible on your screen but are hidden from capture. Selections are saved; paused captures update when resumed.")
        explanation.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        appList.orientation = .vertical
        appList.alignment = .leading
        appList.spacing = 8
        appList.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        appList.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = appList

        let content = window.contentView!
        content.addSubview(explanation)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            explanation.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            explanation.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            explanation.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: explanation.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: explanation.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: explanation.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            appList.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            appList.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            appList.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func reloadApplications(hiddenBundleIDs: Set<String>, enabled: Bool) {
        var apps: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { continue }
            apps[id] = app.localizedName ?? id
        }
        // Keep saved selections available to uncheck even after an app quits.
        for id in hiddenBundleIDs where apps[id] == nil {
            let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent ?? id
            apps[id] = "\(name) (not running)"
        }
        for view in appList.arrangedSubviews { view.removeFromSuperview() }
        for (id, name) in apps.sorted(by: { $0.value.localizedStandardCompare($1.value) == .orderedAscending }) {
            let checkbox = NSButton(checkboxWithTitle: name, target: self, action: #selector(toggleApp(_:)))
            checkbox.identifier = NSUserInterfaceItemIdentifier(id)
            checkbox.toolTip = id
            checkbox.cell?.lineBreakMode = .byTruncatingTail
            appList.addArrangedSubview(checkbox)
            checkbox.widthAnchor.constraint(lessThanOrEqualTo: appList.widthAnchor, constant: -24).isActive = true
        }
        if apps.isEmpty { appList.addArrangedSubview(NSTextField(labelWithString: "Open an app to add it to this list.")) }
        update(hiddenBundleIDs: hiddenBundleIDs, enabled: enabled)
    }

    func update(hiddenBundleIDs: Set<String>, enabled: Bool) {
        for case let checkbox as NSButton in appList.arrangedSubviews {
            checkbox.state = hiddenBundleIDs.contains(checkbox.identifier!.rawValue) ? .on : .off
            checkbox.isEnabled = enabled
        }
    }

    @objc private func toggleApp(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        onChange?(id, sender.state == .on)
    }
}
