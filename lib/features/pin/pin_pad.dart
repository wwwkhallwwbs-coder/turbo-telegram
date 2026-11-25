import 'package:flutter/material.dart';

/// لوحة أرقام لإدخال رمز PIN. عند اكتمال [length] أرقام تستدعي [onCompleted]
/// ثم تفرّغ نفسها، والشاشة التي تستعملها هي التي تقرر ما يحدث بعد ذلك.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onCompleted,
    this.length = 4,
    this.enabled = true,
  });

  final ValueChanged<String> onCompleted;
  final int length;
  final bool enabled;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _value = '';

  void _digit(String digit) {
    if (!widget.enabled || _value.length >= widget.length) {
      return;
    }
    final next = _value + digit;
    if (next.length == widget.length) {
      setState(() => _value = '');
      widget.onCompleted(next);
    } else {
      setState(() => _value = next);
    }
  }

  void _backspace() {
    if (_value.isEmpty) {
      return;
    }
    setState(() => _value = _value.substring(0, _value.length - 1));
  }

  Widget _digitKey(String digit) {
    return SizedBox(
      width: 84,
      height: 64,
      child: TextButton(
        onPressed: widget.enabled ? () => _digit(digit) : null,
        child: Text(digit, style: const TextStyle(fontSize: 26)),
      ),
    );
  }

  Widget _row(List<String> digits) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (final digit in digits) _digitKey(digit)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.length; i++)
              Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _value.length ? color : Colors.transparent,
                  border: Border.all(color: color, width: 2),
                ),
              ),
          ],
        ),
        const SizedBox(height: 28),
        // لوحة الأرقام تبقى بترتيبها المعتاد 1-2-3 من اليسار حتى في الواجهة العربية.
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _row(const ['1', '2', '3']),
              _row(const ['4', '5', '6']),
              _row(const ['7', '8', '9']),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 84, height: 64),
                  _digitKey('0'),
                  SizedBox(
                    width: 84,
                    height: 64,
                    child: IconButton(
                      tooltip: 'مسح',
                      onPressed: widget.enabled ? _backspace : null,
                      icon: const Icon(Icons.backspace_outlined),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
