import 'dart:math';

final Random _secure = Random.secure();

/// معرّف UUID v4 عشوائي كنص من 36 حرفاً.
String newId() {
  final bytes = List<int>.generate(16, (_) => _secure.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int from, int to) => bytes
      .sublist(from, to)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

/// الوقت بصيغة UTC مثل المخطط: `2026-11-24T07:38:12Z` (بلا أجزاء من الثانية).
String nowIso([DateTime? time]) {
  final utc = (time ?? DateTime.now()).toUtc();
  final year = utc.year.toString().padLeft(4, '0');
  return '$year-${_two(utc.month)}-${_two(utc.day)}'
      'T${_two(utc.hour)}:${_two(utc.minute)}:${_two(utc.second)}Z';
}

/// تاريخ اليوم المحلي بصيغة `YYYY-MM-DD` (تاريخ المخبز، لا UTC).
String formatDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  return '$year-${_two(date.month)}-${_two(date.day)}';
}

final RegExp _isoDate = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// يزيح تاريخاً بصيغة `YYYY-MM-DD` بعدد من الأيام (موجب للأمام، سالب للخلف).
/// الحساب على UTC حتى لا يتأثر بتوقيت الصيف أو تغيّر المنطقة الزمنية.
String shiftDate(String date, int days) {
  final match = _isoDate.firstMatch(date);
  if (match == null) {
    throw ArgumentError.value(date, 'date', 'التاريخ بصيغة YYYY-MM-DD');
  }
  final base = DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
  return formatDate(base.add(Duration(days: days)));
}
