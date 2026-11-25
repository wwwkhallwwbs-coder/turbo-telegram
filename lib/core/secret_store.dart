/// تخزين الأسرار (كود الجهاز، بصمة PIN، عداد المحاولات).
///
/// في التطبيق يُنفَّذ بـ Android Keystore (`SecureSecretStore` في lib/data)،
/// وفي الاختبارات بالذاكرة. لا تُحفظ الأسرار في قاعدة البيانات أبداً.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// تنفيذ في الذاكرة للاختبارات.
class MemorySecretStore implements SecretStore {
  MemorySecretStore([Map<String, String>? initial]) : _values = {...?initial};

  final Map<String, String> _values;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
