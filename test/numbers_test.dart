import 'package:flutter_test/flutter_test.dart';
import 'package:makhbazak/core/numbers.dart';

void main() {
  test('تحويل الأرقام العربية والفارسية إلى لاتينية', () {
    expect(normalizeDigits('٠١٢٣٤٥٦٧٨٩'), '0123456789');
    expect(normalizeDigits('۰۱۲۳۴۵۶۷۸۹'), '0123456789');
    expect(normalizeDigits('سعر ١٠٠'), 'سعر 100');
  });

  test('قراءة عدد صحيح من نص المستخدم', () {
    expect(parseWholeNumber('100'), 100);
    expect(parseWholeNumber('١٠٠'), 100);
    expect(parseWholeNumber(' 1,200 '), 1200);
    expect(parseWholeNumber('1٬200'), 1200);
    expect(parseWholeNumber('0'), 0);
  });

  test('نصوص غير صالحة ترجع null', () {
    for (final bad in ['', ' ', 'abc', '12.5', '-5', '1e3', '١٢٫٥']) {
      expect(parseWholeNumber(bad), isNull, reason: '"$bad"');
    }
  });
}
