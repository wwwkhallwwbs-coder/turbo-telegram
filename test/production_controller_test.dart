import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:makhbazak/data/app_database.dart';
import 'package:makhbazak/data/day_repository.dart';
import 'package:makhbazak/data/device_repository.dart';
import 'package:makhbazak/data/models.dart';
import 'package:makhbazak/data/settings_repository.dart';
import 'package:makhbazak/features/production/production_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// أرقام المواصفة §4.1: المجموع 9,040، المفروض 9,000، الفرق +40، المتوسط 904.
const List<int> _specSacks = [905, 900, 910, 895, 902, 908, 899, 905, 903, 913];

void main() {
  sqfliteFfiInit();

  late Database db;
  late DeviceInfo device;
  late DayRepository days;
  late SettingsRepository settings;
  late ProductionController controller;
  late String schemaSql;

  // «اليوم» ثابت في الاختبارات: 2026-11-24، وبداية الوكيل 2026-11-23.
  final DateTime today = DateTime(2026, 11, 24, 10);

  setUpAll(() {
    schemaSql = File('assets/db/schema.sql').readAsStringSync();
  });

  setUp(() async {
    db = await openAppDatabase(
      schemaSql: schemaSql,
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    device = await DeviceRepository(db).activateAsAgent(
      codeHash: 'a' * 64,
      bakeryName: 'مخبز التجربة',
      agentName: 'وكيل التجربة',
      startedAt: '2026-11-23',
    );
    settings = SettingsRepository(
      db,
      bakeryId: device.bakeryId!,
      deviceId: device.id,
    );
    days = DayRepository(
      db,
      bakeryId: device.bakeryId!,
      agentId: device.agentId!,
      deviceId: device.id,
    );
    controller = ProductionController(days: days, clock: () => today);
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  Future<void> setPrices() async {
    await settings.set(SettingKeys.windowPrice, 100);
    await settings.set(SettingKeys.distributionPrice, 90);
  }

  Future<void> openToday() async {
    await setPrices();
    await controller.load();
    await controller.openDay();
  }

  group('التحميل وفتح اليوم', () {
    test('يبدأ بتاريخ اليوم ويوم غير مفتوح', () async {
      await setPrices();
      await controller.load();

      expect(controller.loading, isFalse);
      expect(controller.loadFailed, isFalse);
      expect(controller.date, '2026-11-24');
      expect(controller.isToday, isTrue);
      expect(controller.day, isNull);
      expect(controller.summary, isNull);
      expect(controller.sacks, isEmpty);
      expect(controller.startDate, '2026-11-23');
    });

    test('فتح اليوم بلا أسعار لا ينشئ يوماً ويطلب الإعدادات', () async {
      await controller.load();
      await controller.openDay();

      expect(controller.needsSettings, isTrue);
      expect(controller.day, isNull);
      expect(controller.error, isNull);
      final rows = await db.query('days');
      expect(rows, isEmpty);
    });

    test('بعد إدخال الأسعار يُفتح اليوم بنسخها ومستهدف الإعدادات', () async {
      await controller.load();
      await controller.openDay();
      expect(controller.needsSettings, isTrue);

      await setPrices();
      await controller.openDay();

      expect(controller.needsSettings, isFalse);
      final day = controller.day;
      expect(day, isNotNull);
      expect(day!.date, '2026-11-24');
      expect(day.windowPrice, 100);
      expect(day.distributionPrice, 90);
      expect(day.targetPerSack, 900);
      expect(day.status, 'open');
      expect(controller.summary!.sacks, 0);
      expect(controller.nextSeq, 1);
    });

    test('فتح اليوم مرتين لا ينشئ يومين', () async {
      await openToday();
      final first = controller.day!.id;
      await controller.openDay();

      expect(controller.day!.id, first);
      final rows = await db.query('days');
      expect(rows.length, 1);
    });

    test('ensureLoaded لا يعيد التحميل بعد نجاحه', () async {
      await setPrices();
      await controller.ensureLoaded();
      await controller.openDay();
      await controller.ensureLoaded();

      expect(controller.day, isNotNull);
    });
  });

  group('الجوالات والملخص', () {
    test('أرقام المواصفة: 9,040 والمفروض 9,000 والفرق +40 والمتوسط 904', () async {
      await openToday();
      for (final loaves in _specSacks) {
        await controller.addSack(loaves);
      }

      final summary = controller.summary!;
      expect(controller.sacks.length, 10);
      expect(controller.sacks.first.seq, 1);
      expect(controller.sacks.last.seq, 10);
      expect(summary.sacks, 10);
      expect(summary.total, 9040);
      expect(summary.expected, 9000);
      expect(summary.diff, 40);
      expect(summary.average, 904.0);
      expect(controller.nextSeq, 11);
      expect(controller.error, isNull);
    });

    test('تعديل جوال موجود لا يضيف جوالاً', () async {
      await openToday();
      await controller.addSack(900);
      await controller.addSack(910);
      await controller.setLoaves(1, 930);

      expect(controller.sacks.length, 2);
      expect(controller.sacks.first.loaves, 930);
      expect(controller.summary!.total, 1840);
    });

    test('إلغاء آخر جوال يُخرجه من الحساب ويعيد استعمال رقمه', () async {
      await openToday();
      await controller.addSack(900);
      await controller.addSack(880);
      await controller.cancelLastSack();

      expect(controller.sacks.length, 1);
      expect(controller.summary!.total, 900);
      expect(controller.nextSeq, 2);

      // الصف الملغى يبقى في القاعدة للتدقيق.
      final all = await db.query('sack_entries');
      expect(all.length, 2);

      await controller.addSack(895);
      expect(controller.sacks.length, 2);
      expect(controller.sacks.last.loaves, 895);
      expect((await db.query('sack_entries')).length, 2);
    });

    test('إلغاء الجوال حين لا جوالات لا يفعل شيئاً ولا يخطئ', () async {
      await openToday();
      await controller.cancelLastSack();

      expect(controller.sacks, isEmpty);
      expect(controller.error, isNull);
    });

    test('كتابات سريعة متتابعة بلا انتظار تُنفَّذ بترتيبها', () async {
      await openToday();
      final writes = <Future<void>>[
        for (var i = 0; i < 6; i++) controller.addSack(900 + i),
      ];
      await Future.wait(writes);

      expect(controller.sacks.map((e) => e.seq).toList(), [1, 2, 3, 4, 5, 6]);
      expect(
        controller.sacks.map((e) => e.loaves).toList(),
        [900, 901, 902, 903, 904, 905],
      );
      expect(controller.error, isNull);
    });

    test('الكتابة قبل فتح اليوم تُرفض برسالة', () async {
      await setPrices();
      await controller.load();
      await controller.addSack(900);

      expect(controller.error, 'افتح اليوم أولاً');
      expect(await db.query('sack_entries'), isEmpty);

      controller.dismissError();
      expect(controller.error, isNull);
    });

    test('عدد سالب يُرفض برسالة ولا يغيّر شيئاً', () async {
      await openToday();
      await controller.addSack(900);
      await controller.setLoaves(1, -5);

      expect(controller.error, isNotNull);
      expect(controller.sacks.single.loaves, 900);
    });

    test('المتحكم يُبلغ المستمعين عند كل تغيير', () async {
      await openToday();
      var calls = 0;
      controller.addListener(() => calls++);
      await controller.addSack(900);

      expect(calls, greaterThan(0));
    });
  });

  group('اليوم المقفل', () {
    Future<void> lockToday() async {
      await db.rawUpdate(
        "UPDATE days SET status = 'locked', locked_at = '2026-11-24T20:00:00Z' WHERE id = ?",
        [controller.day!.id],
      );
    }

    test('يوم مقفل عند التحميل: يظهر مقفلاً وكل كتابة عليه مرفوضة', () async {
      await openToday();
      await controller.addSack(900);
      await lockToday();
      await controller.load();

      expect(controller.isLocked, isTrue);
      await controller.addSack(1000);
      expect(controller.error, lockedDayMessage);
      controller.dismissError();
      await controller.setLoaves(1, 1000);
      expect(controller.error, lockedDayMessage);
      controller.dismissError();
      await controller.cancelLastSack();
      expect(controller.error, lockedDayMessage);

      expect(controller.sacks.single.loaves, 900);
      expect(controller.summary!.total, 900);
    });

    test('قُفل اليوم بعد التحميل: القاعدة نفسها ترفض والرسالة واحدة', () async {
      await openToday();
      await controller.addSack(900);
      // المتحكم ما زال يظن اليوم مفتوحاً، فيصل الرفض من trigger القاعدة.
      await lockToday();
      await controller.setLoaves(1, 1000);

      expect(controller.error, lockedDayMessage);
      final rows = await db.query('sack_entries');
      expect(rows.single['loaves'], 900);
    });
  });

  group('التنقل بين التواريخ', () {
    test('لا بعد اليوم ولا قبل بداية الوكيل', () async {
      await setPrices();
      await controller.load();

      expect(controller.canGoNext, isFalse);
      expect(controller.canGoPrevious, isTrue);

      await controller.goToNext();
      expect(controller.date, '2026-11-24');

      await controller.goToPrevious();
      expect(controller.date, '2026-11-23');
      expect(controller.isToday, isFalse);
      expect(controller.canGoPrevious, isFalse);
      expect(controller.canGoNext, isTrue);

      await controller.goToPrevious();
      expect(controller.date, '2026-11-23');

      await controller.goToNext();
      expect(controller.date, '2026-11-24');
    });

    test('تاريخ خارج النطاق يُقيَّد إلى اليوم أو بداية الوكيل', () async {
      await setPrices();
      await controller.load('2026-12-31');
      expect(controller.date, '2026-11-24');

      await controller.load('2020-01-01');
      expect(controller.date, '2026-11-23');
    });

    test('كل يوم له جوالاته، وفتح يوم سابق لا يمس اليوم الحالي', () async {
      await openToday();
      await controller.addSack(900);
      await controller.goToPrevious();

      expect(controller.date, '2026-11-23');
      expect(controller.day, isNull);
      expect(controller.sacks, isEmpty);

      await controller.openDay();
      await controller.addSack(870);
      await controller.addSack(880);
      expect(controller.summary!.total, 1750);

      await controller.goToNext();
      expect(controller.date, '2026-11-24');
      expect(controller.sacks.single.loaves, 900);
      expect(controller.summary!.total, 900);
      expect((await db.query('days')).length, 2);
    });

    test('يوم سابق يُنسخ إليه سعر الإعدادات الحالي عند فتحه، لا أسعار يوم آخر', () async {
      await openToday();
      await settings.set(SettingKeys.windowPrice, 120);
      await controller.goToPrevious();
      await controller.openDay();

      expect(controller.day!.windowPrice, 120);
      final todayDay = await days.find('2026-11-24');
      expect(todayDay!.windowPrice, 100);
    });
  });
}
