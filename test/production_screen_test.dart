import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:makhbazak/data/app_database.dart';
import 'package:makhbazak/data/day_repository.dart';
import 'package:makhbazak/data/device_repository.dart';
import 'package:makhbazak/data/settings_repository.dart';
import 'package:makhbazak/features/production/production_controller.dart';
import 'package:makhbazak/features/production/production_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const List<int> _specSacks = [905, 900, 910, 895, 902, 908, 899, 905, 903, 913];

/// اختبارات عرض الشاشة. قراءة القاعدة الحقيقية (ffi) تجري داخل runAsync لأنها
/// دخل/خرج فعلي لا يعمل داخل الزمن المزيَّف، ثم تُعرض الحالة المحمّلة فقط.
void main() {
  sqfliteFfiInit();

  late String schemaSql;
  final List<Database> opened = <Database>[];

  setUpAll(() {
    schemaSql = File('assets/db/schema.sql').readAsStringSync();
  });

  // الإغلاق دخل/خرج فعلي، فيجري داخل runAsync في آخر كل اختبار.
  Future<void> closeDatabases(WidgetTester tester) async {
    await tester.runAsync<void>(() async {
      for (final db in opened) {
        await db.close();
      }
      opened.clear();
    });
  }

  Future<ProductionController> prepare(
    WidgetTester tester, {
    required Future<void> Function(Database db, DayRepository days, String dayId)
        fill,
    bool openDay = true,
    bool prices = true,
  }) async {
    final controller = await tester.runAsync<ProductionController>(() async {
      final db = await openAppDatabase(
        schemaSql: schemaSql,
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      opened.add(db);
      final device = await DeviceRepository(db).activateAsAgent(
        codeHash: 'a' * 64,
        bakeryName: 'مخبز التجربة',
        agentName: 'وكيل التجربة',
        startedAt: '2026-11-01',
      );
      final settings = SettingsRepository(
        db,
        bakeryId: device.bakeryId!,
        deviceId: device.id,
      );
      if (prices) {
        await settings.set(SettingKeys.windowPrice, 100);
        await settings.set(SettingKeys.distributionPrice, 90);
      }
      final days = DayRepository(
        db,
        bakeryId: device.bakeryId!,
        agentId: device.agentId!,
        deviceId: device.id,
      );
      final production = ProductionController(
        days: days,
        clock: () => DateTime(2026, 11, 24, 10),
      );
      await production.load();
      if (openDay) {
        await production.openDay();
        await fill(db, days, production.day!.id);
        await production.load();
      }
      return production;
    });
    return controller!;
  }

  Future<void> show(WidgetTester tester, ProductionController controller) {
    return tester.pumpWidget(
      MaterialApp(
        home: ProductionScreen(
          controller: controller,
          onOpenSettings: () async {},
        ),
      ),
    );
  }

  testWidgets('يعرض أرقام المواصفة: 9,040 والمفروض 9,000 والمتوسط 904 والفرق', (tester) async {
    final controller = await prepare(
      tester,
      fill: (db, days, dayId) async {
        for (var i = 0; i < _specSacks.length; i++) {
          await days.setSack(dayId, i + 1, _specSacks[i]);
        }
      },
    );
    await show(tester, controller);

    expect(find.text('9,040'), findsOneWidget);
    expect(find.text('9,000'), findsOneWidget);
    expect(find.text('904'), findsOneWidget);
    expect(find.text('10'), findsWidgets);
    expect(
      find.text('إنتاج اليوم زائد عن المفروض بـ 40 عيشة'),
      findsOneWidget,
    );
    expect(find.text('إضافة'), findsOneWidget);
    expect(find.text('2026-11-24'), findsOneWidget);
    await closeDatabases(tester);
  });

  testWidgets('يوم مفتوح بلا جوالات: لا سطر فرق ويُطلب أول جوال', (tester) async {
    final controller = await prepare(tester, fill: (db, days, dayId) async {});
    await show(tester, controller);

    expect(find.text('اكتب عيش أول جوال بالأسفل'), findsOneWidget);
    expect(find.textContaining('عن المفروض'), findsNothing);
    expect(find.textContaining('مطابق للمفروض'), findsNothing);
    expect(find.text('إضافة'), findsOneWidget);
    await closeDatabases(tester);
  });

  testWidgets('اليوم غير المفتوح: زر فتح اليوم', (tester) async {
    final controller = await prepare(
      tester,
      openDay: false,
      fill: (db, days, dayId) async {},
    );
    await show(tester, controller);

    expect(find.text('لم يُفتح هذا اليوم بعد'), findsOneWidget);
    expect(find.text('فتح اليوم'), findsOneWidget);
    expect(find.text('إضافة'), findsNothing);
    await closeDatabases(tester);
  });

  testWidgets('اليوم المقفل: شريط القفل بلا حقول إدخال ولا زر إضافة', (tester) async {
    final controller = await prepare(
      tester,
      fill: (db, days, dayId) async {
        await days.setSack(dayId, 1, 905);
        await db.rawUpdate(
          "UPDATE days SET status = 'locked', locked_at = '2026-11-24T20:00:00Z' WHERE id = ?",
          [dayId],
        );
      },
    );
    await show(tester, controller);

    expect(find.text(lockedDayMessage), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('إضافة'), findsNothing);
    expect(find.text('905'), findsWidgets);
    await closeDatabases(tester);
  });
}
