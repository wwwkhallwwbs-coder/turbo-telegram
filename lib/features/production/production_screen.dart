import 'package:flutter/material.dart';

import '../../core/accounting.dart';
import '../../core/labels_ar.dart';
import '../../core/numbers.dart';
import '../../data/models.dart';
import 'production_controller.dart';

/// شاشة الإنتاج اليومي (القطعيات): عيش كل جوال، والمجموع والمتوسط والفرق عن المفروض.
///
/// تملك [controller] وتتخلص منه عند إغلاقها. الحفظ تلقائي مع كل تعديل.
class ProductionScreen extends StatefulWidget {
  const ProductionScreen({
    super.key,
    required this.controller,
    required this.onOpenSettings,
  });

  final ProductionController controller;

  /// يفتح شاشة الإعدادات (عند عدم اكتمال الأسعار).
  final Future<void> Function() onOpenSettings;

  @override
  State<ProductionScreen> createState() => _ProductionScreenState();
}

class _ProductionScreenState extends State<ProductionScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.ensureLoaded();
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  Future<void> _openSettings() async {
    await widget.onOpenSettings();
    if (mounted) {
      await widget.controller.openDay();
    }
  }

  Future<void> _confirmCancelLast() async {
    final controller = widget.controller;
    if (controller.sacks.isEmpty) {
      return;
    }
    final seq = controller.sacks.last.seq;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('إلغاء الجوال رقم $seq؟'),
        content: const Text('يبقى في السجل ولا يدخل في حساب اليوم.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('إلغاء الجوال'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.cancelLastSack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final canCancel =
            controller.day != null && !controller.isLocked && controller.sacks.isNotEmpty;
        return Scaffold(
          appBar: AppBar(
            title: const Text('الإنتاج اليومي (القطعيات)'),
            actions: [
              if (canCancel)
                IconButton(
                  tooltip: 'إلغاء آخر جوال',
                  onPressed: _confirmCancelLast,
                  icon: const Icon(Icons.undo),
                ),
            ],
          ),
          body: SafeArea(child: _body(controller)),
        );
      },
    );
  }

  Widget _body(ProductionController controller) {
    if (controller.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.loadFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                controller.error ?? 'تعذر تحميل اليوم',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => controller.load(),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    final day = controller.day;
    final summary = controller.summary;
    return Column(
      children: [
        _DateBar(controller: controller),
        if (controller.error != null)
          _ErrorBanner(
            message: controller.error!,
            onClose: controller.dismissError,
          ),
        Expanded(
          child: (day == null || summary == null)
              ? _NotOpened(controller: controller, onOpenSettings: _openSettings)
              : _DayView(controller: controller, day: day, summary: summary),
        ),
      ],
    );
  }
}

/// شريط التاريخ: اليوم السابق والتالي (لا بعد اليوم، ولا قبل بداية الوكيل).
class _DateBar extends StatelessWidget {
  const _DateBar({required this.controller});

  final ProductionController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'اليوم السابق',
            onPressed: controller.canGoPrevious ? () => controller.goToPrevious() : null,
            icon: const Icon(Icons.chevron_right),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    controller.date,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                if (controller.isToday)
                  Text('اليوم', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'اليوم التالي',
            onPressed: controller.canGoNext ? () => controller.goToNext() : null,
            icon: const Icon(Icons.chevron_left),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB42318)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(color: Color(0xFFB42318))),
          ),
          IconButton(
            tooltip: 'إخفاء',
            onPressed: onClose,
            icon: const Icon(Icons.close, color: Color(0xFFB42318)),
          ),
        ],
      ),
    );
  }
}

/// اليوم المعروض لم يُفتح بعد.
class _NotOpened extends StatelessWidget {
  const _NotOpened({required this.controller, required this.onOpenSettings});

  final ProductionController controller;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_note_outlined, size: 56),
            const SizedBox(height: 12),
            Text('لم يُفتح هذا اليوم بعد', style: theme.textTheme.titleMedium),
            const SizedBox(height: 20),
            if (controller.needsSettings) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDF0D5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'أدخل سعر الشباك وسعر التوزيع في الإعدادات أولاً، ثم يُفتح اليوم.',
                  style: TextStyle(color: Color(0xFF7A4B00)),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => onOpenSettings(),
                child: const Text('فتح الإعدادات'),
              ),
            ] else
              FilledButton.icon(
                onPressed: () => controller.openDay(),
                icon: const Icon(Icons.add),
                label: const Text('فتح اليوم'),
              ),
          ],
        ),
      ),
    );
  }
}

/// يوم مفتوح (أو مقفل): الملخص وقائمة الجوالات وصف الإدخال.
class _DayView extends StatelessWidget {
  const _DayView({
    required this.controller,
    required this.day,
    required this.summary,
  });

  final ProductionController controller;
  final DayRecord day;
  final ProductionSummary summary;

  @override
  Widget build(BuildContext context) {
    final sacks = controller.sacks;
    return Column(
      children: [
        _SummaryCard(summary: summary),
        if (day.isLocked) const _LockedBanner(),
        Expanded(
          child: sacks.isEmpty
              ? Center(
                  child: Text(
                    day.isLocked ? 'لا جوالات مسجلة في هذا اليوم' : 'اكتب عيش أول جوال بالأسفل',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              // القائمة معكوسة الاتجاه: أحدث جوال يلتصق بصف الإدخال في الأسفل
              // (كالمحادثة)، فيبقى ظاهراً بعد كل إضافة، والأقدم يُرى بالتمرير للأعلى.
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: sacks.length,
                  itemBuilder: (context, index) {
                    final entry = sacks[sacks.length - 1 - index];
                    return _SackRow(
                      key: ValueKey<int>(entry.seq),
                      seq: entry.seq,
                      loaves: entry.loaves,
                      editable: !day.isLocked,
                      onChanged: (value) => controller.setLoaves(entry.seq, value),
                    );
                  },
                ),
        ),
        if (!day.isLocked) _EntryBar(controller: controller),
      ],
    );
  }
}

class _LockedBanner extends StatelessWidget {
  const _LockedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF0D5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Icon(Icons.lock_outline, color: Color(0xFF7A4B00)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              lockedDayMessage,
              style: TextStyle(color: Color(0xFF7A4B00), fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// المجموع الكلي وعدد الجوالات والمتوسط والمفروض، وسطر واحد للفرق.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final ProductionSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('المجموع الكلي', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 2),
            Text(
              formatThousands(summary.total),
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Stat(label: 'الجوالات', value: summary.sacks.toString()),
                _Stat(label: 'المتوسط', value: formatAverage(summary.average)),
                _Stat(label: 'المفروض', value: formatThousands(summary.expected)),
              ],
            ),
            if (summary.sacks > 0) ...[
              const SizedBox(height: 12),
              _DiffLine(diff: summary.diff),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({required this.diff});

  final int diff;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    if (diff > 0) {
      background = const Color(0xFFE3F1ED);
      foreground = const Color(0xFF0E6B58);
    } else if (diff < 0) {
      background = const Color(0xFFFDF0D5);
      foreground = const Color(0xFF7A4B00);
    } else {
      background = const Color(0xFFF1F3F2);
      foreground = const Color(0xFF1B2421);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        productionDiffLabel(diff),
        textAlign: TextAlign.center,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// صف جوال: رقمه فقط وحقل العيش. كل تعديل صحيح يُحفظ فوراً.
class _SackRow extends StatefulWidget {
  const _SackRow({
    super.key,
    required this.seq,
    required this.loaves,
    required this.editable,
    required this.onChanged,
  });

  final int seq;
  final int loaves;
  final bool editable;
  final ValueChanged<int> onChanged;

  @override
  State<_SackRow> createState() => _SackRowState();
}

class _SackRowState extends State<_SackRow> {
  late final TextEditingController _text =
      TextEditingController(text: widget.loaves.toString());
  final FocusNode _focus = FocusNode();

  /// آخر قيمة أرسلناها للحفظ. نقارن بها (لا بالقيمة المقروءة من القاعدة) لأن
  /// القراءة تتأخر عن الكتابة: لو كتب المستخدم 9 ثم 90 ثم عاد إلى القيمة
  /// الأصلية بسرعة لوجب إرسالها، وإلا بقي الحقل مخالفاً للمحفوظ.
  late int _sent = widget.loaves;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  /// عند ترك الحقل فارغاً أو غير صالح نعيد القيمة المحفوظة، فلا يبقى الحقل مخالفاً للمخزَّن.
  void _onFocusChanged() {
    if (!_focus.hasFocus && parseWholeNumber(_text.text) == null) {
      _text.text = _sent.toString();
    }
  }

  void _changed(String value) {
    final parsed = parseWholeNumber(value);
    if (parsed != null && parsed != _sent) {
      _sent = parsed;
      widget.onChanged(parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              widget.seq.toString(),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: widget.editable
                ? TextField(
                    controller: _text,
                    focusNode: _focus,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    onChanged: _changed,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      suffixText: 'عيشة',
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFD0D5D2)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      formatThousands(widget.loaves),
                      textAlign: TextAlign.center,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// صف الإدخال السفلي: عيش الجوال التالي. «إضافة» تسجله وتبقي المفتاح مفتوحاً.
class _EntryBar extends StatefulWidget {
  const _EntryBar({required this.controller});

  final ProductionController controller;

  @override
  State<_EntryBar> createState() => _EntryBarState();
}

class _EntryBarState extends State<_EntryBar> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _invalid = false;

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final value = parseWholeNumber(_text.text);
    if (value == null) {
      setState(() {
        _invalid = true;
      });
      return;
    }
    widget.controller.addSack(value);
    _text.clear();
    setState(() {
      _invalid = false;
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              height: 48,
              child: Center(
                child: Text(
                  widget.controller.nextSeq.toString(),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _text,
                focusNode: _focus,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                textAlign: TextAlign.center,
                onEditingComplete: _submit,
                decoration: InputDecoration(
                  hintText: 'عدد العيش',
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  errorText: _invalid ? 'اكتب عدداً صحيحاً' : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _submit,
                child: const Text('إضافة'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
