import 'package:sqflite/sqflite.dart';

import '../core/accounting.dart';
import 'models.dart';
import 'settings_repository.dart';
import 'util.dart';

final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// اليوم وقطعيات الجوالات. لا حذف فعلي: الإلغاء بـ cancelled_at.
///
/// اليوم المقفل للقراءة فقط: أي كتابة عليه ترفعها القاعدة نفسها
/// (DatabaseException من الـ triggers)، مهما كان الكود الذي استدعاها.
class DayRepository {
  DayRepository(
    this._db, {
    required this.bakeryId,
    required this.agentId,
    required this.deviceId,
  });

  final Database _db;
  final String bakeryId;
  final String agentId;
  final String deviceId;

  DayRecord _day(Map<String, Object?> row) => DayRecord(
        id: row['id']! as String,
        date: row['date']! as String,
        status: row['status']! as String,
        windowPrice: row['window_price']! as int,
        distributionPrice: row['distribution_price']! as int,
        targetPerSack: row['target_per_sack']! as int,
        batchSizeKg: (row['batch_size_kg']! as num).toDouble(),
      );

  Future<DayRecord?> find(String date) async {
    final rows = await _db.query(
      'days',
      where: 'bakery_id = ? AND date = ?',
      whereArgs: [bakeryId, date],
      limit: 1,
    );
    return rows.isEmpty ? null : _day(rows.first);
  }

  /// يرجع اليوم إن وُجد، وإلا ينشئه ناسخاً الأسعار والمستهدف من الإعدادات.
  Future<DayRecord> getOrCreate(String date) async {
    if (!_datePattern.hasMatch(date)) {
      throw ArgumentError.value(date, 'date', 'التاريخ بصيغة YYYY-MM-DD');
    }
    final existing = await find(date);
    if (existing != null) {
      return existing;
    }

    final opening = await _readOpeningSettings();
    if (opening == null) {
      throw StateError(
        'أكمل الإعدادات (سعر الشباك وسعر التوزيع والمستهدف وحجم العجنة) قبل فتح يوم جديد',
      );
    }

    final stamp = nowIso();
    await _db.insert('days', {
      'id': newId(),
      'bakery_id': bakeryId,
      'agent_id': agentId,
      'date': date,
      'window_price': opening.windowPrice,
      'distribution_price': opening.distributionPrice,
      'target_per_sack': opening.targetPerSack,
      'batch_size_kg': opening.batchSizeKg,
      'device_id': deviceId,
      'created_at': stamp,
      'updated_at': stamp,
    });
    final created = await find(date);
    if (created == null) {
      throw StateError('تعذر إنشاء اليوم $date');
    }
    return created;
  }

  /// هل الإعدادات اللازمة لفتح يوم جديد مكتملة؟
  Future<bool> hasOpeningSettings() async => await _readOpeningSettings() != null;

  /// تاريخ بداية الوكيل في المخبز (أقدم يوم يمكن فتحه)، أو null إن لم يوجد ربط نشط.
  Future<String?> agentStartDate() async {
    final rows = await _db.query(
      'agent_bakery',
      columns: ['started_at'],
      where: 'bakery_id = ? AND agent_id = ? AND ended_at IS NULL',
      whereArgs: [bakeryId, agentId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['started_at'] as String?;
  }

  Future<_OpeningSettings?> _readOpeningSettings() async {
    final settings = SettingsRepository(
      _db,
      bakeryId: bakeryId,
      deviceId: deviceId,
    );
    final windowPrice = await settings.getInt(SettingKeys.windowPrice);
    final distributionPrice =
        await settings.getInt(SettingKeys.distributionPrice);
    final target = await settings.getInt(SettingKeys.targetPerSack);
    final batch = await settings.getDouble(SettingKeys.batchSizeKg);
    if (windowPrice == null ||
        distributionPrice == null ||
        target == null ||
        batch == null) {
      return null;
    }
    return _OpeningSettings(
      windowPrice: windowPrice,
      distributionPrice: distributionPrice,
      targetPerSack: target,
      batchSizeKg: batch,
    );
  }

  /// يسجل قطعيات الجوال رقم [seq]، ويعيد إحياء الجوال الملغى إن وُجد.
  Future<void> setSack(String dayId, int seq, int loaves) async {
    if (seq <= 0) {
      throw ArgumentError.value(seq, 'seq', 'رقم الجوال يبدأ من 1');
    }
    if (loaves < 0) {
      throw ArgumentError.value(loaves, 'loaves', 'عدد العيش لا يكون سالباً');
    }
    final stamp = nowIso();
    await _db.transaction((txn) async {
      final updated = await txn.update(
        'sack_entries',
        {
          'loaves': loaves,
          'cancelled_at': null,
          'updated_at': stamp,
          'synced': 0,
          'device_id': deviceId,
        },
        where: 'day_id = ? AND seq = ?',
        whereArgs: [dayId, seq],
      );
      if (updated == 0) {
        await txn.insert('sack_entries', {
          'id': newId(),
          'day_id': dayId,
          'seq': seq,
          'loaves': loaves,
          'device_id': deviceId,
          'created_at': stamp,
          'updated_at': stamp,
        });
      }
    });
  }

  /// يلغي قطعيات الجوال رقم [seq] (يبقى الصف للتدقيق ولا يدخل الحساب).
  Future<void> cancelSack(String dayId, int seq) async {
    final stamp = nowIso();
    await _db.update(
      'sack_entries',
      {
        'cancelled_at': stamp,
        'updated_at': stamp,
        'synced': 0,
        'device_id': deviceId,
      },
      where: 'day_id = ? AND seq = ? AND cancelled_at IS NULL',
      whereArgs: [dayId, seq],
    );
  }

  /// قطعيات اليوم الفعالة مرتبة برقم الجوال.
  Future<List<SackEntry>> sacks(String dayId) async {
    final rows = await _db.query(
      'sack_entries',
      columns: ['seq', 'loaves'],
      where: 'day_id = ? AND cancelled_at IS NULL',
      whereArgs: [dayId],
      orderBy: 'seq',
    );
    return rows
        .map(
          (row) => SackEntry(
            seq: row['seq']! as int,
            loaves: row['loaves']! as int,
          ),
        )
        .toList();
  }

  /// ملخص إنتاج اليوم (المجموع والمفروض والفرق والمتوسط) من معادلات lib/core.
  Future<ProductionSummary> production(DayRecord day) async {
    final entries = await sacks(day.id);
    return summarizeProduction(
      loavesPerSack: entries.map((entry) => entry.loaves).toList(),
      targetPerSack: day.targetPerSack,
    );
  }
}

/// الإعدادات التي تُنسخ إلى اليوم عند فتحه.
class _OpeningSettings {
  const _OpeningSettings({
    required this.windowPrice,
    required this.distributionPrice,
    required this.targetPerSack,
    required this.batchSizeKg,
  });

  final int windowPrice;
  final int distributionPrice;
  final int targetPerSack;
  final double batchSizeKg;
}
