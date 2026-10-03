import AppKit

@MainActor
enum ScreenRecordingPermission {
    static func ensureAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        NSApp.activate(ignoringOtherApps: true)
        let explanation = NSAlert()
        explanation.messageText = "Allow Screen Recording for SnipBeam"
        explanation.informativeText = "SnipBeam captures the selected portion of your screen locally. Nothing is recorded or uploaded.\n\nmacOS calls this permission Screen Recording. It is required to show your selected region in a shareable window."
        explanation.addButton(withTitle: "Continue")
        explanation.addButton(withTitle: "Cancel")
        guard explanation.runModal() == .alertFirstButtonReturn else { return false }
        if CGRequestScreenCaptureAccess() { return true }

        while !CGPreflightScreenCaptureAccess() {
            let alert = NSAlert()
            alert.messageText = "Screen Recording permission is not enabled"
            alert.informativeText = "Enable SnipBeam in System Settings → Privacy & Security → Screen Recording (or Screen & System Audio Recording). Then choose Select Region again to retry. If macOS asks, quit and reopen SnipBeam."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Retry")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
                return false
            case .alertSecondButtonReturn: continue
            default: return false
            }
        }
        return true
    }
}
