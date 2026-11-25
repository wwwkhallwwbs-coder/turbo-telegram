import 'package:flutter_test/flutter_test.dart';
import 'package:makhbazak/core/pin_service.dart';
import 'package:makhbazak/core/secret_store.dart';

void main() {
  late MemorySecretStore store;
  late DateTime now;
  late PinService service;

  setUp(() {
    store = MemorySecretStore();
    now = DateTime(2026, 11, 24, 10);
    // عدد تكرارات قليل لتسريع الاختبار فقط.
    service = PinService(store, clock: () => now, iterations: 10);
  });

  test('لا رمز قبل الإنشاء', () async {
    expect(await service.isSet(), isFalse);
    await expectLater(service.check('1234'), throwsStateError);
  });

  test('إنشاء الرمز ثم فحصه', () async {
    await service.setPin('1234');
    expect(await service.isSet(), isTrue);
    expect((await service.check('1234')).isOk, isTrue);
    expect((await service.check('4321')).status, PinStatus.wrong);
  });

  test('لا يُحفظ الرمز نفسه في التخزين', () async {
    await service.setPin('1234');
    for (final key in ['pin_hash', 'pin_salt']) {
      final value = await store.read(key);
      expect(value, isNotNull);
      expect(value, isNot(contains('1234')));
    }
  });

  test('تنسيق غير صالح يُرفض عند الإنشاء ويُعد خطأً عند الفحص', () async {
    for (final bad in ['123', '12345', 'abcd', '12 4', '']) {
      await expectLater(service.setPin(bad), throwsArgumentError, reason: bad);
    }
    await service.setPin('1234');
    expect((await service.check('12')).status, PinStatus.wrong);
  });

  test('المحاولات المتبقية تنقص، والنجاح يصفّر العدّاد', () async {
    await service.setPin('1234');
    expect((await service.check('0000')).attemptsLeft, 4);
    expect((await service.check('0000')).attemptsLeft, 3);
    expect((await service.check('1234')).isOk, isTrue);
    expect((await service.check('0000')).attemptsLeft, 4);
  });

  test('5 محاولات خاطئة تُوقف الفحص 5 دقائق ولو أُدخل الرمز الصحيح', () async {
    await service.setPin('1234');
    for (var i = 0; i < PinService.maxAttempts - 1; i++) {
      expect((await service.check('0000')).status, PinStatus.wrong);
    }
    final fifth = await service.check('0000');
    expect(fifth.status, PinStatus.lockedOut);
    expect(fifth.lockedUntil, now.add(PinService.lockoutDuration));

    // أثناء الإيقاف: حتى الرمز الصحيح مرفوض.
    now = now.add(const Duration(minutes: 4));
    expect((await service.check('1234')).status, PinStatus.lockedOut);

    // بعد انتهاء المدة يعمل الرمز الصحيح.
    now = now.add(const Duration(minutes: 2));
    expect((await service.check('1234')).isOk, isTrue);
  });

  test('بعد انتهاء الإيقاف يبدأ العدّاد من جديد', () async {
    await service.setPin('1234');
    for (var i = 0; i < PinService.maxAttempts; i++) {
      await service.check('0000');
    }
    now = now.add(const Duration(minutes: 6));
    expect((await service.check('0000')).attemptsLeft, 4);
  });

  test('تغيير الرمز يلغي القديم ويصفّر الإيقاف', () async {
    await service.setPin('1234');
    for (var i = 0; i < PinService.maxAttempts; i++) {
      await service.check('0000');
    }
    await service.setPin('5678');
    expect((await service.check('1234')).status, PinStatus.wrong);
    expect((await service.check('5678')).isOk, isTrue);
  });

  test('الملح عشوائي: نفس الرمز يعطي بصمتين مختلفتين', () async {
    final other = MemorySecretStore();
    await service.setPin('1234');
    await PinService(other, iterations: 10).setPin('1234');
    expect(await store.read('pin_hash'), isNot(await other.read('pin_hash')));
  });
}
