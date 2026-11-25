import 'package:flutter_test/flutter_test.dart';
import 'package:makhbazak/core/accounting.dart';
import 'package:makhbazak/core/labels_ar.dart';

/// كل الأرقام هنا هي أمثلة المواصفة الفنية النهائية (§4) نفسها.
void main() {
  const loaves = [890, 880, 920, 905, 915, 898, 910, 925, 897, 900];

  group('الإنتاج اليومي §4.1', () {
    test('المجموع والمتوسط والفرق عن المفروض', () {
      final summary = summarizeProduction(
        loavesPerSack: loaves,
        targetPerSack: 900,
      );
      expect(summary.sacks, 10);
      expect(summary.total, 9040);
      expect(summary.expected, 9000);
      expect(summary.diff, 40);
      expect(summary.average, 904);
    });

    test('بدون جوالات لا قسمة على صفر', () {
      final summary = summarizeProduction(
        loavesPerSack: const [],
        targetPerSack: 900,
      );
      expect(summary.total, 0);
      expect(summary.expected, 0);
      expect(summary.diff, 0);
      expect(summary.average, 0);
    });
  });

  group('الشباك والتوزيع §4.2', () {
    const lines = [
      DistributorLine(name: 'أ', loaves: 250, paid: 22500, distributionPrice: 90),
      DistributorLine(name: 'ب', loaves: 300, paid: 20000, distributionPrice: 90),
      DistributorLine(name: 'ج', loaves: 180, paid: 10000, distributionPrice: 90),
    ];

    test('مستحق ومتبقي كل موزع', () {
      expect(lines[0].due, 22500);
      expect(lines[0].remaining, 0);
      expect(lines[1].due, 27000);
      expect(lines[1].remaining, 7000);
      expect(lines[2].due, 16200);
      expect(lines[2].remaining, 6200);
    });

    test('إجمالي الموزعين', () {
      final totals = totalDistribution(lines);
      expect(totals.loaves, 730);
      expect(totals.due, 65700);
      expect(totals.paid, 52500);
      expect(totals.remaining, 13200);
    });
  });

  group('حساب اليوم §4.2 و §4.5', () {
    final account = computeDayAccount(
      totalLoaves: 9040,
      distributedLoaves: 730,
      windowPrice: 100,
      distributionPrice: 90,
      generalExpenses: 245000, // ثابتة 220,000 + متحركة 25,000
      bankajiRemitted: 500000,
      agentCarryIn: 0,
      agentRemitted: 600000,
    );

    test('الشباك وحساب البنكجي', () {
      expect(account.windowLoaves, 8310);
      expect(account.windowRevenue, 831000);
      expect(account.bankajiRequired, 586000);
    });

    test('فرق البنكجي', () {
      expect(account.bankajiDiff, 86000);
      expect(account.hasBankajiDiff, isTrue);
    });

    test('المطلوب من الوكيل والمرحَّل للغد', () {
      expect(account.distributionTotal, 65700);
      expect(account.agentRequired, 651700);
      expect(account.agentCarryOut, 51700);
    });

    test('الرصيد المرحَّل يدخل في المطلوب ولا يتكرر دين الموزعين', () {
      final next = computeDayAccount(
        totalLoaves: 9000,
        distributedLoaves: 0,
        windowPrice: 100,
        distributionPrice: 90,
        generalExpenses: 245000,
        bankajiRemitted: 655000,
        agentCarryIn: account.agentCarryOut,
        agentRemitted: 0,
      );
      expect(next.bankajiRequired, 655000);
      expect(next.bankajiDiff, 0);
      expect(next.hasBankajiDiff, isFalse);
      expect(next.agentRequired, 655000 + 51700);
    });
  });

  group('المخزون §4.4', () {
    test('الدقيق المعجون: 10 عجنات × 50 كجم', () {
      final kg = kneadedFlourKg(const [BatchLine(sizeKg: 50, count: 10)]);
      expect(kg, 500);
      expect(kgToSacks(kg, 50), 10);
    });

    test('عجنة 37.5 كجم وعجنة أخيرة 25 كجم', () {
      final kg = kneadedFlourKg(const [
        BatchLine(sizeKg: 37.5, count: 8),
        BatchLine(sizeKg: 25, count: 1),
      ]);
      expect(kg, 325);
    });

    test('المتبقي: دقيق 48 شوال، خميرة 9، غاز 5', () {
      // دقيق بالشوال (50 كجم): 40 + 20 − 2 − 10 = 48
      expect(
        stockClosing(opening: 40, incoming: 20, outgoing: 2, used: 10),
        48,
      );
      expect(
        stockClosing(opening: 12, incoming: 0, outgoing: 0, used: 3),
        9,
      );
      expect(
        stockClosing(opening: 6, incoming: 0, outgoing: 0, used: 1),
        5,
      );
    });
  });

  group('نصوص العرض', () {
    test('تجميع الآلاف', () {
      expect(formatThousands(0), '0');
      expect(formatThousands(999), '999');
      expect(formatThousands(1000), '1,000');
      expect(formatThousands(9040), '9,040');
      expect(formatThousands(831000), '831,000');
      expect(formatThousands(-86000), '-86,000');
    });

    test('سطر الفرق عن المفروض', () {
      expect(
        productionDiffLabel(40),
        'إنتاج اليوم زائد عن المفروض بـ 40 عيشة',
      );
      expect(
        productionDiffLabel(-1250),
        'إنتاج اليوم ناقص عن المفروض بـ 1,250 عيشة',
      );
      expect(productionDiffLabel(0), 'إنتاج اليوم مطابق للمفروض');
    });

    test('المتوسط للجوال', () {
      expect(formatAverage(904), '904');
      expect(formatAverage(903.5), '903.5');
      expect(formatAverage(904.33), '904.3');
      expect(formatAverage(0), '0');
    });

    test('تنبيه فرق البنكجي يختفي عند التطابق', () {
      expect(bankajiDiffLabel(0), '');
      expect(bankajiDiffLabel(86000), 'تنبيه: على البنكجي فرق 86,000');
    });
  });
}
