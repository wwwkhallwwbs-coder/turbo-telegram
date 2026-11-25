import 'package:flutter/material.dart';

import '../../app/app_controller.dart';

/// بيانات المخبز والوكيل بعد نجاح التفعيل.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final TextEditingController _bakery = TextEditingController();
  final TextEditingController _agent = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _bakery.dispose();
    _agent.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_bakery.text.trim().isEmpty || _agent.text.trim().isEmpty) {
      setState(() => _error = 'اكتب اسم المخبز واسم الوكيل');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.completeSetup(
        bakeryName: _bakery.text,
        agentName: _agent.text,
        phone: _phone.text,
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'تعذر الحفظ: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('بيانات المخبز')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'تم التفعيل. اكتب بيانات المخبز والوكيل (تُحفظ على هذا الهاتف).',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _bakery,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'اسم المخبز',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _agent,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'اسم الوكيل',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'رقم هاتف الوكيل (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _next,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('التالي'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
