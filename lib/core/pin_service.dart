import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'secret_store.dart';

enum PinStatus { ok, wrong, lockedOut }

/// نتيجة فحص رمز PIN.
class PinCheck {
  const PinCheck._(this.status, {this.attemptsLeft = 0, this.lockedUntil});

  const PinCheck.ok() : this._(PinStatus.ok);

  const PinCheck.wrong(int attemptsLeft)
      : this._(PinStatus.wrong, attemptsLeft: attemptsLeft);

  const PinCheck.lockedOut(DateTime until)
      : this._(PinStatus.lockedOut, lockedUntil: until);

  final PinStatus status;

  /// المحاولات المتبقية قبل الإيقاف المؤقت (عند [PinStatus.wrong]).
  final int attemptsLeft;

  /// وقت انتهاء الإيقاف (عند [PinStatus.lockedOut]).
  final DateTime? lockedUntil;

  bool get isOk => status == PinStatus.ok;
}

/// رمز PIN من 4 أرقام لفتح التطبيق.
///
/// تُحفظ بصمة مملّحة (PBKDF2) في [SecretStore] لا الرمز نفسه. رمز من 4 أرقام
/// ضعيف أمام التخمين المباشر مهما كانت البصمة، فالحماية الفعلية هي الإيقاف
/// المؤقت بعد [maxAttempts] محاولات خاطئة، وحفظ البصمة في Keystore.
class PinService {
  PinService(
    this._store, {
    DateTime Function()? clock,
    Random? random,
    this.iterations = 2000,
  })  : _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure();

  static const int length = 4;
  static const int maxAttempts = 5;
  static const Duration lockoutDuration = Duration(minutes: 5);

  static const String _hashKey = 'pin_hash';
  static const String _saltKey = 'pin_salt';
  static const String _failsKey = 'pin_fails';
  static const String _untilKey = 'pin_locked_until';

  final SecretStore _store;
  final DateTime Function() _clock;
  final Random _random;
  final int iterations;

  static bool isValidFormat(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  Future<bool> isSet() async => await _store.read(_hashKey) != null;

  Future<List<int>> _derive(String pin, List<int> salt) async {
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final key = await algorithm.deriveKeyFromPassword(
      password: pin,
      nonce: salt,
    );
    return key.extractBytes();
  }

  bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// ينشئ الرمز أو يستبدله، ويصفّر عدّاد المحاولات.
  Future<void> setPin(String pin) async {
    if (!isValidFormat(pin)) {
      throw ArgumentError.value(pin, 'pin', 'الرمز 4 أرقام');
    }
    final salt = List<int>.generate(16, (_) => _random.nextInt(256));
    final hash = await _derive(pin, salt);
    await _store.write(_saltKey, base64.encode(salt));
    await _store.write(_hashKey, base64.encode(hash));
    await _store.delete(_failsKey);
    await _store.delete(_untilKey);
  }

  /// يفحص الرمز. بعد [maxAttempts] محاولات خاطئة متتالية يُوقَف الفحص
  /// مدة [lockoutDuration].
  Future<PinCheck> check(String pin) async {
    final now = _clock();
    final untilText = await _store.read(_untilKey);
    if (untilText != null) {
      final until = DateTime.tryParse(untilText);
      if (until != null && now.isBefore(until)) {
        return PinCheck.lockedOut(until);
      }
    }

    final hashText = await _store.read(_hashKey);
    final saltText = await _store.read(_saltKey);
    if (hashText == null || saltText == null) {
      throw StateError('لم يُنشأ رمز PIN بعد');
    }

    var correct = false;
    if (isValidFormat(pin)) {
      final derived = await _derive(pin, base64.decode(saltText));
      correct = _sameBytes(derived, base64.decode(hashText));
    }

    if (correct) {
      await _store.delete(_failsKey);
      await _store.delete(_untilKey);
      return const PinCheck.ok();
    }

    final fails = (int.tryParse(await _store.read(_failsKey) ?? '') ?? 0) + 1;
    if (fails >= maxAttempts) {
      final until = now.add(lockoutDuration);
      await _store.write(_untilKey, until.toIso8601String());
      await _store.delete(_failsKey);
      return PinCheck.lockedOut(until);
    }
    await _store.write(_failsKey, '$fails');
    return PinCheck.wrong(maxAttempts - fails);
  }
}
