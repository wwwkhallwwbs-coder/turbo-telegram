import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:makhbazak/core/activation.dart';

// متجه اختبار مولَّد بـ tools/activation.py بمفاتيح مؤقتة حُذفت فور التوليد.
// هذه المفاتيح للاختبار فقط ولا علاقة لها بمفتاح التفعيل الحقيقي.
const String _publicKey = 'hHl28fyv8oURVyqMHXApwC/YpJZMJVQC46BkGsB5evQ=';
const String _otherPublicKey = 'Gxx3FdppKVU4qs1urUxKy6hOxaQrIjAiL2MS9z5kYZ8=';
const String _device = 'K7QZ2MWD4A';
const String _otherDevice = 'K7QZ2MWD4B';
const String _code =
    'MKZ1-XMWJM-M5GU6-H2FYD-2G77B-4FPZ4-K3OU2-MCSHF-X5NQK-J3BGN-JY6VY-5VC5B-'
    'CARR5-CYTYC-3FDEB-OWB5W-FBIYQ-RZTNM-J2IKP-7XQ2J-7BQZX-2CKNJ-NNDC7-DBM5S-'
    'W45D4-JM3VC-WRSJV-LUINC-BPQZD-AMRWG-EYTEM-I';

const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

List<int> _key(String base64Text) => base64.decode(base64Text);

Future<ActivationInfo> _verify({
  String code = _code,
  String device = _device,
  String key = _publicKey,
}) =>
    verifyActivationCode(
      code: code,
      deviceCode: device,
      publicKey: _key(key),
    );

void main() {
  test('رمز صالح لنفس الجهاز', () async {
    final info = await _verify();
    expect(info.role, 'agent');
    expect(info.device, _device);
    expect(info.issued, '20261121');
  });

  test('لا يعمل على جهاز آخر', () async {
    await expectLater(
      _verify(device: _otherDevice),
      throwsA(isA<ActivationException>()),
    );
  });

  test('لا يُقبل بمفتاح عام مختلف', () async {
    await expectLater(
      _verify(key: _otherPublicKey),
      throwsA(isA<ActivationException>()),
    );
  });

  test('اللصق من واتساب: مسافات وأحرف صغيرة وسطور جديدة وكود جهاز بشرطة', () async {
    final messy = '  ${_code.toLowerCase().replaceAll('-', ' ')}\n';
    final info = await _verify(code: messy, device: 'k7qz2-mwd4a');
    expect(info.role, 'agent');
  });

  test('أي حرف معدّل يُبطل الرمز (عدا حشو آخر حرف)', () async {
    final compact = _code.replaceAll('-', '');
    // الموضع 0..3 هو المقدمة MKZ1، والباقي جسم الرمز.
    final last = compact.length - 1;
    for (var i = 4; i < compact.length; i++) {
      final next = _alphabet[(_alphabet.indexOf(compact[i]) + 1) % 32];
      final broken = compact.substring(0, i) + next + compact.substring(i + 1);
      try {
        final info = await _verify(code: broken);
        // الاستثناء الوحيد: آخر حرف يحمل بتّين من البيانات و3 بتات حشو.
        expect(i, last, reason: 'قُبل رمز معدّل في الموضع $i');
        expect(info.device, _device);
      } on ActivationException {
        // المتوقع.
      }
    }
  });

  test('رموز مقطوعة أو فارغة أو بمقدمة خاطئة أو بحرف غريب', () async {
    final compact = _code.replaceAll('-', '');
    for (final bad in [
      compact.substring(0, compact.length - 6),
      'MKZ1-',
      'XYZ9-AAAA',
      '${_code}!',
      '',
    ]) {
      await expectLater(
        _verify(code: bad),
        throwsA(isA<ActivationException>()),
        reason: 'كان يجب أن يُرفض: "$bad"',
      );
    }
  });

  test('كود جهاز غير صالح يُرفض', () async {
    for (final bad in ['SHORT', 'K7QZ2MWD40', '', 'K7QZ2MWD4AA']) {
      await expectLater(
        _verify(device: bad),
        throwsA(isA<ActivationException>()),
        reason: 'كان يجب أن يُرفض كود الجهاز "$bad"',
      );
    }
  });

  group('كود الجهاز', () {
    test('التوليد: 10 أحرف من الأبجدية المسموحة', () {
      final rng = Random(7);
      for (var i = 0; i < 50; i++) {
        final code = generateDeviceCode(rng);
        expect(RegExp(r'^[A-Z2-7]{10}$').hasMatch(code), isTrue, reason: code);
      }
    });

    test('التوليد العشوائي الآمن يعطي أكواداً مختلفة', () {
      expect(generateDeviceCode(), isNot(generateDeviceCode()));
    });

    test('العرض والتوحيد', () {
      expect(formatDeviceCode('K7QZ2MWD4A'), 'K7QZ2-MWD4A');
      expect(normalizeDeviceCode(' k7qz2-mwd4a '), 'K7QZ2MWD4A');
    });
  });

  group('بصمة الرمز', () {
    test('64 خانة سداسية، وتتجاهل التنسيق', () async {
      final a = await activationCodeHash(_code);
      final b = await activationCodeHash(
        _code.toLowerCase().replaceAll('-', ' '),
      );
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(a), isTrue);
      expect(a, b);
    });

    test('رمزان مختلفان لهما بصمتان مختلفتان', () async {
      final a = await activationCodeHash(_code);
      final b = await activationCodeHash('${_code}A');
      expect(a, isNot(b));
    });
  });
}
