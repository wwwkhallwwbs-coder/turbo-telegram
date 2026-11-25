import 'package:sqflite/sqflite.dart';

import 'models.dart';
import 'settings_repository.dart';
import 'util.dart';

/// الجهاز والتفعيل. في النسخة الأولى يُنشأ المخبز والوكيل محلياً عند التفعيل.
class DeviceRepository {
  DeviceRepository(this._db);

  final Database _db;

  /// الجهاز المُفعَّل، أو null إن لم يُفعَّل بعد.
  Future<DeviceInfo?> current() async {
    final rows = await _db.query('device', limit: 1);
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return DeviceInfo(
      id: row['id']! as String,
      role: row['role']! as String,
      bakeryId: row['bakery_id'] as String?,
      agentId: row['agent_id'] as String?,
    );
  }

  /// يفعّل الجهاز بدور وكيل: ينشئ المخبز والوكيل والربط وصف الجهاز والإعدادات
  /// الافتراضية في معاملة واحدة (إما يكتمل كله أو لا يُكتب شيء).
  ///
  /// [codeHash] بصمة رمز التفعيل (انظر `activationCodeHash`).
  /// [startedAt] تاريخ بداية الوكيل في المخبز `YYYY-MM-DD`، ولا يمكن إنشاء يوم
  /// قبله (يمنعه trigger في القاعدة). الافتراضي تاريخ اليوم.
  Future<DeviceInfo> activateAsAgent({
    required String codeHash,
    required String bakeryName,
    required String agentName,
    String? agentPhone,
    String? startedAt,
    DateTime? now,
  }) async {
    if (await current() != null) {
      throw StateError('الجهاز مُفعَّل من قبل');
    }
    final time = now ?? DateTime.now();
    final stamp = nowIso(time);
    final deviceId = newId();
    final bakeryId = newId();
    final agentId = newId();

    await _db.transaction((txn) async {
      await txn.insert('bakeries', {
        'id': bakeryId,
        'name': bakeryName,
        'device_id': deviceId,
        'created_at': stamp,
        'updated_at': stamp,
      });
      await txn.insert('agents', {
        'id': agentId,
        'name': agentName,
        'phone': agentPhone,
        'device_id': deviceId,
        'created_at': stamp,
        'updated_at': stamp,
      });
      await txn.insert('agent_bakery', {
        'id': newId(),
        'agent_id': agentId,
        'bakery_id': bakeryId,
        'started_at': startedAt ?? formatDate(time),
        'device_id': deviceId,
        'created_at': stamp,
        'updated_at': stamp,
      });
      await txn.insert('device', {
        'id': deviceId,
        'role': 'agent',
        'bakery_id': bakeryId,
        'agent_id': agentId,
        'activated_at': stamp,
        'activation_code_hash': codeHash,
        'device_id': deviceId,
        'created_at': stamp,
        'updated_at': stamp,
      });

      // الأسعار لا تُفترض: يدخلها المستخدم، ولا يُفتح يوم قبل إدخالها.
      final settings = SettingsRepository(
        txn,
        bakeryId: bakeryId,
        deviceId: deviceId,
      );
      await settings.set(SettingKeys.targetPerSack, 900);
      await settings.set(SettingKeys.sackSizeKg, 50);
      await settings.set(SettingKeys.batchSizeKg, 50);
    });

    return DeviceInfo(
      id: deviceId,
      role: 'agent',
      bakeryId: bakeryId,
      agentId: agentId,
    );
  }
}
