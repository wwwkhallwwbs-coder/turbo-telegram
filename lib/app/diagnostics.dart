import 'package:flutter/foundation.dart';

/// رقم النسخة المعروض على شاشة البداية في نسخ التجربة (debug) فقط.
/// يطابق `version:` في pubspec.yaml (يفحص ذلك test/diagnostics_test.dart).
const String appBuildLabel = '0.2.0+2';

/// أقصى مدة لكل مرحلة من مراحل التحميل قبل أن نعتبرها معلّقة.
const Duration defaultStageTimeout = Duration(seconds: 20);

/// المرحلة الجارية من تحميل التطبيق. تظهر تحت شعار البداية في نسخ التجربة،
/// فإذا علق التحميل نعرف عند أي مرحلة علق.
final ValueNotifier<String> bootStage = ValueNotifier<String>('');

/// مرحلة تحميل لم تنتهِ في وقتها.
class StageTimeoutException implements Exception {
  const StageTimeoutException(this.stage, this.timeout);

  final String stage;
  final Duration timeout;

  @override
  String toString() =>
      'توقّف التحميل عند «$stage» أكثر من ${timeout.inSeconds} ثانية';
}

/// يشغّل [action] باسم المرحلة [stage]، ويرفع [StageTimeoutException] إن تأخر
/// عن [timeout]. أي خطأ آخر يمر كما هو مع اسم المرحلة في نصه.
Future<T> runStage<T>(
  String stage,
  Future<T> Function() action, {
  Duration timeout = defaultStageTimeout,
}) async {
  bootStage.value = stage;
  try {
    return await action().timeout(
      timeout,
      onTimeout: () => throw StageTimeoutException(stage, timeout),
    );
  } on StageTimeoutException {
    rethrow;
  } on StageFailure {
    // مرحلة داخلية سمّت نفسها بالفعل: لا نلفّها مرة ثانية.
    rethrow;
  } on Object catch (error) {
    throw StageFailure(stage, error);
  }
}

/// خطأ أثناء مرحلة تحميل، يحمل اسم المرحلة والخطأ الأصلي.
class StageFailure implements Exception {
  const StageFailure(this.stage, this.cause);

  final String stage;
  final Object cause;

  @override
  String toString() => 'تعذّر «$stage»:\n$cause';
}
