import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/secret_store.dart';

/// تخزين الأسرار في Android Keystore عبر flutter_secure_storage.
///
/// أحياناً تضيع مفاتيح Keystore (استرجاع نسخة احتياطية، أو تحديث نظام) فتفشل
/// القراءة دائماً بـ PlatformException ويبقى التطبيق معلقاً. لذلك نعيد المحاولة
/// مرة، فإن فشلت مرة ثانية نمسح المخزن ونكمل (يُنشأ كود جهاز جديد، ويُطلب
/// إنشاء PIN جديد). هذا أفضل من تطبيق لا يفتح أبداً، والمخزن لا يحوي إلا
/// أسراراً يمكن إعادة إنشائها.
class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException catch (first) {
      debugPrint('SecureSecretStore.read($key) فشل، إعادة المحاولة: $first');
    }
    try {
      return await _storage.read(key: key);
    } on PlatformException catch (second) {
      debugPrint('SecureSecretStore.read($key) فشل ثانية، مسح المخزن: $second');
      await _wipe();
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException catch (error) {
      debugPrint('SecureSecretStore.write($key) فشل، مسح المخزن وإعادة الكتابة: $error');
      await _wipe();
      await _storage.write(key: key, value: value);
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on PlatformException catch (error) {
      debugPrint('SecureSecretStore.delete($key) فشل: $error');
      await _wipe();
    }
  }

  Future<void> _wipe() async {
    try {
      await _storage.deleteAll();
    } on PlatformException catch (error) {
      debugPrint('SecureSecretStore: تعذر مسح المخزن: $error');
    }
  }
}
