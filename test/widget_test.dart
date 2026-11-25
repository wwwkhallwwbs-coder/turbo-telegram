import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makhbazak/app/app_controller.dart';
import 'package:makhbazak/main.dart';

void main() {
  testWidgets('شاشة البداية تعرض اسم التطبيق واسم المصمم أثناء التحميل', (tester) async {
    // تحميل لا ينتهي، فتبقى شاشة البداية ظاهرة. بلا مدة انتظار حتى لا تبقى مؤقتات معلقة.
    await tester.pumpWidget(
      MakhbazakApp(
        loader: () => Completer<AppController>().future,
        minSplash: null,
      ),
    );

    expect(find.text('مخبزك'), findsOneWidget);
    expect(find.text('from'), findsOneWidget);
    expect(find.text('Abdo Shams'), findsOneWidget);
  });

  testWidgets('نسخ التجربة تعرض رقم النسخة على شاشة البداية', (tester) async {
    await tester.pumpWidget(
      MakhbazakApp(
        loader: () => Completer<AppController>().future,
        minSplash: null,
      ),
    );

    expect(find.textContaining('نسخة التجربة'), findsOneWidget);
  });

  testWidgets('فشل التحميل يعرض رسالة الخطأ بدل شاشة فارغة', (tester) async {
    await tester.pumpWidget(
      MakhbazakApp(
        loader: () => Future<AppController>.error(StateError('عطل تجريبي')),
        minSplash: null,
      ),
    );
    await tester.pump();

    final shown = tester.widget<SelectableText>(find.byType(SelectableText)).data;
    expect(shown, contains('تعذر تشغيل التطبيق'));
    expect(shown, contains('عطل تجريبي'));
  });
}
