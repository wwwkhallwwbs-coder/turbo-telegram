import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import 'pin_pad.dart';

/// إنشاء رمز PIN: إدخاله ثم تأكيده.
class CreatePinScreen extends StatefulWidget {
  const CreatePinScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends State<CreatePinScreen> {
  String? _first;
  String? _error;
  bool _busy = false;

  Future<void> _onPin(String pin) async {
    if (_first == null) {
      setState(() {
        _first = pin;
        _error = null;
      });
      return;
    }
    if (pin != _first) {
      setState(() {
        _first = null;
        _error = 'الرمزان غير متطابقين. ابدأ من جديد.';
      });
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.controller.createPin(pin);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _first = null;
          _error = 'تعذر حفظ الرمز: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('إنشاء رمز PIN', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  _first == null
                      ? 'اختر رمزاً من 4 أرقام لفتح التطبيق'
                      : 'أعد إدخال الرمز للتأكيد',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 32),
                PinPad(onCompleted: _onPin, enabled: !_busy),
                const SizedBox(height: 20),
                SizedBox(
                  height: 24,
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
