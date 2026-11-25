import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:makhbazak/core/sql_script.dart';

void main() {
  test('يقسم الجداول والـ triggers ويتجاهل التعليقات وPRAGMA', () {
    const script = '''
-- تعليق
PRAGMA foreign_keys = ON;

CREATE TABLE a (
  id TEXT PRIMARY KEY,
  name TEXT
);

CREATE TRIGGER t1 BEFORE DELETE ON a
BEGIN SELECT RAISE(ABORT, 'no'); END;

CREATE TRIGGER t2 AFTER UPDATE ON a
WHEN NEW.name IS NULL
BEGIN
  UPDATE a SET name = 'x' WHERE id = NEW.id;
END;

INSERT INTO a (id) VALUES
  ('1'),
  ('2');
''';
    final statements = splitSqlScript(script);
    expect(statements.length, 4);
    expect(statements[0], startsWith('CREATE TABLE a'));
    expect(statements[2], contains("UPDATE a SET name = 'x'"));
    expect(statements[2], endsWith('END;'));
    expect(statements[3], endsWith("('2');"));
  });

  test('يرفض جملة غير منتهية', () {
    expect(
      () => splitSqlScript('CREATE TABLE a (id TEXT)'),
      throwsFormatException,
    );
  });

  test('مخطط قاعدة البيانات الفعلي ينقسم إلى جمل كاملة', () {
    final script = File('assets/db/schema.sql').readAsStringSync();
    final statements = splitSqlScript(script);
    expect(statements.length, greaterThan(60));
    for (final statement in statements) {
      expect(statement.trimRight().endsWith(';'), isTrue, reason: statement);
      expect(statement.toUpperCase().startsWith('PRAGMA'), isFalse);
    }
    expect(
      statements.where((s) => s.startsWith('CREATE TABLE')).length,
      greaterThanOrEqualTo(20),
    );
  });
}
