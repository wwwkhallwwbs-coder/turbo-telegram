/// يحوّل الأرقام العربية الهندية (٠-٩) والفارسية (۰-۹) إلى 0-9.
/// بعض لوحات المفاتيح العربية تكتبها في خانات الأرقام.
String normalizeDigits(String text) {
  final buffer = StringBuffer();
  for (final unit in text.runes) {
    if (unit >= 0x0660 && unit <= 0x0669) {
      buffer.writeCharCode(unit - 0x0660 + 0x30);
    } else if (unit >= 0x06F0 && unit <= 0x06F9) {
      buffer.writeCharCode(unit - 0x06F0 + 0x30);
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

/// يقرأ عدداً صحيحاً غير سالب من نص المستخدم (يتجاهل المسافات وفواصل الآلاف).
/// يرجع null إن لم يكن النص عدداً صحيحاً.
int? parseWholeNumber(String text) {
  final cleaned = normalizeDigits(text).replaceAll(RegExp(r'[\s,،٬]'), '');
  if (!RegExp(r'^\d+$').hasMatch(cleaned)) {
    return null;
  }
  return int.tryParse(cleaned);
}
