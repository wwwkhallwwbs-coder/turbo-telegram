import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../core/activation.dart';

/// تفعيل التطبيق: يعرض كود الجهاز ليرسله الوكيل للمصمم، ثم يلصق الرمز الذي وصله.
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final TextEditingController _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _copyDeviceCode() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(
      ClipboardData(text: formatDeviceCode(widget.controller.deviceCode)),
    );
    messenger.showSnackBar(const SnackBar(content: Text('تم نسخ كود الجهاز')));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && mounted) {
      setState(() => _code.text = text.trim());
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.controller.submitActivationCode(_code.text);
    if (!mounted) {
      return;
    }
    // عند النجاح يتغير الـ stage وتُستبدل هذه الشاشة.
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deviceCode = formatDeviceCode(widget.controller.deviceCode);
    return Scaffold(
      appBar: AppBar(title: const Text('تفعيل التطبيق')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('1. أرسل كود جهازك للمصمم', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: SelectableText(
                          deviceCode,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            letterSpacing: 3,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'نسخ الكود',
                      onPressed: _copyDeviceCode,
                      icon: const Icon(Icons.copy),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('2. الصق رمز التفعيل الذي وصلك', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              minLines: 3,
              maxLines: 6,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'MKZ1-XXXXX-XXXXX-...',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _paste,
                icon: const Icon(Icons.content_paste),
                label: const Text('لصق من الحافظة'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_busy ? 'جارٍ التحقق...' : 'تفعيل'),
              ),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: widget.controller.skipActivationForTesting,
                child: const Text('تخطي التفعيل (للتجربة فقط)'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
