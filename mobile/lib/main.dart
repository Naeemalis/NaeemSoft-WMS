import 'package:flutter/material.dart';
import 'data/local_database.dart';
import 'screens/cashier_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDatabase.instance.database;
  runApp(const NaeemSoftWmsApp());
}

class NaeemSoftWmsApp extends StatefulWidget {
  const NaeemSoftWmsApp({super.key});

  @override
  State<NaeemSoftWmsApp> createState() => _NaeemSoftWmsAppState();
}

class _NaeemSoftWmsAppState extends State<NaeemSoftWmsApp> {
  Locale _locale = const Locale('ar');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NaeemSoft-WMS',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: const [Locale('ar'), Locale('en'), Locale('fr')],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B57)),
        scaffoldBackgroundColor: const Color(0xFFF6F8F7),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: _locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: child ?? const SizedBox.shrink(),
      ),
      home: WmsShell(
        locale: _locale,
        onLocaleChanged: (value) => setState(() => _locale = value),
      ),
    );
  }
}

class WmsShell extends StatefulWidget {
  const WmsShell({required this.locale, required this.onLocaleChanged, super.key});
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<WmsShell> createState() => _WmsShellState();
}

class _WmsShellState extends State<WmsShell> {
  int _selected = 0;

  static const _pages = [
    ('dashboard', Icons.dashboard_outlined),
    ('products', Icons.inventory_2_outlined),
    ('receiving', Icons.move_to_inbox_outlined),
    ('issuing', Icons.outbox_outlined),
    ('suppliers', Icons.local_shipping_outlined),
    ('recipients', Icons.people_alt_outlined),
    ('reports', Icons.assessment_outlined),
    ('settings', Icons.settings_outlined),
  ];

  String tr(String key) => _strings[widget.locale.languageCode]?[key] ??
      _strings['en']![key] ?? key;

  void _openMore() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [4, 5, 6, 7].map((index) => ListTile(
            leading: Icon(_pages[index].$2),
            title: Text(tr(_pages[index].$1)),
            onTap: () {
              Navigator.pop(sheetContext);
              setState(() => _selected = index);
            },
          )).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 720;
    final title = tr(_pages[_selected].$1);
    final content = _selected == 1
        ? ProductsPage(tr: tr)
        : _selected == 2
            ? CashierPage(tr: tr, receiving: true)
            : _selected == 3
                ? CashierPage(tr: tr, receiving: false)
                : _selected == 7
                    ? SettingsPage(locale: widget.locale, onChanged: widget.onLocaleChanged, tr: tr)
                    : DashboardPage(tr: tr, onOpen: (index) => setState(() => _selected = index));

    return Scaffold(
      appBar: AppBar(
        title: Text('NaeemSoft-WMS • $title', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Center(child: Text(widget.locale.languageCode.toUpperCase())),
          ),
        ],
      ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              selectedIndex: _selected,
              onDestinationSelected: (value) => setState(() => _selected = value),
              labelType: NavigationRailLabelType.all,
              destinations: _pages.map((page) => NavigationRailDestination(
                icon: Icon(page.$2), label: Text(tr(page.$1)),
              )).toList(),
            ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: content,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide ? null : NavigationBar(
        selectedIndex: _selected > 3 ? 4 : _selected,
        onDestinationSelected: (value) {
          if (value == 4) {
            _openMore();
          } else {
            setState(() => _selected = value);
          }
        },
        destinations: [
          NavigationDestination(icon: const Icon(Icons.dashboard_outlined), label: tr('dashboard')),
          NavigationDestination(icon: const Icon(Icons.inventory_2_outlined), label: tr('products')),
          NavigationDestination(icon: const Icon(Icons.move_to_inbox_outlined), label: tr('receiving')),
          NavigationDestination(icon: const Icon(Icons.outbox_outlined), label: tr('issuing')),
          NavigationDestination(icon: const Icon(Icons.menu), label: tr('more')),
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({required this.tr, required this.onOpen, super.key});
  final String Function(String) tr;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width < 420 ? 2 : width < 800 ? 3 : width < 1150 ? 4 : 5;
    final tiles = <(String, IconData, int)>[
      ('products', Icons.inventory_2_outlined, 1),
      ('receiving', Icons.move_to_inbox_outlined, 2),
      ('issuing', Icons.outbox_outlined, 3),
      ('suppliers', Icons.local_shipping_outlined, 4),
      ('recipients', Icons.people_alt_outlined, 5),
      ('reports', Icons.assessment_outlined, 6),
      ('settings', Icons.settings_outlined, 7),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('welcome'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(tr('offlineSingle'), style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 18),
        LayoutBuilder(builder: (context, constraints) {
          final cardWidth = (constraints.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(spacing: 12, runSpacing: 12, children: tiles.map((tile) => SizedBox(
            width: cardWidth,
            height: 116,
            child: Card(child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onOpen(tile.$3),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Icon(tile.$2, size: 27, color: Theme.of(context).colorScheme.primary),
                  Text(tr(tile.$1), style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
              ),
            )),
          )).toList());
        }),
        const SizedBox(height: 22),
        Text(tr('statusLegend'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Wrap(spacing: 8, runSpacing: 8, children: [
          StatusChip(color: Color(0xFFD92D20), label: 'نفد'),
          StatusChip(color: Color(0xFFF79009), label: 'منخفض'),
          StatusChip(color: Color(0xFF7F56D9), label: 'راكد'),
          StatusChip(color: Color(0xFFB42318), label: 'منتهي'),
          StatusChip(color: Color(0xFFEAAA08), label: 'قرب الانتهاء'),
          StatusChip(color: Color(0xFF12B76A), label: 'متوفر'),
        ]),
      ]),
    );
  }
}

class ProductsPage extends StatelessWidget {
  const ProductsPage({required this.tr, super.key});
  final String Function(String) tr;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: LocalDatabase.instance.getProducts(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text(snapshot.error.toString()));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final products = snapshot.data!;
        final width = MediaQuery.sizeOf(context).width;
        final columns = width < 380 ? 2 : width < 600 ? 3 : width < 900 ? 4 : width < 1250 ? 6 : 8;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('products'), style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Expanded(child: products.isEmpty
              ? Center(child: Text(tr('noProducts')))
              : GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns, crossAxisSpacing: 10, mainAxisSpacing: 10,
                    childAspectRatio: width < 600 ? 1.2 : 1.35,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    final qty = (product['available_quantity'] as num?)?.toDouble() ?? 0;
                    final min = (product['minimum_stock'] as num?)?.toDouble() ?? 0;
                    final color = qty <= 0 ? const Color(0xFFD92D20)
                        : min > 0 && qty <= min ? const Color(0xFFF79009)
                        : const Color(0xFF12B76A);
                    return Card(
                      color: color.withValues(alpha: .09),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.inventory_2_outlined, color: color, size: 26),
                          const SizedBox(height: 8),
                          Text((product['name_ar'] ?? '').toString(), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 5),
                          Text('${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)} ${product['base_unit_name'] ?? ''}', textAlign: TextAlign.center),
                        ]),
                      ),
                    );
                  },
                )),
          ]),
        );
      },
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.locale, required this.onChanged, required this.tr, super.key});
  final Locale locale;
  final ValueChanged<Locale> onChanged;
  final String Function(String) tr;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    Text(tr('settings'), style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 14),
    DropdownButtonFormField<String>(
      value: locale.languageCode,
      decoration: InputDecoration(labelText: tr('language')),
      items: const [
        DropdownMenuItem(value: 'ar', child: Text('العربية')),
        DropdownMenuItem(value: 'en', child: Text('English')),
        DropdownMenuItem(value: 'fr', child: Text('Français')),
      ],
      onChanged: (value) { if (value != null) onChanged(Locale(value)); },
    ),
    const SizedBox(height: 18),
    ListTile(leading: const Icon(Icons.storage_outlined), title: Text(tr('localDb')), subtitle: const Text('SQLite • App-private storage')),
    ListTile(leading: const Icon(Icons.wifi_off), title: Text(tr('offlineOnly'))),
    ListTile(leading: const Icon(Icons.phone_android), title: Text(tr('responsive'))),
  ]);
}

class StatusChip extends StatelessWidget {
  const StatusChip({required this.color, required this.label, super.key});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Chip(
    avatar: CircleAvatar(backgroundColor: color, radius: 6),
    label: Text(label),
    visualDensity: VisualDensity.compact,
  );
}

const Map<String, Map<String, String>> _strings = {
  'ar': {
    'dashboard':'لوحة التحكم','products':'الأصناف','receiving':'كاشير الاستلام','issuing':'كاشير الصرف',
    'suppliers':'الموردون','recipients':'المستلمون','reports':'التقارير والكشوف','settings':'الإعدادات','more':'المزيد',
    'welcome':'مرحباً بك في NaeemSoft-WMS','offlineSingle':'إدارة مخزن واحد محلياً على هذا الجهاز دون الحاجة إلى الإنترنت.',
    'statusLegend':'دلالات ألوان الأصناف','noProducts':'لا توجد أصناف مسجلة بعد.','noAvailableProducts':'لا توجد أصناف متاحة للصرف.',
    'receivingRule':'اختر المورد ثم أضف الأصناف إلى فاتورة الاستلام. لا يضاف المخزون إلا بعد اعتماد الاستلام.',
    'issuingRule':'اختر المستلم ثم أضف الأصناف. كل سطر صرف يتضمن سعراً، ولا يخصم المخزون إلا بعد الاعتماد.',
    'cashierFoundation':'تم اختيار الصنف ضمن تأسيس شاشة الكاشير.','language':'لغة التطبيق','localDb':'قاعدة البيانات المحلية',
    'offlineOnly':'يعمل دون إنترنت','responsive':'متوافق مع الهواتف والأجهزة اللوحية',
  },
  'en': {
    'dashboard':'Dashboard','products':'Products','receiving':'Receiving cashier','issuing':'Issue cashier',
    'suppliers':'Suppliers','recipients':'Recipients','reports':'Reports & statements','settings':'Settings','more':'More',
    'welcome':'Welcome to NaeemSoft-WMS','offlineSingle':'Manage one warehouse locally on this device without internet.',
    'statusLegend':'Product status colors','noProducts':'No products have been registered yet.','noAvailableProducts':'No products are available to issue.',
    'receivingRule':'Select a supplier and add products to a receipt. Stock increases only after approval.',
    'issuingRule':'Select a recipient and add products. Every issue line is priced; stock decreases only after approval.',
    'cashierFoundation':'The product grid is part of the cashier foundation.','language':'Application language','localDb':'Local database',
    'offlineOnly':'Works offline','responsive':'Responsive on phones and tablets',
  },
  'fr': {
    'dashboard':'Tableau de bord','products':'Articles','receiving':'Caisse de réception','issuing':'Caisse de sortie',
    'suppliers':'Fournisseurs','recipients':'Destinataires','reports':'Rapports et relevés','settings':'Paramètres','more':'Plus',
    'welcome':'Bienvenue dans NaeemSoft-WMS','offlineSingle':'Gérez un seul dépôt localement sur cet appareil, sans Internet.',
    'statusLegend':'Couleurs d’état des articles','noProducts':'Aucun article enregistré.','noAvailableProducts':'Aucun article disponible pour la sortie.',
    'receivingRule':'Choisissez un fournisseur et ajoutez les articles au reçu. Le stock augmente après validation.',
    'issuingRule':'Choisissez un destinataire et ajoutez les articles. Chaque ligne est tarifée; le stock diminue après validation.',
    'cashierFoundation':'La grille des articles fait partie de la base de la caisse.','language':'Langue de l’application','localDb':'Base de données locale',
    'offlineOnly':'Fonctionne hors ligne','responsive':'Adapté aux téléphones et tablettes',
  },
};
