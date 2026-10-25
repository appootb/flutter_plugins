import Cocoa
import FlutterMacOS
import Foundation
import IOKit
import IOKit.graphics

public class SystemUsagePlugin: NSObject, FlutterPlugin {
    // CPU tick snapshots for usage calculation.
    private var prevCpuInfo: processor_info_array_t?
    private var prevCpuInfoCount: mach_msg_type_number_t = 0
    private var prevCpuCount: natural_t = 0

    // Cached readings with a short TTL to avoid excessive system calls.
    private var lastCpu: CpuReadResult?
    private var lastCpuTimestamp: TimeInterval = 0

    private var lastMemory: MemoryReadResult?
    private var lastMemoryTimestamp: TimeInterval = 0

    private var lastGpu: GpuReadResult?
    private var lastGpuTimestamp: TimeInterval = 0

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "system_usage", binaryMessenger: registrar.messenger)
        let instance = SystemUsagePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
        case "getSnapshot":
            let args = call.arguments as? [String: Any]
            let includes = (args?["includes"] as? [String]) ?? []
            result(buildSnapshot(includes: includes))
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func buildSnapshot(includes: [String]) -> [String: Any] {
        let now = Date().timeIntervalSince1970
        let nowMs = Int(now * 1000.0)

        // TTL for cached readings (in seconds).
        let cacheTtl: TimeInterval = 0.5

        let includeSet = Set(includes)
        let wantCpu = includes.isEmpty || includeSet.contains("cpu")
        let wantMem = includes.isEmpty || includeSet.contains("memory")
        let wantGpu = includes.isEmpty || includeSet.contains("gpu")

        let cpu: CpuReadResult
        if wantCpu {
            if let cached = lastCpu, now - lastCpuTimestamp < cacheTtl {
                cpu = cached
            } else {
                let current = readCpu()
                lastCpu = current
                lastCpuTimestamp = now
                cpu = current
            }
        } else {
            cpu = CpuReadResult(coreCount: 0, usage: 0)
        }

        let memory: MemoryReadResult
        if wantMem {
            if let cached = lastMemory, now - lastMemoryTimestamp < cacheTtl {
                memory = cached
            } else {
                let current = readMemory()
                lastMemory = current
                lastMemoryTimestamp = now
                memory = current
            }
        } else {
            memory = MemoryReadResult(
                totalBytes: 0,
                usedBytes: 0,
                freeBytes: 0,
                wiredBytes: 0
            )
        }

        let gpu: GpuReadResult?
        if wantGpu {
            if let cached = lastGpu, now - lastGpuTimestamp < cacheTtl {
                gpu = cached
            } else {
                let current = readGpu()
                lastGpu = current
                lastGpuTimestamp = now
                gpu = current
            }
        } else {
            gpu = nil
        }

        // GPU utilization is not reliably available via public APIs on macOS.
        // Return nil to indicate "not available" for now.
        var snapshot: [String: Any] = [
            "timestampMs": nowMs,
            "cpu": [
                "coreCount": cpu.coreCount,
                "usage": cpu.usage,
            ],
            "memory": [
                "totalBytes": memory.totalBytes,
                "usedBytes": memory.usedBytes,
                "freeBytes": memory.freeBytes,
                "wiredBytes": memory.wiredBytes,
            ],
        ]
        if let gpu = gpu {
            var gpuDict: [String: Any] = [
                "usage": gpu.usage
            ]
            if let used = gpu.vramUsedBytes {
                gpuDict["vramUsedBytes"] = used
            }
            if let total = gpu.vramTotalBytes {
                gpuDict["vramTotalBytes"] = total
            }
            snapshot["gpu"] = gpuDict
        }
        return snapshot
    }

    private struct CpuReadResult {
        let coreCount: Int
        let usage: Double
    }

    private func readCpu() -> CpuReadResult {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0

        let kr = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &cpuInfo, &cpuInfoCount)
        guard kr == KERN_SUCCESS, let cpuInfo = cpuInfo else {
            return CpuReadResult(coreCount: Int(ProcessInfo.processInfo.processorCount), usage: 0.0)
        }

        defer {
            // Keep current snapshot as previous for next delta.
            if let prev = prevCpuInfo {
                let prevSize = Int(prevCpuInfoCount) * MemoryLayout<integer_t>.stride
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), vm_size_t(prevSize))
            }
            prevCpuInfo = cpuInfo
            prevCpuInfoCount = cpuInfoCount
            prevCpuCount = cpuCount
        }

        // If no previous snapshot, we can't compute a delta reliably yet.
        guard let prevCpuInfo = prevCpuInfo, prevCpuCount == cpuCount else {
            return CpuReadResult(coreCount: Int(cpuCount), usage: 0.0)
        }

        let cpuLoadInfoCount = Int(CPU_STATE_MAX)
        var totalTicks: Double = 0
        var usedTicks: Double = 0
        let userIdx = Int(CPU_STATE_USER)
        let systemIdx = Int(CPU_STATE_SYSTEM)
        let niceIdx = Int(CPU_STATE_NICE)
        let idleIdx = Int(CPU_STATE_IDLE)

        for i in 0..<Int(cpuCount) {
            let idx = i * cpuLoadInfoCount

            let user = Double(cpuInfo[idx + userIdx] - prevCpuInfo[idx + userIdx])
            let system = Double(cpuInfo[idx + systemIdx] - prevCpuInfo[idx + systemIdx])
            let nice = Double(cpuInfo[idx + niceIdx] - prevCpuInfo[idx + niceIdx])
            let idle = Double(cpuInfo[idx + idleIdx] - prevCpuInfo[idx + idleIdx])

            let coreTotal = user + system + nice + idle
            let coreUsed = user + system + nice

            totalTicks += coreTotal
            usedTicks += coreUsed
        }

        let usage = totalTicks > 0 ? max(0.0, min(1.0, usedTicks / totalTicks)) : 0.0
        return CpuReadResult(coreCount: Int(cpuCount), usage: usage)
    }

    private struct MemoryReadResult {
        let totalBytes: Int64
        let usedBytes: Int64
        let freeBytes: Int64
        let wiredBytes: Int64
    }

    private struct GpuReadResult {
        let usage: Double
        let vramUsedBytes: Int64?
        let vramTotalBytes: Int64?
    }

    private func readMemory() -> MemoryReadResult {
        let total = readTotalMemoryBytes()

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout.size(ofValue: stats) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        if result != KERN_SUCCESS {
            return MemoryReadResult(totalBytes: total, usedBytes: 0, freeBytes: 0, wiredBytes: 0)
        }

        let ps = Int64(pageSize)
        let free = Int64(stats.free_count) * ps
        let wired = Int64(stats.wire_count) * ps
        let active = Int64(stats.active_count) * ps
        let compressed = Int64(stats.compressor_page_count) * ps
        let purgeable = Int64(stats.purgeable_count) * ps

        // Approximate App Memory + Wired + Compressed:
        // - Do NOT count inactive as used (it's cache and quickly reclaimable)
        // - Subtract purgeable memory, which the system can reclaim at any time
        var used = active + wired + compressed - purgeable
        if used < 0 { used = 0 }
        if used > total { used = total }

        return MemoryReadResult(
            totalBytes: total,
            usedBytes: used,
            freeBytes: free,
            wiredBytes: wired
        )
    }

    private func readTotalMemoryBytes() -> Int64 {
        var size: Int64 = 0
        var len = MemoryLayout<Int64>.size
        let r = sysctlbyname("hw.memsize", &size, &len, nil, 0)
        if r == 0 {
            return size
        }
        return Int64(ProcessInfo.processInfo.physicalMemory)
    }

    // Attempt to read GPU utilization and VRAM usage via IOKit PerformanceStatistics.
    // This relies on implementation details of IOAccelerator/AGXAccelerator and may
    // not be available on all hardware/OS combinations.
    private func readGpu() -> GpuReadResult? {
        let serviceClasses = ["AGXAccelerator", "IOAccelerator"]

        for name in serviceClasses {
            if let result = readGpuForService(named: name) {
                return result
            }
        }

        return nil
    }

    private func readGpuForService(named name: String) -> GpuReadResult? {
        guard let matching = IOServiceMatching(name) else {
            return nil
        }

        var iterator: io_iterator_t = 0
        let masterPort: mach_port_t
        if #available(macOS 12.0, *) {
            masterPort = kIOMainPortDefault
        } else {
            // Deprecated on newer macOS but still available for older systems.
            masterPort = kIOMasterPortDefault
        }
        let kr = IOServiceGetMatchingServices(masterPort, matching, &iterator)
        if kr != KERN_SUCCESS {
            return nil
        }

        defer {
            IOObjectRelease(iterator)
        }

        var service: io_object_t = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service) }

            var props: Unmanaged<CFMutableDictionary>?
            let propsKr = IORegistryEntryCreateCFProperties(
                service,
                &props,
                kCFAllocatorDefault,
                0
            )
            guard propsKr == KERN_SUCCESS,
                let cfProps = props?.takeRetainedValue() as? [String: Any]
            else {
                service = IOIteratorNext(iterator)
                continue
            }

            if let perf = cfProps["PerformanceStatistics"] as? [String: Any] {
                var usage: Double?
                if let v = perf["Device Utilization %"] as? NSNumber {
                    usage = v.doubleValue / 100.0
                } else if let v = perf["GPU Activity(%)"] as? NSNumber {
                    usage = v.doubleValue / 100.0
                }

                let used = (perf["vramUsedBytes"] as? NSNumber)?.int64Value
                let total = (perf["vramTotalBytes"] as? NSNumber)?.int64Value

                if let usage = usage {
                    let clamped = max(0.0, min(1.0, usage))
                    return GpuReadResult(usage: clamped, vramUsedBytes: used, vramTotalBytes: total)
                }
            }

            service = IOIteratorNext(iterator)
        }

        return nil
    }
}
