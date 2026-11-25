import 'package:flutter/foundation.dart';

import '../../core/accounting.dart';
import '../../data/day_repository.dart';
import '../../data/models.dart';
import '../../data/util.dart';

/// رسالة موحدة عند محاولة الكتابة على يوم مقفل.
const String lockedDayMessage = 'اليوم مقفل: للقراءة فقط';

/// حالة شاشة القطعيات: اليوم المعروض وجوالاته وملخص الإنتاج.
///
/// الشاشة لا تحسب ولا تكتب SQL، بل تستدعي هذا المتحكم، وهو يستدعي
/// [DayRepository] ومعادلات `lib/core`. كل العمليات تُنفَّذ بالترتيب نفسه
/// الذي استُدعيت به (طابور واحد)، فالكتابة السريعة المتتابعة لا تتداخل،
/// ولا تُرمى أخطاؤها: تُحفظ في [error] لتعرضها الشاشة.
class ProductionController extends ChangeNotifier {
  ProductionController({
    required DayRepository days,
    DateTime Function()? clock,
  })  : _days = days,
        _clock = clock ?? DateTime.now;

  final DayRepository _days;
  final DateTime Function() _clock;

  Future<void> _pending = Future<void>.value();
  bool _disposed = false;
  bool _loaded = false;

  /// جارٍ تحميل اليوم المعروض.
  bool loading = true;

  /// فشل التحميل نفسه (تُعرض معه زر إعادة المحاولة).
  bool loadFailed = false;

  /// رسالة آخر خطأ في عملية (فتح أو حفظ)، أو null.
  String? error;

  /// فتح اليوم يحتاج إكمال الإعدادات أولاً (الأسعار).
  bool needsSettings = false;

  /// بداية عمل الوكيل في المخبز: لا يُفتح يوم قبلها.
  String? startDate;

  /// التاريخ المعروض `YYYY-MM-DD`.
  String date = '';

  /// اليوم المعروض، أو null إن لم يُفتح بعد.
  DayRecord? day;

  /// الجوالات الفعالة مرتبة برقم الجوال.
  List<SackEntry> sacks = const <SackEntry>[];

  /// ملخص الإنتاج، أو null إن لم يُفتح اليوم.
  ProductionSummary? summary;

  String get today => formatDate(_clock());

  bool get isToday => date == today;

  bool get isLocked => day?.isLocked ?? false;

  bool get canGoPrevious {
    final start = startDate;
    return start != null && date.compareTo(start) > 0;
  }

  bool get canGoNext => date.compareTo(today) < 0;

  /// رقم الجوال التالي.
  int get nextSeq => sacks.isEmpty ? 1 : sacks.last.seq + 1;

  Future<void> ensureLoaded() => _loaded ? Future<void>.value() : load();

  /// يحمّل [targetDate] (الافتراضي: اليوم المعروض، وأول مرة تاريخ اليوم).
  /// التاريخ يُقيَّد بين بداية الوكيل واليوم.
  Future<void> load([String? targetDate]) {
    return _enqueue(() async {
      loading = true;
      loadFailed = false;
      error = null;
      needsSettings = false;
      _notify();
      try {
        startDate ??= await _days.agentStartDate();
        final wanted = targetDate ?? (date.isEmpty ? today : date);
        date = _clamp(wanted);
        await _refresh();
        _loaded = true;
      } on Object catch (e) {
        loadFailed = true;
        error = 'تعذر تحميل اليوم: $e';
      }
      loading = false;
      _notify();
    });
  }

  Future<void> goToPrevious() async {
    if (canGoPrevious) {
      await load(shiftDate(date, -1));
    }
  }

  Future<void> goToNext() async {
    if (canGoNext) {
      await load(shiftDate(date, 1));
    }
  }

  /// يفتح اليوم المعروض (يُنشأ بأسعار الإعدادات الحالية).
  Future<void> openDay() {
    return _enqueue(() async {
      error = null;
      needsSettings = false;
      try {
        if (!await _days.hasOpeningSettings()) {
          needsSettings = true;
        } else {
          await _days.getOrCreate(date);
          await _refresh();
        }
      } on Object catch (e) {
        error = _describe(e, 'تعذر فتح اليوم');
      }
      _notify();
    });
  }

  /// يضيف جوالاً جديداً برقم تالٍ وقطعياته [loaves].
  Future<void> addSack(int loaves) {
    return _write((current) => _days.setSack(current.id, nextSeq, loaves));
  }

  /// يعدّل قطعيات الجوال رقم [seq].
  Future<void> setLoaves(int seq, int loaves) {
    return _write((current) => _days.setSack(current.id, seq, loaves));
  }

  /// يلغي آخر جوال (يبقى في السجل ولا يدخل الحساب).
  Future<void> cancelLastSack() {
    return _write((current) async {
      if (sacks.isNotEmpty) {
        await _days.cancelSack(current.id, sacks.last.seq);
      }
    });
  }

  void dismissError() {
    if (error != null) {
      error = null;
      _notify();
    }
  }

  Future<void> _write(Future<void> Function(DayRecord current) action) {
    return _enqueue(() async {
      final current = day;
      if (current == null) {
        error = 'افتح اليوم أولاً';
      } else if (current.isLocked) {
        error = lockedDayMessage;
      } else {
        try {
          await action(current);
          await _refresh();
          error = null;
        } on Object catch (e) {
          error = _describe(e, 'تعذر الحفظ');
        }
      }
      _notify();
    });
  }

  /// يقرأ اليوم المعروض وجوالاته من القاعدة ويحسب الملخص.
  Future<void> _refresh() async {
    final found = await _days.find(date);
    day = found;
    if (found == null) {
      sacks = const <SackEntry>[];
      summary = null;
      return;
    }
    sacks = await _days.sacks(found.id);
    summary = summarizeProduction(
      loavesPerSack: sacks.map((entry) => entry.loaves).toList(),
      targetPerSack: found.targetPerSack,
    );
  }

  String _clamp(String wanted) {
    var result = wanted;
    final now = today;
    if (result.compareTo(now) > 0) {
      result = now;
    }
    final start = startDate;
    if (start != null && result.compareTo(start) < 0) {
      result = start;
    }
    return result;
  }

  String _describe(Object e, String prefix) {
    final text = e.toString();
    if (text.contains('day is locked')) {
      return lockedDayMessage;
    }
    if (text.contains('not assigned')) {
      return 'هذا التاريخ قبل بداية عملك في المخبز';
    }
    if (e is ArgumentError) {
      return '$prefix: ${e.message}';
    }
    if (e is StateError) {
      return '$prefix: ${e.message}';
    }
    return '$prefix: $text';
  }

  /// يشغّل العمليات بالترتيب، وفشل إحداها لا يوقف الطابور.
  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _pending.then((_) => operation());
    _pending = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
