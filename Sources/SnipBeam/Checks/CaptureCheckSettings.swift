import Foundation

enum CaptureCheckSettings {
    static var requested: Bool {
        CommandLine.arguments.contains("--smoke-test") || CommandLine.arguments.contains("--performance-test")
    }

    static var preferencesDomain: String { "com.example.SnipBeam.checks.\(ProcessInfo.processInfo.processIdentifier)" }

    static func preferences() -> UserDefaults {
        let defaults = UserDefaults(suiteName: preferencesDomain)!
        defaults.removePersistentDomain(forName: preferencesDomain)
        return defaults
    }

    static func timeout(profiling: Bool, displayCount: Int) -> TimeInterval {
        30 + Double(max(1, displayCount)) * (profiling ? 90 : 60)
    }
}
