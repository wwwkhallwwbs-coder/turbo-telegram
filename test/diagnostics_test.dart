import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:makhbazak/app/diagnostics.dart';

void main() {
  group('runStage', () {
    test('يرجع نتيجة المرحلة ويسجّل اسمها', () async {
      final value = await runStage('مرحلة تجريبية', () async => 42);
      expect(value, 42);
      expect(bootStage.value, 'مرحلة تجريبية');
    });

    test('مرحلة معلّقة ترفع StageTimeoutException باسمها', () async {
      final never = Completer<int>();
      await expectLater(
        runStage(
          'فتح القاعدة',
          () => never.future,
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(
          isA<StageTimeoutException>()
              .having((e) => e.stage, 'stage', 'فتح القاعدة')
              .having((e) => e.toString(), 'text', contains('فتح القاعدة')),
        ),
      );
    });

    test('خطأ داخل المرحلة يحمل اسمها وسببها', () async {
      await expectLater(
        runStage<int>('قراءة PIN', () async => throw StateError('عطل')),
        throwsA(
          isA<StageFailure>()
              .having((e) => e.stage, 'stage', 'قراءة PIN')
              .having((e) => e.toString(), 'text', contains('عطل')),
        ),
      );
    });

    test('مرحلة داخلية فاشلة لا تُلفّ مرة ثانية بالمرحلة الخارجية', () async {
      await expectLater(
        runStage<int>(
          'خارجية',
          () => runStage<int>('داخلية', () async => throw StateError('عطل')),
        ),
        throwsA(
          isA<StageFailure>().having((e) => e.stage, 'stage', 'داخلية'),
        ),
      );
    });
  });

  test('رقم النسخة المعروض يطابق pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull);
    expect(match!.group(1), appBuildLabel);
  });
}
