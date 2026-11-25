import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_root.dart';
import 'app/bootstrap.dart';
import 'features/splash/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MakhbazakApp());
}

class MakhbazakApp extends StatelessWidget {
  const MakhbazakApp({
    super.key,
    this.loader = loadAppController,
    this.minSplash = const Duration(milliseconds: 1200),
  });

  /// تحميل القاعدة والتخزين الآمن (يُستبدل في الاختبارات).
  final AppLoader loader;

  /// أقل مدة لعرض شاشة البداية.
  final Duration? minSplash;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مخبزك',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: SplashScreen.brandGreen),
      ),
      home: AppRoot(loader: loader, minSplash: minSplash),
    );
  }
}
