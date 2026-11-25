import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/pin_service.dart';
import 'pin_pad.dart';

/// إدخال رمز PIN لفتح التطبيق.
class EnterPinScreen extends StatefulWidget {
  const EnterPinScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<EnterPinScreen> createState() => _EnterPinScreenState();
}

class _EnterPinScreenState extends State<EnterPinScreen> {
  String? _error;
  bool _busy = false;

  Future<void> _onPin(String pin) async {
    setState(() => _busy = true);
    final result = await widget.controller.unlock(pin);
    if (!mounted) {
      return;
    }
    // عند النجاح يتغير الـ stage وتُستبدل هذه الشاشة، فلا نفعل شيئاً.
    if (result.status == PinStatus.wrong) {
      setState(() {
        _busy = false;
        _error = 'الرمز غير صحيح. المحاولات المتبقية: ${result.attemptsLeft}';
      });
    } else if (result.status == PinStatus.lockedOut) {
      final remaining = result.lockedUntil!.difference(DateTime.now());
      final minutes = remaining.inMinutes + 1;
      setState(() {
        _busy = false;
        _error = 'تم إيقاف المحاولات مؤقتاً. حاول بعد $minutes دقيقة.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.controller.bakeryName;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 40, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  name == null ? 'مخبزك' : 'مخبزك: $name',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text('أدخل رمز PIN', style: theme.textTheme.bodyLarge),
                const SizedBox(height: 32),
                PinPad(onCompleted: _onPin, enabled: !_busy),
                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: Text(
                    _error ?? '',
                    style: TextStyle(color: theme.colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
