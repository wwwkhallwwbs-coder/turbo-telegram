/// التحقق من رمز التفعيل بدون إنترنت (انظر docs/ACTIVATION.md).
///
/// يطابق `tools/activation.py` حرفاً بحرف. أي تعديل هنا يتبعه تعديل هناك
/// والاختبارات في الجهتين.
///
/// الصيغة: `MKZ1-<Base32(توقيع 64 بايت || حمولة)>`
/// الحمولة (ASCII): `MKZ1|<role>|<كود الجهاز>|<YYYYMMDD>`
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const String activationVersion = 'MKZ1';
const List<String> activationRoles = ['agent', 'owner'];

const int _signatureLength = 64;
const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

final RegExp _separators = RegExp(r'[\s\-]');
final RegExp _deviceCodePattern = RegExp(r'^[A-Z2-7]{10}$');
final RegExp _issuedPattern = RegExp(r'^\d{8}$');

/// رمز غير صالح لأي سبب. الرسالة للسجلات فقط، والواجهة تعرض رسالة موحدة
/// حتى لا نكشف السبب لمن يجرّب.
class ActivationException implements Exception {
  const ActivationException(this.message);

  final String message;

  @override
  String toString() => 'ActivationException: $message';
}

/// محتوى رمز صالح.
class ActivationInfo {
  const ActivationInfo({
    required this.role,
    required this.device,
    required this.issued,
  });

  final String role;
  final String device;

  /// تاريخ الإصدار `YYYYMMDD`.
  final String issued;
}

/// يوحّد كود الجهاز: بلا مسافات ولا شرطات، أحرف كبيرة، 10 أحرف من A-Z و2-7.
String normalizeDeviceCode(String text) {
  final device = text.replaceAll(_separators, '').toUpperCase();
  if (!_deviceCodePattern.hasMatch(device)) {
    throw const ActivationException('كود الجهاز يجب أن يكون 10 أحرف (A-Z و2-7)');
  }
  return device;
}

/// كود جهاز جديد: 10 أحرف عشوائية. يُحفظ في التخزين الآمن للجهاز.
String generateDeviceCode([Random? random]) {
  final rng = random ?? Random.secure();
  final units = List<int>.generate(
    10,
    (_) => _alphabet.codeUnitAt(rng.nextInt(_alphabet.length)),
  );
  return String.fromCharCodes(units);
}

/// للعرض: `K7QZ2-MWD4A`.
String formatDeviceCode(String code) =>
    '${code.substring(0, 5)}-${code.substring(5)}';

/// Base32 القياسي (RFC 4648) بلا حشو. بتات الحشو في آخر حرف لا تُفحص
/// (كما في بايثون)، ولا يضر ذلك لأن التوقيع يغطي البايتات المفكوكة.
Uint8List _base32Decode(String encoded) {
  const validRemainders = {0, 2, 4, 5, 7};
  if (!validRemainders.contains(encoded.length % 8)) {
    throw const ActivationException('طول الرمز غير صالح');
  }
  final bytes = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final unit in encoded.codeUnits) {
    final value = _alphabet.indexOf(String.fromCharCode(unit));
    if (value < 0) {
      throw const ActivationException('الرمز يحوي أحرفاً غير صالحة');
    }
    buffer = (buffer << 5) | value;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      bytes.add((buffer >> bits) & 0xff);
      buffer &= (1 << bits) - 1;
    }
  }
  return Uint8List.fromList(bytes);
}

/// يتحقق من الرمز كما يفعل التطبيق عند التفعيل. يرجع المحتوى عند النجاح،
/// أو يرفع [ActivationException].
///
/// [publicKey] المفتاح العام Ed25519 (32 بايت).
Future<ActivationInfo> verifyActivationCode({
  required String code,
  required String deviceCode,
  required List<int> publicKey,
}) async {
  final expectedDevice = normalizeDeviceCode(deviceCode);
  final compact = code.replaceAll(_separators, '').toUpperCase();
  if (!compact.startsWith(activationVersion)) {
    throw const ActivationException('صيغة الرمز غير معروفة');
  }
  final body = _base32Decode(compact.substring(activationVersion.length));
  if (body.length <= _signatureLength) {
    throw const ActivationException('الرمز قصير');
  }
  final signature = body.sublist(0, _signatureLength);
  final payload = body.sublist(_signatureLength);

  final valid = await Ed25519().verify(
    payload,
    signature: Signature(
      signature,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
    ),
  );
  if (!valid) {
    throw const ActivationException('التوقيع غير صحيح');
  }

  final String text;
  try {
    text = ascii.decode(payload);
  } on FormatException {
    throw const ActivationException('الحمولة تالفة');
  }
  final parts = text.split('|');
  if (parts.length != 4) {
    throw const ActivationException('الحمولة تالفة');
  }
  final version = parts[0];
  final role = parts[1];
  final deviceInCode = parts[2];
  final issued = parts[3];
  if (version != activationVersion ||
      !activationRoles.contains(role) ||
      !_issuedPattern.hasMatch(issued)) {
    throw const ActivationException('الحمولة غير مدعومة');
  }
  if (deviceInCode != expectedDevice) {
    throw const ActivationException('الرمز مخصص لجهاز آخر');
  }
  return ActivationInfo(role: role, device: deviceInCode, issued: issued);
}

/// بصمة SHA-256 للرمز بعد توحيده (تُخزَّن في device.activation_code_hash،
/// ولا يُخزَّن الرمز نفسه).
Future<String> activationCodeHash(String code) async {
  final compact = code.replaceAll(_separators, '').toUpperCase();
  final hash = await Sha256().hash(utf8.encode(compact));
  return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
