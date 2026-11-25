import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/numbers.dart';
import '../../data/settings_repository.dart';

/// الإعدادات: الأسعار والمستهدف وحجم العجنة والجوال.
/// تسري على الأيام الجديدة فقط، فكل يوم يحتفظ بالأسعار التي فُتح بها.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _window = TextEditingController();
  final TextEditingController _distribution = TextEditingController();
  final TextEditingController _target = TextEditingController();
  double _batchKg = 50;
  double _sackKg = 50;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _window.dispose();
    _distribution.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = widget.controller.settings;
    final window = await settings.getInt(SettingKeys.windowPrice);
    final distribution = await settings.getInt(SettingKeys.distributionPrice);
    final target = await settings.getInt(SettingKeys.targetPerSack);
    final batch = await settings.getDouble(SettingKeys.batchSizeKg);
    final sack = await settings.getDouble(SettingKeys.sackSizeKg);
    if (!mounted) {
      return;
    }
    setState(() {
      _window.text = window?.toString() ?? '';
      _distribution.text = distribution?.toString() ?? '';
      _target.text = target?.toString() ?? '';
      _batchKg = batch ?? 50;
      _sackKg = sack ?? 50;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final window = parseWholeNumber(_window.text);
    final distribution = parseWholeNumber(_distribution.text);
    final target = parseWholeNumber(_target.text);
    if (window == null || distribution == null) {
      setState(() => _error = 'اكتب سعر الشباك وسعر التوزيع بأرقام صحيحة');
      return;
    }
    if (target == null || target <= 0) {
      setState(() => _error = 'اكتب المستهدف للجوال بعدد أكبر من صفر');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final settings = widget.controller.settings;
      await settings.set(SettingKeys.windowPrice, window);
      await settings.set(SettingKeys.distributionPrice, distribution);
      await settings.set(SettingKeys.targetPerSack, target);
      await settings.set(SettingKeys.batchSizeKg, _batchKg);
      await settings.set(SettingKeys.sackSizeKg, _sackKg);
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      messenger.showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات')));
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'تعذر الحفظ: $error';
        });
      }
    }
  }

  Widget _numberField(TextEditingController controller, String label, String suffix) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: const OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    'التعديل هنا يسري على الأيام الجديدة فقط. الأيام المفتوحة سابقاً تحتفظ بأسعارها.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  _numberField(_window, 'سعر عيشة الشباك', 'جنيه'),
                  const SizedBox(height: 16),
                  _numberField(_distribution, 'سعر عيشة التوزيع', 'جنيه'),
                  const SizedBox(height: 16),
                  _numberField(_target, 'المستهدف لكل جوال', 'عيشة'),
                  const SizedBox(height: 24),
                  Text('حجم العجنة', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SegmentedButton<double>(
                    segments: const [
                      ButtonSegment<double>(value: 37.5, label: Text('37.5 كجم')),
                      ButtonSegment<double>(value: 50, label: Text('50 كجم')),
                    ],
                    selected: {_batchKg},
                    onSelectionChanged: (selection) =>
                        setState(() => _batchKg = selection.first),
                  ),
                  const SizedBox(height: 24),
                  Text('حجم جوال الدقيق', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SegmentedButton<double>(
                    segments: const [
                      ButtonSegment<double>(value: 25, label: Text('25 كجم')),
                      ButtonSegment<double>(value: 50, label: Text('50 كجم')),
                    ],
                    selected: {_sackKg},
                    onSelectionChanged: (selection) =>
                        setState(() => _sackKg = selection.first),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('حفظ'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
