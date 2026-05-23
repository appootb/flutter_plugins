class CpuInfo {
  final int coreCount;

  /// Total CPU usage in [0, 1].
  final double usage;

  const CpuInfo({required this.coreCount, required this.usage});

  factory CpuInfo.fromJson(Map<String, dynamic> json) {
    return CpuInfo(
      coreCount: (json['coreCount'] as num?)?.toInt() ?? 0,
      usage: (json['usage'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'coreCount': coreCount, 'usage': usage};
}

class MemoryInfo {
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final int wiredBytes;

  const MemoryInfo({
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
    required this.wiredBytes,
  });

  factory MemoryInfo.fromJson(Map<String, dynamic> json) {
    return MemoryInfo(
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      usedBytes: (json['usedBytes'] as num?)?.toInt() ?? 0,
      freeBytes: (json['freeBytes'] as num?)?.toInt() ?? 0,
      wiredBytes: (json['wiredBytes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'totalBytes': totalBytes,
    'usedBytes': usedBytes,
    'freeBytes': freeBytes,
    'wiredBytes': wiredBytes,
  };
}

class GpuInfo {
  /// GPU usage in [0, 1] if available.
  final double? usage;

  /// GPU memory used bytes if available.
  final int? vramUsedBytes;

  /// GPU memory total bytes if available.
  final int? vramTotalBytes;

  const GpuInfo({this.usage, this.vramUsedBytes, this.vramTotalBytes});

  factory GpuInfo.fromJson(Map<String, dynamic> json) {
    return GpuInfo(
      usage: (json['usage'] as num?)?.toDouble(),
      vramUsedBytes: (json['vramUsedBytes'] as num?)?.toInt(),
      vramTotalBytes: (json['vramTotalBytes'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (usage != null) 'usage': usage,
    if (vramUsedBytes != null) 'vramUsedBytes': vramUsedBytes,
    if (vramTotalBytes != null) 'vramTotalBytes': vramTotalBytes,
  };
}

class SystemSnapshot {
  final int timestampMs;
  final CpuInfo cpu;
  final MemoryInfo memory;
  final GpuInfo? gpu;

  const SystemSnapshot({
    required this.timestampMs,
    required this.cpu,
    required this.memory,
    this.gpu,
  });

  factory SystemSnapshot.fromJson(Map<String, dynamic> json) {
    final cpuJson = (json['cpu'] as Map?)?.cast<String, dynamic>() ?? const {};
    final memJson =
        (json['memory'] as Map?)?.cast<String, dynamic>() ?? const {};
    final gpuJson = (json['gpu'] as Map?)?.cast<String, dynamic>();

    return SystemSnapshot(
      timestampMs: (json['timestampMs'] as num?)?.toInt() ?? 0,
      cpu: CpuInfo.fromJson(cpuJson),
      memory: MemoryInfo.fromJson(memJson),
      gpu: gpuJson == null ? null : GpuInfo.fromJson(gpuJson),
    );
  }

  Map<String, dynamic> toJson() => {
    'timestampMs': timestampMs,
    'cpu': cpu.toJson(),
    'memory': memory.toJson(),
    if (gpu != null) 'gpu': gpu!.toJson(),
  };
}
