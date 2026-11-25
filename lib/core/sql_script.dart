/// يقسم سكريبت SQL إلى جمل منفصلة لتنفيذها واحدة واحدة على sqflite.
///
/// القواعد (نفس منطق tools/verify_schema.py):
/// - تُتجاهل الأسطر الفارغة وأسطر التعليقات التي تبدأ بـ `--`.
/// - جملة `CREATE TRIGGER` تنتهي عند سطر ينتهي بـ `END;` (قد تحوي `;` داخلها).
/// - غيرها تنتهي عند سطر ينتهي بـ `;`.
/// - جمل `PRAGMA` تُحذف (تُضبط من التطبيق عند فتح الاتصال).
/// - لا تعليقات داخل الجملة نفسها.
List<String> splitSqlScript(String script) {
  final statements = <String>[];
  final buffer = <String>[];
  var inTrigger = false;
  final triggerEnd = RegExp(r'END;\s*$', caseSensitive: false);

  for (final raw in script.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('--')) {
      continue;
    }
    buffer.add(raw);
    if (line.toUpperCase().startsWith('CREATE TRIGGER')) {
      inTrigger = true;
    }
    final finished = inTrigger ? triggerEnd.hasMatch(line) : line.endsWith(';');
    if (finished) {
      final statement = buffer.join('\n').trim();
      buffer.clear();
      inTrigger = false;
      if (!statement.toUpperCase().startsWith('PRAGMA')) {
        statements.add(statement);
      }
    }
  }

  if (buffer.isNotEmpty) {
    throw FormatException('جملة SQL غير منتهية: ${buffer.join(' ')}');
  }
  return statements;
}
