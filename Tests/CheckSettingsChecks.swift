import Foundation

@main
enum CheckSettingsChecks {
    static func main() throws {
        if CommandLine.arguments.contains("--abort-with-check-preferences") {
            let preferences = CaptureCheckSettings.preferences()
            preferences.set([], forKey: "hiddenAppBundleIDs")
            preferences.set(false, forKey: "showsCursor")
            preferences.synchronize()
            exit(17) // Deliberately bypass cleanup, as a timeout or crash would.
        }

        let defaults = UserDefaults.standard
        let domain = ProcessInfo.processInfo.processName
        let saved = defaults.persistentDomain(forName: domain)
        defer { defaults.setPersistentDomain(saved ?? [:], forName: domain) }
        defaults.set(["private.app"], forKey: "hiddenAppBundleIDs")
        defaults.set(true, forKey: "showsCursor")
        defaults.synchronize()
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--abort-with-check-preferences"]
        try child.run()
        child.waitUntilExit()
        defaults.synchronize()
        defaults.removePersistentDomain(forName: "com.example.SnipBeam.checks.\(child.processIdentifier)")
        assert(child.terminationStatus == 17)
        assert(defaults.stringArray(forKey: "hiddenAppBundleIDs") == ["private.app"])
        assert(defaults.bool(forKey: "showsCursor"))

        for displays in [1, 4, 8] {
            let mandatorySleeps = 12 + 27.1 * Double(displays)
            assert(CaptureCheckSettings.timeout(profiling: true, displayCount: displays) > mandatorySleeps + 10)
        }
        assert(CaptureCheckSettings.timeout(profiling: false, displayCount: 0) > 0)
        print("PASS: abrupt test exit preserves normal preferences; multi-display deadlines have startup headroom")
    }
}
