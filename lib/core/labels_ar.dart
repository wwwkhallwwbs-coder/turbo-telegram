/// نصوص وأرقام العرض بالعربية (الأرقام بالصيغة الغربية 9,040 كما في التصميم).

/// تجميع الآلاف بفاصلة: 9040 ← 9,040 ، -86000 ← -86,000.
String formatThousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return value < 0 ? '-$buffer' : buffer.toString();
}

/// السطر تحت المجموع الكلي في شاشة الإنتاج.
String productionDiffLabel(int diff) {
  if (diff > 0) {
    return 'إنتاج اليوم زائد عن المفروض بـ ${formatThousands(diff)} عيشة';
  }
  if (diff < 0) {
    return 'إنتاج اليوم ناقص عن المفروض بـ ${formatThousands(-diff)} عيشة';
  }
  return 'إنتاج اليوم مطابق للمفروض';
}

/// تنبيه فرق البنكجي (يظهر فقط إذا اختلفت التوريدة عن المطلوب).
String bankajiDiffLabel(int diff) {
  if (diff == 0) {
    return '';
  }
  if (diff > 0) {
    return 'تنبيه: على البنكجي فرق ${formatThousands(diff)}';
  }
  return 'تنبيه: البنكجي ورَّد زيادة ${formatThousands(-diff)}';
}

/// المتوسط للجوال: عدد صحيح إن لم يكن فيه كسر (904)، وإلا بخانة عشرية واحدة (903.5).
String formatAverage(double value) {
  final rounded = (value * 10).round() / 10;
  if (rounded == rounded.roundToDouble()) {
    return formatThousands(rounded.round());
  }
  return rounded.toStringAsFixed(1);
}
