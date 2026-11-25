import 'dart:convert';

/// المفتاح العام لرمز التفعيل بصيغة Base64 (32 بايت).
///
/// المفتاح العام ليس سراً، ويوضع في التطبيق ويُرفع مع الكود. أما المفتاح
/// الخاص فيبقى عند المصمم وحده في tools/private/ ولا يدخل المستودع أبداً.
///
/// يُملأ بعد تشغيل: python3 tools/activation.py keygen
/// وهو فارغ الآن، فلا يُقبل أي رمز قبل ضبطه.
const String activationPublicKeyBase64 = '';

bool get isActivationConfigured => activationPublicKeyBase64.isNotEmpty;

/// المفتاح العام كبايتات، أو null إن لم يُضبط بعد.
List<int>? configuredActivationPublicKey() {
  if (!isActivationConfigured) {
    return null;
  }
  return base64.decode(activationPublicKeyBase64);
}
