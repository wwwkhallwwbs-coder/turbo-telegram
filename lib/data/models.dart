/// جهاز مُفعَّل: دوره والمخبز والوكيل المرتبطان به.
class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.role,
    required this.bakeryId,
    required this.agentId,
  });

  /// معرّف الجهاز في القاعدة (يُكتب في عمود device_id لكل صف ينشئه).
  final String id;

  /// `agent` أو `owner`.
  final String role;
  final String? bakeryId;
  final String? agentId;
}

/// يوم عمل: الأسعار والمستهدف منسوخة إليه عند إنشائه، فلا يتغير حسابه لاحقاً.
class DayRecord {
  const DayRecord({
    required this.id,
    required this.date,
    required this.status,
    required this.windowPrice,
    required this.distributionPrice,
    required this.targetPerSack,
    required this.batchSizeKg,
  });

  final String id;

  /// `YYYY-MM-DD`.
  final String date;

  /// `open` أو `locked`.
  final String status;
  final int windowPrice;
  final int distributionPrice;
  final int targetPerSack;
  final double batchSizeKg;

  bool get isLocked => status == 'locked';
}

/// قطعيات جوال واحد: seq رقم الجوال، وloaves عدد العيش.
class SackEntry {
  const SackEntry({required this.seq, required this.loaves});

  final int seq;
  final int loaves;
}
