import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/sql_script.dart';

/// مسار المخطط داخل الأصول (المصدر الوحيد: assets/db/schema.sql).
const String schemaAsset = 'assets/db/schema.sql';

/// رقم إصدار القاعدة. يزيد مع كل تعديل على المخطط (مع كتابة ترحيل).
const int schemaVersion = 1;

/// يقرأ نص المخطط من أصول التطبيق.
Future<String> loadSchemaAsset() => rootBundle.loadString(schemaAsset);

/// يفتح قاعدة البيانات وينشئ الجداول والـ triggers عند أول تشغيل.
///
/// - [schemaSql] نص المخطط (في التطبيق من [loadSchemaAsset]، وفي الاختبارات من الملف).
/// - [path] مسار الملف، والافتراضي `makhbazak.db` في مجلد قواعد البيانات.
/// - [factory] للاختبارات (ffi). الافتراضي هو الذي ضبطه sqflite للهاتف.
///
/// المفاتيح الأجنبية تُفعَّل عند كل اتصال (PRAGMA لا يبقى بين الاتصالات).
Future<Database> openAppDatabase({
  required String schemaSql,
  String? path,
  DatabaseFactory? factory,
}) async {
  final dbFactory = factory ?? databaseFactory;
  final dbPath = path ?? p.join(await dbFactory.getDatabasesPath(), 'makhbazak.db');
  final statements = splitSqlScript(schemaSql);

  return dbFactory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        for (final statement in statements) {
          await db.execute(statement);
        }
      },
    ),
  );
}
