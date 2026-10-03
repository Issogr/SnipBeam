import Foundation

enum ResourceMeasurement {
    private static func usage() throws -> (cpuSeconds: Double, footprint: UInt64) {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V2, $0)
            }
        }
        var cpu = rusage()
        guard result == 0, getrusage(RUSAGE_SELF, &cpu) == 0 else {
            throw CaptureError.message("Could not read process resource usage.")
        }
        // getrusage uses seconds/microseconds; proc_pid_rusage CPU fields use platform-dependent Mach ticks.
        let seconds = Double(cpu.ru_utime.tv_sec + cpu.ru_stime.tv_sec)
            + Double(cpu.ru_utime.tv_usec + cpu.ru_stime.tv_usec) / 1_000_000
        return (seconds, info.ri_phys_footprint)
    }

    // Opt-in diagnostic only; no sampling timer runs in normal use.
    static func measure(_ label: String, renderer: FrameRenderer? = nil) async throws {
        try await Task.sleep(for: .seconds(1))
        let beforeFrames = await renderer?.statistics().presented ?? 0
        let before = try usage()
        let start = ProcessInfo.processInfo.systemUptime
        try await Task.sleep(for: .seconds(5))
        let end = ProcessInfo.processInfo.systemUptime
        let after = try usage()
        let afterFrames = await renderer?.statistics().presented ?? 0
        let cpuSeconds = after.cpuSeconds - before.cpuSeconds
        print(String(format: "PROFILE %@: CPU %.2f%% of one core, footprint %.1f MiB, %.1f presentations/s",
                     label, cpuSeconds / (end - start) * 100, Double(after.footprint) / 1_048_576,
                     Double(afterFrames - beforeFrames) / (end - start)))
    }
}
