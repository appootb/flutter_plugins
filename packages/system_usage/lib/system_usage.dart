import 'src/models.dart';
import 'system_usage_platform_interface.dart';

/// Types of system resources that can be included in a snapshot.
enum ResourceType { cpu, gpu, npu, memory, disk, network }

class SystemUsage {
  Future<String?> getPlatformVersion() {
    return SystemUsagePlatform.instance.getPlatformVersion();
  }

  /// Get a snapshot of system usage.
  ///
  /// If [includes] is provided, only the specified resources will be populated
  /// in the returned [SystemSnapshot] (other fields may be null or zeroed).
  Future<SystemSnapshot?> getSnapshot({List<ResourceType>? includes}) async {
    final includeNames = includes?.map((e) => e.name).toList(growable: false);
    final json = await SystemUsagePlatform.instance.getSnapshot(
      includes: includeNames,
    );
    if (json == null) return null;
    final full = SystemSnapshot.fromJson(json);

    // No filtering requested.
    if (includes == null || includes.isEmpty) {
      return full;
    }

    final should = includes.toSet();
    final keepCpu = should.contains(ResourceType.cpu);
    final keepMem = should.contains(ResourceType.memory);
    final keepGpu = should.contains(ResourceType.gpu);

    return SystemSnapshot(
      timestampMs: full.timestampMs,
      cpu: keepCpu
          ? full.cpu
          : CpuInfo(coreCount: full.cpu.coreCount, usage: 0),
      memory: keepMem
          ? full.memory
          : MemoryInfo(
              totalBytes: full.memory.totalBytes,
              usedBytes: 0,
              freeBytes: 0,
              wiredBytes: 0,
            ),
      gpu: keepGpu ? full.gpu : null,
    );
  }

  /// Watch system usage snapshots as a stream.
  ///
  /// If [includes] is provided, only those resources will be populated
  /// in each emitted snapshot.
  Stream<SystemSnapshot> watch({
    Duration interval = const Duration(seconds: 1),
    List<ResourceType>? includes,
  }) async* {
    while (true) {
      final snap = await getSnapshot(includes: includes);
      if (snap != null) yield snap;
      await Future<void>.delayed(interval);
    }
  }
}
