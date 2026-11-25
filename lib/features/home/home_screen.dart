import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../data/settings_repository.dart';
import '../../data/util.dart';
import '../production/production_controller.dart';
import '../production/production_screen.dart';
import '../settings/settings_screen.dart';

/// الشاشة الرئيسية. الأقسام تُفعَّل واحداً بعد الآخر مع بناء كل مرحلة.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<bool> _pricesReady;

  @override
  void initState() {
    super.initState();
    _pricesReady = _checkPrices();
  }

  Future<bool> _checkPrices() async {
    final settings = widget.controller.settings;
    final window = await settings.getInt(SettingKeys.windowPrice);
    final distribution = await settings.getInt(SettingKeys.distributionPrice);
    return window != null && distribution != null;
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(controller: widget.controller),
      ),
    );
    if (mounted) {
      // كتلة كاملة وليس سهماً: setState يرفض callback يرجع Future.
      setState(() {
        _pricesReady = _checkPrices();
      });
    }
  }

  Future<void> _openProduction() async {
    // المتحكم يُنشأ مرة واحدة هنا (لا داخل builder الذي قد يُستدعى أكثر من مرة)،
    // والشاشة تتخلص منه عند إغلاقها.
    final production = ProductionController(days: widget.controller.days);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProductionScreen(
          controller: production,
          onOpenSettings: _openSettings,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _pricesReady = _checkPrices();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const upcoming = [
      'الشباك والتوزيع',
      'المصروفات',
      'المخزون',
      'حساب البنكجي',
      'حساب الوكيل',
      'الأيام السابقة',
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.controller.bakeryName ?? 'مخبزك'),
        actions: [
          IconButton(
            tooltip: 'قفل التطبيق',
            onPressed: widget.controller.lock,
            icon: const Icon(Icons.lock_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  formatDate(DateTime.now()),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<bool>(
              future: _pricesReady,
              builder: (context, snapshot) {
                if (snapshot.data == false) {
                  return Card(
                    color: theme.colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_rounded),
                      title: const Text('أدخل الأسعار أولاً'),
                      subtitle: const Text('لا يُفتح يوم جديد قبل إدخال سعر الشباك وسعر التوزيع.'),
                      onTap: _openSettings,
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('الإعدادات'),
                subtitle: const Text('الأسعار والمستهدف وحجم العجنة'),
                onTap: _openSettings,
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.grain),
                title: const Text('الإنتاج اليومي (القطعيات)'),
                subtitle: const Text('عيش كل جوال والمجموع والفرق عن المفروض'),
                onTap: _openProduction,
              ),
            ),
            const SizedBox(height: 8),
            for (final title in upcoming)
              Card(
                child: ListTile(
                  enabled: false,
                  leading: const Icon(Icons.hourglass_empty),
                  title: Text(title),
                  trailing: const Text('قريباً'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
