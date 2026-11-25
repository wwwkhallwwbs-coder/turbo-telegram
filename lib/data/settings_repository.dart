import 'package:sqflite/sqflite.dart';

import 'util.dart';

/// مفاتيح جدول settings (الوكيل هو كاتبها الوحيد).
abstract final class SettingKeys {
  static const String windowPrice = 'window_price';
  static const String distributionPrice = 'distribution_price';
  static const String targetPerSack = 'target_per_sack';
  static const String batchSizeKg = 'batch_size_kg';
  static const String sackSizeKg = 'sack_size_kg';
}

/// إعدادات مخبز واحد. القيم نصوص في القاعدة، وتُحوَّل هنا.
class SettingsRepository {
  SettingsRepository(
    this._db, {
    required this.bakeryId,
    required this.deviceId,
  });

  final DatabaseExecutor _db;
  final String bakeryId;
  final String deviceId;

  Future<String?> get(String key) async {
    final rows = await _db.query(
      'settings',
      columns: ['value'],
      where: 'bakery_id = ? AND key = ?',
      whereArgs: [bakeryId, key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['value'] as String?;
  }

  Future<int?> getInt(String key) async {
    final value = await get(key);
    return value == null ? null : int.tryParse(value);
  }

  Future<double?> getDouble(String key) async {
    final value = await get(key);
    return value == null ? null : double.tryParse(value);
  }

  /// يكتب القيمة (تحديث إن وُجدت، وإضافة إن لم توجد).
  /// لا نستعمل UPSERT لأن SQLite في أندرويد القديم (قبل 10) لا يدعمه.
  Future<void> set(String key, Object value) async {
    final text = '$value';
    final stamp = nowIso();
    final updated = await _db.update(
      'settings',
      {'value': text, 'updated_at': stamp, 'synced': 0, 'device_id': deviceId},
      where: 'bakery_id = ? AND key = ?',
      whereArgs: [bakeryId, key],
    );
    if (updated == 0) {
      await _db.insert('settings', {
        'bakery_id': bakeryId,
        'key': key,
        'value': text,
        'created_at': stamp,
        'updated_at': stamp,
        'device_id': deviceId,
      });
    }
  }
}
