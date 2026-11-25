import '../core/activation_config.dart';
import '../data/app_database.dart';
import '../data/secure_secret_store.dart';
import 'app_controller.dart';
import 'diagnostics.dart';

/// يفتح القاعدة الحقيقية والتخزين الآمن ويجهّز المتحكم. يُستدعى مرة عند بدء التطبيق.
///
/// كل مرحلة لها اسم ومهلة: إن علقت إحداها يظهر اسمها في شاشة الخطأ بدل
/// بقاء شاشة البداية بلا تفسير.
Future<AppController> loadAppController() async {
  final schema = await runStage('قراءة مخطط القاعدة', loadSchemaAsset);
  final db = await runStage(
    'فتح قاعدة البيانات',
    () => openAppDatabase(schemaSql: schema),
  );
  final controller = await runStage(
    'تجهيز التطبيق',
    () => AppController.open(
      db: db,
      secrets: SecureSecretStore(),
      activationPublicKey: configuredActivationPublicKey(),
    ),
    // داخله مراحل أدق بمهلها الخاصة، فهذه مهلة احتياطية أطول.
    timeout: const Duration(seconds: 60),
  );
  bootStage.value = '';
  return controller;
}
