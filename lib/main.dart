import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  runApp(const NaeemSoftWmsApp());
}

class NaeemSoftWmsApp extends StatefulWidget {
  const NaeemSoftWmsApp({super.key});

  @override
  State<NaeemSoftWmsApp> createState() => _NaeemSoftWmsAppState();
}

class _NaeemSoftWmsAppState extends State<NaeemSoftWmsApp> {
  Locale _locale = const Locale('ar');

  void _changeLocale(Locale locale) {
    setState(() => _locale = locale);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NaeemSoft-WMS',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
        Locale('fr'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF176B87),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
        ),
      ),
      home: WmsDashboard(
        locale: _locale,
        onLocaleChanged: _changeLocale,
      ),
    );
  }
}

class WmsDashboard extends StatelessWidget {
  const WmsDashboard({
    required this.locale,
    required this.onLocaleChanged,
    super.key,
  });

  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;

  static const Map<String, Map<String, String>> _copy = {
    'ar': {
      'title': 'NaeemSoft-WMS',
      'subtitle': 'نظام إدارة المخازن والمخزون',
      'foundation': 'مرحلة التأسيس',
      'foundationTitle': 'بناء قاعدة موثوقة للنظام',
      'foundationBody':
          'يجري تجهيز نموذج البيانات وبنية تطبيق Android قبل تفعيل العمليات التشغيلية.',
      'database': 'قاعدة البيانات',
      'databaseBody': 'الأصناف والوحدات وحركات المخزون والاعتمادات',
      'inventory': 'إدارة المخزون',
      'inventoryBody': 'الأرصدة والاستلام والصرف والجرد والدفعات',
      'operations': 'العمليات التجارية',
      'operationsBody': 'الموردون والعملاء وعروض الأسعار والمبيعات',
      'control': 'الإدارة والرقابة',
      'controlBody': 'المستخدمون والفروع والصلاحيات وسجل التدقيق',
      'android': 'تطبيق Android',
      'version': 'الإصدار التأسيسي 0.1.0',
    },
    'en': {
      'title': 'NaeemSoft-WMS',
      'subtitle': 'Warehouse Management System',
      'foundation': 'Foundation phase',
      'foundationTitle': 'Building a reliable system core',
      'foundationBody':
          'The data model and Android application foundation are being established before operational workflows are enabled.',
      'database': 'Database',
      'databaseBody': 'Products, units, stock movements and approvals',
      'inventory': 'Inventory management',
      'inventoryBody': 'Balances, receiving, issuing, counts and batches',
      'operations': 'Business operations',
      'operationsBody': 'Suppliers, customers, quotations and sales',
      'control': 'Administration and control',
      'controlBody': 'Users, branches, permissions and audit trail',
      'android': 'Android application',
      'version': 'Foundation release 0.1.0',
    },
    'fr': {
      'title': 'NaeemSoft-WMS',
      'subtitle': 'Système de gestion des entrepôts',
      'foundation': 'Phase de fondation',
      'foundationTitle': 'Construire un noyau fiable',
      'foundationBody':
          'Le modèle de données et la base de l’application Android sont préparés avant l’activation des opérations.',
      'database': 'Base de données',
      'databaseBody': 'Articles, unités, mouvements et validations',
      'inventory': 'Gestion des stocks',
      'inventoryBody': 'Soldes, réceptions, sorties, inventaires et lots',
      'operations': 'Opérations commerciales',
      'operationsBody': 'Fournisseurs, clients, devis et ventes',
      'control': 'Administration et contrôle',
      'controlBody': 'Utilisateurs, agences, autorisations et audit',
      'android': 'Application Android',
      'version': 'Version de fondation 0.1.0',
    },
  };

  String _t(String key) {
    final language = _copy[locale.languageCode] ?? _copy['en']!;
    return language[key] ?? key;
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = locale.languageCode == 'ar';

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_t('title')),
          centerTitle: false,
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Locale>(
                  value: locale,
                  icon: const Icon(Icons.language),
                  onChanged: (value) {
                    if (value != null) onLocaleChanged(value);
                  },
                  items: const [
                    DropdownMenuItem(
                      value: Locale('ar'),
                      child: Text('العربية'),
                    ),
                    DropdownMenuItem(
                      value: Locale('en'),
                      child: Text('English'),
                    ),
                    DropdownMenuItem(
                      value: Locale('fr'),
                      child: Text('Français'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [Color(0xFF176B87), Color(0xFF10465D)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warehouse_outlined,
                      color: Colors.white,
                      size: 42,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _t('subtitle'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _t('android'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.88),
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text(
                _t('foundation'),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('foundationTitle'),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t('foundationBody'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: 1.5,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              _ModuleCard(
                icon: Icons.table_chart_outlined,
                title: _t('database'),
                description: _t('databaseBody'),
              ),
              const SizedBox(height: 12),
              _ModuleCard(
                icon: Icons.inventory_2_outlined,
                title: _t('inventory'),
                description: _t('inventoryBody'),
              ),
              const SizedBox(height: 12),
              _ModuleCard(
                icon: Icons.swap_horiz,
                title: _t('operations'),
                description: _t('operationsBody'),
              ),
              const SizedBox(height: 12),
              _ModuleCard(
                icon: Icons.admin_panel_settings_outlined,
                title: _t('control'),
                description: _t('controlBody'),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  _t('version'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              child: Icon(icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
