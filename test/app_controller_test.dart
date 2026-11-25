import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:makhbazak/app/app_controller.dart';
import 'package:makhbazak/core/pin_service.dart';
import 'package:makhbazak/core/secret_store.dart';
import 'package:makhbazak/data/app_database.dart';
import 'package:makhbazak/data/settings_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// نفس متجه الاختبار في activation_test.dart: رمز مربوط بكود الجهاز K7QZ2MWD4A.
const String _publicKey = 'hHl28fyv8oURVyqMHXApwC/YpJZMJVQC46BkGsB5evQ=';
const String _device = 'K7QZ2MWD4A';
const String _code =
    'MKZ1-XMWJM-M5GU6-H2FYD-2G77B-4FPZ4-K3OU2-MCSHF-X5NQK-J3BGN-JY6VY-5VC5B-'
    'CARR5-CYTYC-3FDEB-OWB5W-FBIYQ-RZTNM-J2IKP-7XQ2J-7BQZX-2CKNJ-NNDC7-DBM5S-'
    'W45D4-JM3VC-WRSJV-LUINC-BPQZD-AMRWG-EYTEM-I';

void main() {
  sqfliteFfiInit();

  late Database db;
  late MemorySecretStore secrets;
  late DateTime now;
  late String schemaSql;

  setUpAll(() {
    schemaSql = File('assets/db/schema.sql').readAsStringSync();
  });

  setUp(() async {
    db = await openAppDatabase(
      schemaSql: schemaSql,
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    secrets = MemorySecretStore({deviceCodeKey: _device});
    now = DateTime(2026, 11, 24, 10);
  });

  tearDown(() async {
    await db.close();
  });

  Future<AppController> openController({List<int>? key}) => AppController.open(
        db: db,
        secrets: secrets,
        activationPublicKey: key ?? base64.decode(_publicKey),
        clock: () => now,
      );

  test('أول تشغيل: يحتاج تفعيلاً، ويولّد كود جهاز ويحفظه', () async {
    secrets = MemorySecretStore();
    final first = await openController();
    expect(first.stage, AppStage.needsActivation);
    expect(RegExp(r'^[A-Z2-7]{10}$').hasMatch(first.deviceCode), isTrue);

    // إعادة الفتح تعطي الكود نفسه، فلا يتغير على المستخدم.
    final second = await openController();
    expect(second.deviceCode, first.deviceCode);
  });

  test('رمز خاطئ يُرفض برسالة موحدة ولا تتغير المرحلة', () async {
    final controller = await openController();
    final error = await controller.submitActivationCode('MKZ1-AAAAA-AAAAA');
    expect(error, invalidActivationMessage);
    expect(controller.stage, AppStage.needsActivation);
  });

  test('رمز مربوط بجهاز آخر يُرفض بنفس الرسالة', () async {
    secrets = MemorySecretStore({deviceCodeKey: 'K7QZ2MWD4B'});
    final controller = await openController();
    expect(await controller.submitActivationCode(_code), invalidActivationMessage);
    expect(controller.stage, AppStage.needsActivation);
  });

  test('بدون مفتاح عام مضبوط لا يُقبل أي رمز', () async {
    final controller = await AppController.open(
      db: db,
      secrets: secrets,
      activationPublicKey: null,
      clock: () => now,
    );
    final error = await controller.submitActivationCode(_code);
    expect(error, isNotNull);
    expect(error, isNot(invalidActivationMessage));
    expect(controller.stage, AppStage.needsActivation);
  });

  test('المسار الكامل: تفعيل ← بيانات ← PIN ← قفل ← فتح', () async {
    final controller = await openController();
    var notifications = 0;
    controller.addListener(() => notifications++);

    expect(await controller.submitActivationCode(_code), isNull);
    expect(controller.stage, AppStage.needsSetup);

    await controller.completeSetup(
      bakeryName: '  مخبز النور ',
      agentName: 'أحمد',
      phone: '0912345678',
      now: now,
    );
    expect(controller.stage, AppStage.needsPin);
    expect(controller.bakeryName, 'مخبز النور');

    await controller.createPin('1234');
    expect(controller.stage, AppStage.unlocked);
    expect(notifications, greaterThanOrEqualTo(3));

    controller.lock();
    expect(controller.stage, AppStage.locked);

    expect((await controller.unlock('0000')).status, PinStatus.wrong);
    expect(controller.stage, AppStage.locked);
    expect((await controller.unlock('1234')).isOk, isTrue);
    expect(controller.stage, AppStage.unlocked);
  });

  test('الجهاز المُفعَّل يحفظ بصمة الرمز لا الرمز نفسه، وبداية الوكيل أول الشهر', () async {
    final controller = await openController();
    await controller.submitActivationCode(_code);
    await controller.completeSetup(bakeryName: 'مخبز', agentName: 'وكيل', now: now);

    final device = await db.query('device');
    expect(device.length, 1);
    final hash = device.first['activation_code_hash'] as String;
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), isTrue);

    final link = await db.query('agent_bakery');
    expect(link.first['started_at'], '2026-11-01');
  });

  test('إعادة فتح التطبيق بعد الإعداد تطلب PIN، والبيانات محفوظة', () async {
    final first = await openController();
    await first.submitActivationCode(_code);
    await first.completeSetup(bakeryName: 'مخبز النور', agentName: 'أحمد', now: now);
    await first.createPin('1234');

    final reopened = await openController();
    expect(reopened.stage, AppStage.locked);
    expect(reopened.bakeryName, 'مخبز النور');
    expect((await reopened.unlock('1234')).isOk, isTrue);
  });

  test('الإغلاق بعد إنشاء الجهاز وقبل إنشاء PIN يرجع لإنشاء PIN', () async {
    final first = await openController();
    await first.submitActivationCode(_code);
    await first.completeSetup(bakeryName: 'مخبز', agentName: 'وكيل', now: now);

    final reopened = await openController();
    expect(reopened.stage, AppStage.needsPin);
  });

  test('بيانات ناقصة أو إعداد قبل التفعيل مرفوضان', () async {
    final controller = await openController();
    await expectLater(
      controller.completeSetup(bakeryName: 'مخبز', agentName: 'وكيل'),
      throwsStateError,
    );
    await controller.submitActivationCode(_code);
    await expectLater(
      controller.completeSetup(bakeryName: '  ', agentName: 'وكيل'),
      throwsArgumentError,
    );
    expect(controller.stage, AppStage.needsSetup);
  });

  test('تخطي التفعيل للتجربة يعمل في نسخ التجربة والاختبار', () async {
    final controller = await openController(key: const <int>[]);
    controller.skipActivationForTesting();
    expect(controller.stage, AppStage.needsSetup);
    await controller.completeSetup(bakeryName: 'مخبز', agentName: 'وكيل', now: now);
    expect(controller.stage, AppStage.needsPin);
  });

  test('بعد الإعداد تعمل الإعدادات والأيام على مخبز الجهاز', () async {
    final controller = await openController();
    await controller.submitActivationCode(_code);
    await controller.completeSetup(bakeryName: 'مخبز', agentName: 'وكيل', now: now);

    await controller.settings.set(SettingKeys.windowPrice, 100);
    await controller.settings.set(SettingKeys.distributionPrice, 90);
    // اليوم داخل الشهر الذي بدأ فيه الوكيل (أول الشهر الحالي).
    final day = await controller.days.getOrCreate('2026-11-03');
    expect(day.windowPrice, 100);
    expect(day.targetPerSack, 900);
  });

  test('المستودعات غير متاحة قبل التفعيل', () async {
    final controller = await openController();
    expect(() => controller.settings, throwsStateError);
    expect(() => controller.days, throwsStateError);
  });
}
