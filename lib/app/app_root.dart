import 'package:flutter/material.dart';

import '../features/activation/activation_screen.dart';
import '../features/home/home_screen.dart';
import '../features/pin/create_pin_screen.dart';
import '../features/pin/enter_pin_screen.dart';
import '../features/setup/setup_screen.dart';
import '../features/splash/splash_screen.dart';
import 'app_controller.dart';

typedef AppLoader = Future<AppController> Function();

/// بعد هذه المدة في الخلفية يُقفل التطبيق ويطلب PIN عند الرجوع إليه.
const Duration relockAfter = Duration(minutes: 1);

/// جذر التطبيق: شاشة البداية أثناء التحميل، ثم الشاشة المناسبة لمرحلة التطبيق.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.loader, this.minSplash});

  final AppLoader loader;

  /// أقل مدة لعرض شاشة البداية (null = بلا انتظار، للاختبارات).
  final Duration? minSplash;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  AppController? _controller;
  Object? _error;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    try {
      final splash = widget.minSplash;
      // التحميل وأقل مدة للشاشة يجريان معاً، وأي فشل في التحميل يظهر في catch.
      final results = await Future.wait<Object?>(<Future<Object?>>[
        widget.loader(),
        if (splash != null) Future<void>.delayed(splash),
      ]);
      final controller = results.first! as AppController;
      if (!mounted) {
        return;
      }
      controller.addListener(_onControllerChanged);
      setState(() => _controller = controller);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  /// عند خروج التطبيق من حالة «مفتوح» (قفل) نغلق أي شاشة مفتوحة فوق الرئيسية،
  /// حتى لا تبقى الإعدادات ظاهرة خلف شاشة PIN.
  void _onControllerChanged() {
    final controller = _controller;
    if (controller != null && controller.stage != AppStage.unlocked && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final pausedAt = _pausedAt;
      _pausedAt = null;
      if (pausedAt != null && DateTime.now().difference(pausedAt) >= relockAfter) {
        _controller?.lock();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: SelectableText(
                'تعذر تشغيل التطبيق.\n\n$error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }
    final controller = _controller;
    if (controller == null) {
      return const SplashScreen();
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        switch (controller.stage) {
          case AppStage.needsActivation:
            return ActivationScreen(controller: controller);
          case AppStage.needsSetup:
            return SetupScreen(controller: controller);
          case AppStage.needsPin:
            return CreatePinScreen(controller: controller);
          case AppStage.locked:
            return EnterPinScreen(controller: controller);
          case AppStage.unlocked:
            return HomeScreen(controller: controller);
        }
      },
    );
  }
}
