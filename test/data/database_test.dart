import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:makhbazak/data/app_database.dart';
import 'package:makhbazak/data/day_repository.dart';
import 'package:makhbazak/data/device_repository.dart';
import 'package:makhbazak/data/models.dart';
import 'package:makhbazak/data/settings_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// أرقام المواصفة §4.1: 10 جوالات، المجموع 9,040، المفروض 9,000، الفرق +40، المتوسط 904.
const List<int> _specSacks = [905, 900, 910, 895, 902, 908, 899, 905, 903, 913];

void main() {
  sqfliteFfiInit();

  late Database db;
  late DeviceInfo device;
  late DayRepository days;
  late SettingsRepository settings;
  late String schemaSql;

  setUpAll(() {
    // الاختبارات تعمل من جذر المشروع.
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
      startedAt: '2026-01-01',
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
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> setPrices() async {
    await settings.set(SettingKeys.windowPrice, 100);
    await settings.set(SettingKeys.distributionPrice, 90);
  }

  group('فتح القاعدة', () {
    test('ينشئ الجداول والـ triggers من المخطط الحقيقي', () async {
      final tables = await db.rawQuery(
        "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
      );
      final triggers = await db.rawQuery(
        "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'trigger'",
      );
      expect(tables.first['n'], 20);
      expect(triggers.first['n'], 37);
    });

    test('المفاتيح الأجنبية مفعلة', () async {
      final result = await db.rawQuery('PRAGMA foreign_keys');
      expect(result.first['foreign_keys'], 1);
    });
  });

  group('التفعيل', () {
    test('ينشئ المخبز والوكيل والجهاز والإعدادات الافتراضية', () async {
      final current = await DeviceRepository(db).current();
      expect(current, isNotNull);
      expect(current!.role, 'agent');
      expect(current.bakeryId, device.bakeryId);
      expect(current.agentId, device.agentId);
      expect(await settings.getInt(SettingKeys.targetPerSack), 900);
      expect(await settings.getDouble(SettingKeys.batchSizeKg), 50.0);
      expect(await settings.getDouble(SettingKeys.sackSizeKg), 50.0);
      // الأسعار لا تُفترض.
      expect(await settings.getInt(SettingKeys.windowPrice), isNull);
    });

    test('لا يُفعَّل الجهاز مرتين', () async {
      await expectLater(
        DeviceRepository(db).activateAsAgent(
          codeHash: 'b' * 64,
          bakeryName: 'آخر',
          agentName: 'آخر',
        ),
        throwsStateError,
      );
    });
  });

  group('الإعدادات', () {
    test('الكتابة تحدّث القيمة الموجودة ولا تكرر الصف', () async {
      await settings.set(SettingKeys.windowPrice, 100);
      await settings.set(SettingKeys.windowPrice, 120);
      expect(await settings.getInt(SettingKeys.windowPrice), 120);
      final rows = await db.query(
        'settings',
        where: 'key = ?',
        whereArgs: [SettingKeys.windowPrice],
      );
      expect(rows.length, 1);
    });
  });

  group('اليوم', () {
    test('لا يُفتح يوم قبل إدخال الأسعار', () async {
      await expectLater(days.getOrCreate('2026-11-21'), throwsStateError);
    });

    test('ينسخ الأسعار والمستهدف إلى اليوم، فلا يتغير حسابه لاحقاً', () async {
      await setPrices();
      final day = await days.getOrCreate('2026-11-21');
      expect(day.windowPrice, 100);
      expect(day.distributionPrice, 90);
      expect(day.targetPerSack, 900);
      expect(day.batchSizeKg, 50.0);
      expect(day.status, 'open');

      await settings.set(SettingKeys.windowPrice, 150);
      final again = await days.getOrCreate('2026-11-21');
      expect(again.id, day.id);
      expect(again.windowPrice, 100);
    });

    test('تاريخ بصيغة خاطئة يُرفض', () async {
      await setPrices();
      await expectLater(days.getOrCreate('21/11/2026'), throwsArgumentError);
    });

    test('لا يُنشأ يوم قبل تاريخ بداية الوكيل (trigger)', () async {
      await setPrices();
      await expectLater(
        days.getOrCreate('2025-12-31'),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('القطعيات', () {
    late DayRecord day;

    setUp(() async {
      await setPrices();
      day = await days.getOrCreate('2026-11-21');
      for (var i = 0; i < _specSacks.length; i++) {
        await days.setSack(day.id, i + 1, _specSacks[i]);
      }
    });

    test('ملخص الإنتاج يطابق أرقام المواصفة', () async {
      final summary = await days.production(day);
      expect(summary.sacks, 10);
      expect(summary.total, 9040);
      expect(summary.expected, 9000);
      expect(summary.diff, 40);
      expect(summary.average, 904.0);
    });

    test('تعديل قطعيات جوال موجود لا يضيف صفاً جديداً', () async {
      await days.setSack(day.id, 1, 915);
      final entries = await days.sacks(day.id);
      expect(entries.length, 10);
      expect(entries.first.loaves, 915);
      expect((await days.production(day)).total, 9050);
    });

    test('الإلغاء يُخرج الجوال من الحساب ويبقي الصف، وإعادة التسجيل تحييه', () async {
      await days.cancelSack(day.id, 10);
      expect((await days.sacks(day.id)).length, 9);
      expect((await days.production(day)).total, 9040 - 913);

      final all = await db.query(
        'sack_entries',
        where: 'day_id = ?',
        whereArgs: [day.id],
      );
      expect(all.length, 10);

      await days.setSack(day.id, 10, 913);
      expect((await days.sacks(day.id)).length, 10);
      expect((await days.production(day)).total, 9040);
    });

    test('مدخلات غير صالحة تُرفض قبل القاعدة', () async {
      await expectLater(days.setSack(day.id, 0, 10), throwsArgumentError);
      await expectLater(days.setSack(day.id, 1, -5), throwsArgumentError);
    });

    test('لا حذف فعلي: DELETE يرفضه المخطط', () async {
      await expectLater(
        db.rawDelete('DELETE FROM sack_entries WHERE day_id = ?', [day.id]),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('اليوم المقفل للقراءة فقط: الإضافة والتعديل والإلغاء مرفوضة', () async {
      await db.rawUpdate(
        "UPDATE days SET status = 'locked', locked_at = '2026-11-21T20:00:00Z' WHERE id = ?",
        [day.id],
      );
      await expectLater(
        days.setSack(day.id, 1, 1000),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        days.setSack(day.id, 11, 900),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        days.cancelSack(day.id, 2),
        throwsA(isA<DatabaseException>()),
      );
      // القراءة تعمل، والمجموع كما كان.
      expect((await days.production(day)).total, 9040);
    });
  });
}
