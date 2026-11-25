import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/diagnostics.dart';

/// شاشة البداية: «مخبزك» بشعار كبير، وتحتها في الوسط بخط صغير from / Abdo Shams.
///
/// في نسخ التجربة (debug) فقط يظهر أسفل الشاشة رقم النسخة والمرحلة الجارية من
/// التحميل، لنعرف أي بناء مثبّت وعند أي مرحلة يتوقف. في النسخة النهائية لا يظهر.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  static const Color brandGreen = Color(0xFF0E6B58);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandGreen,
      body: SafeArea(
        child: Column(
          children: [
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Logo(),
                    SizedBox(height: 22),
                    Text(
                      'مخبزك',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 60,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (kDebugMode) const _DebugStatus(),
            const Padding(
              padding: EdgeInsets.only(bottom: 44),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Column(
                  children: [
                    Text(
                      'from',
                      style: TextStyle(color: Color(0xFFD7EFE8), fontSize: 12),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Abdo Shams',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// سطر التشخيص: رقم النسخة والمرحلة الجارية (نسخ التجربة فقط).
class _DebugStatus extends StatelessWidget {
  const _DebugStatus();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
      child: ValueListenableBuilder<String>(
        valueListenable: bootStage,
        builder: (context, stage, _) {
          final lines = <String>[
            'نسخة التجربة $appBuildLabel',
            if (stage.isNotEmpty) 'جارٍ: $stage',
          ];
          return Text(
            lines.join('\n'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFD7EFE8), fontSize: 12),
          );
        },
      ),
    );
  }
}

/// شعار مؤقت (سنبلة قمح داخل دائرة)، يُستبدل لاحقاً بملف SVG من التصميم.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.6),
      ),
      child: const Icon(Icons.grain, size: 64, color: Colors.white),
    );
  }
}
