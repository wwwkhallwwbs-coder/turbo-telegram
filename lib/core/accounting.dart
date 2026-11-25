/// المعادلات المحاسبية لتطبيق «مخبزك» (المواصفة الفنية §4).
///
/// كل المبالغ والكميات أعداد صحيحة (جنيه / عيشة)، والدقيق بالكيلو.
/// دوال نقية بلا قاعدة بيانات ولا واجهة، حتى يسهل اختبارها.
/// لا تحسب هنا الصفوف الملغاة (cancelled_at): الاستعلام هو الذي يستثنيها.

/// ملخص إنتاج اليوم (§4.1).
class ProductionSummary {
  const ProductionSummary({
    required this.sacks,
    required this.total,
    required this.expected,
  });

  /// عدد الجوالات.
  final int sacks;

  /// المجموع الكلي للعيش = Σ قطعيات كل جوال.
  final int total;

  /// المفروض = عدد الجوالات × المستهدف للجوال.
  final int expected;

  /// الفرق عن المفروض: موجب = زائد، سالب = ناقص.
  int get diff => total - expected;

  /// المتوسط للجوال الواحد = المجموع الكلي ÷ عدد الجوالات.
  double get average => sacks == 0 ? 0.0 : total / sacks;
}

ProductionSummary summarizeProduction({
  required List<int> loavesPerSack,
  required int targetPerSack,
}) {
  final sacks = loavesPerSack.length;
  final total = loavesPerSack.fold<int>(0, (sum, value) => sum + value);
  return ProductionSummary(
    sacks: sacks,
    total: total,
    expected: sacks * targetPerSack,
  );
}

/// سطر موزع في جدول الموزعين (§4.2).
class DistributorLine {
  const DistributorLine({
    required this.name,
    required this.loaves,
    required this.paid,
    required this.distributionPrice,
  });

  final String name;
  final int loaves;
  final int paid;
  final int distributionPrice;

  /// المستحق = الكمية الموزعة × سعر عيشة التوزيع.
  int get due => loaves * distributionPrice;

  /// المتبقي على الموزع = المستحق − المسدد.
  int get remaining => due - paid;
}

/// إجمالي جدول الموزعين.
class DistributionTotals {
  const DistributionTotals({
    required this.loaves,
    required this.due,
    required this.paid,
  });

  final int loaves;
  final int due;
  final int paid;

  int get remaining => due - paid;
}

DistributionTotals totalDistribution(Iterable<DistributorLine> lines) {
  var loaves = 0;
  var due = 0;
  var paid = 0;
  for (final line in lines) {
    loaves += line.loaves;
    due += line.due;
    paid += line.paid;
  }
  return DistributionTotals(loaves: loaves, due: due, paid: paid);
}

/// حساب اليوم (§4.2 و §4.5).
class DayAccount {
  const DayAccount({
    required this.windowLoaves,
    required this.windowRevenue,
    required this.distributionTotal,
    required this.generalExpenses,
    required this.bankajiRequired,
    required this.bankajiRemitted,
    required this.bankajiDiff,
    required this.agentCarryIn,
    required this.agentRequired,
    required this.agentRemitted,
    required this.agentCarryOut,
  });

  /// عيش الشباك = المجموع الكلي − الموزع للخارج.
  final int windowLoaves;

  /// إيراد الشباك = عيش الشباك × سعر الشباك.
  final int windowRevenue;

  /// مبيعات توزيع اليوم الجديدة فقط = الكمية الموزعة × سعر التوزيع.
  final int distributionTotal;

  /// إجمالي المصروفات العامة (الثابتة + المتحركة). الشخصية للوكيل لا تدخل هنا.
  final int generalExpenses;

  /// «حساب البنكجي» = إيراد الشباك − المصروفات العامة.
  final int bankajiRequired;

  final int bankajiRemitted;

  /// «فرق البنكجي» = حساب البنكجي − المورَّد منه (صفر = لا تنبيه).
  final int bankajiDiff;

  /// المرحَّل من أمس على الوكيل.
  final int agentCarryIn;

  /// المطلوب الكلي من الوكيل = حساب البنكجي + مبيعات التوزيع + المرحَّل من أمس.
  final int agentRequired;

  final int agentRemitted;

  /// المتبقي على الوكيل، يُرحَّل لحساب الغد = المطلوب الكلي − توريدة اليوم.
  final int agentCarryOut;

  bool get hasBankajiDiff => bankajiDiff != 0;
}

/// دين الموزعين المتبقي لا يُجمع هنا مرة ثانية: هو محسوب مسبقاً ضمن رصيد الوكيل
/// المرحَّل (§5)، ويُعرض في جدول الموزعين للمتابعة فقط.
DayAccount computeDayAccount({
  required int totalLoaves,
  required int distributedLoaves,
  required int windowPrice,
  required int distributionPrice,
  required int generalExpenses,
  required int bankajiRemitted,
  required int agentCarryIn,
  required int agentRemitted,
}) {
  final windowLoaves = totalLoaves - distributedLoaves;
  final windowRevenue = windowLoaves * windowPrice;
  final distributionTotal = distributedLoaves * distributionPrice;
  final bankajiRequired = windowRevenue - generalExpenses;
  final agentRequired = bankajiRequired + distributionTotal + agentCarryIn;
  return DayAccount(
    windowLoaves: windowLoaves,
    windowRevenue: windowRevenue,
    distributionTotal: distributionTotal,
    generalExpenses: generalExpenses,
    bankajiRequired: bankajiRequired,
    bankajiRemitted: bankajiRemitted,
    bankajiDiff: bankajiRequired - bankajiRemitted,
    agentCarryIn: agentCarryIn,
    agentRequired: agentRequired,
    agentRemitted: agentRemitted,
    agentCarryOut: agentRequired - agentRemitted,
  );
}

/// عجنة بحجم ثابت وعدد مرات (§4.4): الحجم 50 أو 37.5 كجم، وعجنة 25 كجم اختيارية.
class BatchLine {
  const BatchLine({required this.sizeKg, required this.count});

  final double sizeKg;
  final int count;
}

/// الدقيق المعجون (كجم) = Σ (حجم العجنة × عددها).
double kneadedFlourKg(Iterable<BatchLine> batches) {
  var total = 0.0;
  for (final batch in batches) {
    total += batch.sizeKg * batch.count;
  }
  return total;
}

double kgToSacks(double kg, double sackSizeKg) => kg / sackSizeKg;

/// المتبقي = الموجود أول اليوم + الوارد − الصادر (خارج المخبز) − المستهلك/المعجون.
double stockClosing({
  required double opening,
  required double incoming,
  required double outgoing,
  required double used,
}) {
  return opening + incoming - outgoing - used;
}
