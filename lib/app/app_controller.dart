import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../core/activation.dart';
import '../core/pin_service.dart';
import '../core/secret_store.dart';
import '../data/day_repository.dart';
import '../data/device_repository.dart';
import '../data/models.dart';
import '../data/settings_repository.dart';
import '../data/util.dart';
import 'diagnostics.dart';

/// مراحل التطبيق عند الفتح:
/// تفعيل ← بيانات المخبز والوكيل ← إنشاء PIN ← (قفل / مفتوح).
enum AppStage { needsActivation, needsSetup, needsPin, locked, unlocked }

/// مفتاح كود الجهاز في [SecretStore].
const String deviceCodeKey = 'device_code';

/// رسالة موحدة لأي رمز مرفوض، فلا نكشف السبب لمن يجرّب.
const String invalidActivationMessage = 'الرمز غير صالح لهذا الجهاز';

class _PendingActivation {
  const _PendingActivation(this.codeHash);

  final String codeHash;
}

/// حالة التطبيق: التفعيل والجهاز وقفل PIN. الشاشات تستدعيه ولا تلمس القاعدة.
class AppController extends ChangeNotifier {
  AppController._({
    required this.db,
    required this.secrets,
    required this.activationPublicKey,
    DateTime Function()? clock,
  })  : devices = DeviceRepository(db),
        pin = PinService(secrets, clock: clock);

  /// يجهّز المتحكم ويقرأ حالة الجهاز المحفوظة.
  static Future<AppController> open({
    required Database db,
    required SecretStore secrets,
    required List<int>? activationPublicKey,
    DateTime Function()? clock,
  }) async {
    final controller = AppController._(
      db: db,
      secrets: secrets,
      activationPublicKey: activationPublicKey,
      clock: clock,
    );
    await controller._load();
    return controller;
  }

  final Database db;
  final SecretStore secrets;

  /// المفتاح العام للتفعيل، أو null إن لم يُضبط في التطبيق بعد.
  final List<int>? activationPublicKey;
  final DeviceRepository devices;
  final PinService pin;

  late String deviceCode;
  DeviceInfo? device;
  String? bakeryName;
  bool _hasPin = false;
  bool _unlocked = false;
  _PendingActivation? _pending;

  Future<void> _load() async {
    var code = await runStage(
      'قراءة كود الجهاز من التخزين الآمن',
      () => secrets.read(deviceCodeKey),
    );
    if (code == null) {
      code = generateDeviceCode();
      final fresh = code;
      await runStage(
        'حفظ كود الجهاز في التخزين الآمن',
        () => secrets.write(deviceCodeKey, fresh),
      );
    }
    deviceCode = code;
    device = await runStage('قراءة بيانات الجهاز', devices.current);
    _hasPin = await runStage('قراءة حالة رمز PIN', pin.isSet);
    await runStage('قراءة اسم المخبز', _loadBakeryName);
  }

  Future<void> _loadBakeryName() async {
    final bakeryId = device?.bakeryId;
    if (bakeryId == null) {
      bakeryName = null;
      return;
    }
    final rows = await db.query(
      'bakeries',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [bakeryId],
      limit: 1,
    );
    bakeryName = rows.isEmpty ? null : rows.first['name'] as String?;
  }

  AppStage get stage {
    if (device == null) {
      return _pending == null ? AppStage.needsActivation : AppStage.needsSetup;
    }
    if (!_hasPin) {
      return AppStage.needsPin;
    }
    return _unlocked ? AppStage.unlocked : AppStage.locked;
  }

  /// يتحقق من رمز التفعيل. يرجع رسالة الخطأ، أو null عند النجاح.
  Future<String?> submitActivationCode(String code) async {
    final key = activationPublicKey;
    if (key == null) {
      return 'التفعيل غير مُهيّأ في هذه النسخة. تواصل مع المصمم.';
    }
    try {
      final info = await verifyActivationCode(
        code: code,
        deviceCode: deviceCode,
        publicKey: key,
      );
      if (info.role != 'agent') {
        return 'هذا الرمز لتطبيق المالك، وهو غير متاح في هذه النسخة.';
      }
      _pending = _PendingActivation(await activationCodeHash(code));
      notifyListeners();
      return null;
    } on ActivationException {
      return invalidActivationMessage;
    }
  }

  /// للتجربة فقط: يتخطى التفعيل. مرفوض في النسخ النهائية.
  void skipActivationForTesting() {
    if (!kDebugMode) {
      throw StateError('تخطي التفعيل متاح في نسخ التجربة فقط');
    }
    _pending = const _PendingActivation('debug-skip');
    notifyListeners();
  }

  /// يكمل التفعيل: ينشئ المخبز والوكيل والجهاز في القاعدة.
  ///
  /// بداية الوكيل في المخبز تُضبط على أول الشهر الحالي، فيمكن إدخال أيام سابقة
  /// من هذا الشهر (لا يُنشأ يوم قبل هذا التاريخ).
  Future<void> completeSetup({
    required String bakeryName,
    required String agentName,
    String? phone,
    DateTime? now,
  }) async {
    final pending = _pending;
    if (pending == null) {
      throw StateError('لم يتم التحقق من رمز التفعيل بعد');
    }
    final bakery = bakeryName.trim();
    final agent = agentName.trim();
    if (bakery.isEmpty || agent.isEmpty) {
      throw ArgumentError('اسم المخبز واسم الوكيل مطلوبان');
    }
    final time = now ?? DateTime.now();
    final phoneText = phone?.trim();
    device = await devices.activateAsAgent(
      codeHash: pending.codeHash,
      bakeryName: bakery,
      agentName: agent,
      agentPhone: (phoneText == null || phoneText.isEmpty) ? null : phoneText,
      startedAt: formatDate(DateTime(time.year, time.month, 1)),
      now: time,
    );
    _pending = null;
    await _loadBakeryName();
    notifyListeners();
  }

  /// ينشئ رمز PIN ويفتح التطبيق.
  Future<void> createPin(String value) async {
    await pin.setPin(value);
    _hasPin = true;
    _unlocked = true;
    notifyListeners();
  }

  /// يفحص PIN، وعند النجاح يفتح التطبيق.
  Future<PinCheck> unlock(String value) async {
    final result = await pin.check(value);
    if (result.isOk) {
      _unlocked = true;
      notifyListeners();
    }
    return result;
  }

  void lock() {
    if (_unlocked) {
      _unlocked = false;
      notifyListeners();
    }
  }

  DeviceInfo _activatedDevice() {
    final info = device;
    if (info == null || info.bakeryId == null || info.agentId == null) {
      throw StateError('الجهاز غير مُفعَّل');
    }
    return info;
  }

  SettingsRepository get settings {
    final info = _activatedDevice();
    return SettingsRepository(
      db,
      bakeryId: info.bakeryId!,
      deviceId: info.id,
    );
  }

  DayRepository get days {
    final info = _activatedDevice();
    return DayRepository(
      db,
      bakeryId: info.bakeryId!,
      agentId: info.agentId!,
      deviceId: info.id,
    );
  }
}
