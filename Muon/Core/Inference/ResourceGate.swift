import Foundation
import IOKit.ps

struct GateResult {
    let ok: Bool
    let useSmall: Bool
    let reason: String?
}

/// Decides whether loading the tier-2 model is safe for the machine right now.
enum ResourceGate {
    static func check() -> GateResult {
        let pi = ProcessInfo.processInfo
        if pi.thermalState == .serious || pi.thermalState == .critical { return GateResult(ok: false, useSmall: false, reason: "Mac is running hot") }
        if pi.isLowPowerModeEnabled { return GateResult(ok: false, useSmall: false, reason: "Low Power Mode is on") }
        if let (onAC, pct) = battery(), !onAC, pct < 25 { return GateResult(ok: false, useSmall: false, reason: "battery at \(pct)% and unplugged") }
        let freeGB = availableMemoryGB()
        if freeGB < 3 { return GateResult(ok: false, useSmall: false, reason: String(format: "only %.1f GB memory available", freeGB)) }
        let heavy = runningHeavyJobs()
        if !heavy.isEmpty && freeGB < 5 { return GateResult(ok: false, useSmall: false, reason: "\(heavy.joined(separator: ", ")) running and memory is tight") }
        let small = freeGB < 7 || !heavy.isEmpty || pi.thermalState == .fair
        return GateResult(ok: true, useSmall: small, reason: small ? (heavy.isEmpty ? String(format: "%.1f GB free", freeGB) : "\(heavy.joined(separator: ", ")) running") : nil)
    }

    /// free + inactive + speculative pages, in GB.
    static func availableMemoryGB() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return 8 }
        let pages = Double(stats.free_count + stats.inactive_count + stats.speculative_count)
        return pages * Double(vm_kernel_page_size) / 1_073_741_824
    }

    static func battery() -> (onAC: Bool, percent: Int)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for src in list {
            guard let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any] else { continue }
            let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let pct = d[kIOPSCurrentCapacityKey] as? Int ?? 100
            return (onAC, pct)
        }
        return nil
    }

    static func runningHeavyJobs() -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-x", "xcodebuild|gradle|ffmpeg|swift-build|clang|ld"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        p.waitUntilExit()
        _ = pipe.fileHandleForReading.readDataToEndOfFile()
        guard p.terminationStatus == 0 else { return [] }
        let names = Process()
        names.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        names.arguments = ["-lx", "xcodebuild|gradle|ffmpeg|swift-build"]
        let np = Pipe(); names.standardOutput = np; names.standardError = FileHandle.nullDevice
        guard (try? names.run()) != nil else { return [] }
        names.waitUntilExit()
        let out = String(data: np.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Array(Set(out.split(separator: "\n").compactMap { $0.split(separator: " ").last.map(String.init) })).sorted()
    }
}
