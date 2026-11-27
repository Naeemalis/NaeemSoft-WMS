import 'package:flutter/material.dart';
import 'data/local_database.dart';
import 'screens/cashier_page.dart';
import 'screens/issue_cashier_page.dart';
import 'screens/sales_cashier_page.dart';
import 'screens/management_pages.dart';
import 'screens/supplier_statement_page.dart';
import 'data/demo_data_seeder.dart';

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
  int? _autoOpenPartnerPage;
  bool _autoOpenProductForm = false;
  int? _returnToCashierPage;

  static const _pages = [
    ('dashboard', Icons.dashboard_outlined),
    ('products', Icons.inventory_2_outlined),
    ('receiving', Icons.move_to_inbox_outlined),
    ('issuing', Icons.outbox_outlined),
    ('sales', Icons.point_of_sale_outlined),
    ('suppliers', Icons.local_shipping_outlined),
    ('recipients', Icons.people_alt_outlined),
    ('reports', Icons.assessment_outlined),
    ('settings', Icons.settings_outlined),
    ('supplierStatement', Icons.account_balance_wallet_outlined),
  ];

  String tr(String key) => _strings[widget.locale.languageCode]?[key] ??
      _strings['en']![key] ?? key;

  void _selectPage(int index) {
    if (index < 0 || index >= _pages.length) return;
    setState(() { _selected = index; _autoOpenPartnerPage = null; _autoOpenProductForm = false; });
  }

  void _openPartnerForm(int index) {
    setState(() { _returnToCashierPage = _selected == 2 || _selected == 3 || _selected == 9 ? _selected : null; _selected = index; _autoOpenPartnerPage = index; _autoOpenProductForm = false; });
  }

  void _openProductForm() {
    setState(() { _returnToCashierPage = _selected == 2 || _selected == 3 ? _selected : null; _selected = 1; _autoOpenProductForm = true; _autoOpenPartnerPage = null; });
  }

  void _returnToCashier() {
    final destination = _returnToCashierPage;
    if (destination == null) return;
    setState(() { _selected = destination; _returnToCashierPage = null; _autoOpenPartnerPage = null; _autoOpenProductForm = false; });
  }

  Widget _navigationDrawer() => NavigationDrawer(
    selectedIndex: _selected,
    onDestinationSelected: (index) {
      Navigator.of(context).pop();
      _selectPage(index);
    },
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
        child: Text('NaeemSoft-WMS', style: Theme.of(context).textTheme.titleLarge),
      ),
      const Divider(),
      for (var i = 0; i < _pages.length; i++)
        NavigationDrawerDestination(
          icon: Icon(_pages[i].$2),
          label: Text(tr(_pages[i].$1)),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 720;
    final title = tr(_pages[_selected].$1);
    final content = _selected == 1
        ? ProductManagementPage(key: ValueKey('products-$_autoOpenProductForm'), tr: tr, autoOpenAdd: _autoOpenProductForm, onDone: _returnToCashier)
        : _selected == 2
            ? CashierPage(
                key: const ValueKey('receiving-cashier'),
                tr: tr,
                receiving: true,
                onOpenPartners: () => _openPartnerForm(4),
                onOpenProducts: _openProductForm,
              )
            : _selected == 3
                ? IssueCashierPage(
                    key: const ValueKey('issuing-cashier'),
                    tr: tr,
                    onOpenRecipients: () => _openPartnerForm(5),
                    onOpenProducts: _openProductForm,
                  )
                : _selected == 9
                    ? SalesCashierPage(
                        key: const ValueKey('sales-cashier'),
                        tr: tr,
                        onOpenRecipients: () => _openPartnerForm(5),
                        onOpenProducts: _openProductForm,
                      )
                : _selected == 4
                    ? PartnerManagementPage(key: ValueKey('suppliers-$_autoOpenPartnerPage'), tr: tr, suppliers: true, autoOpenAdd: _autoOpenPartnerPage == 4, onDone: _returnToCashier)
                    : _selected == 5
                        ? PartnerManagementPage(key: ValueKey('recipients-$_autoOpenPartnerPage'), tr: tr, suppliers: false, autoOpenAdd: _autoOpenPartnerPage == 5, onDone: _returnToCashier)
                        : _selected == 6
                            ? BasicReportsPage(tr: tr)
                            : _selected == 7
                                ? SettingsPage(locale: widget.locale, onChanged: widget.onLocaleChanged, tr: tr)
                                : _selected == 8
                                    ? SupplierStatementPage(tr: tr)
                                    : DashboardPage(tr: tr, onOpen: (index) => setState(() => _selected = index));

    return Scaffold(
      drawer: _navigationDrawer(),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'القائمة الرئيسية',
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
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
        selectedIndex: _selected <= 4 ? _selected : 0,
        onDestinationSelected: _selectPage,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.dashboard_outlined), label: tr('dashboard')),
          NavigationDestination(icon: const Icon(Icons.inventory_2_outlined), label: tr('products')),
          NavigationDestination(icon: const Icon(Icons.move_to_inbox_outlined), label: tr('receiving')),
          NavigationDestination(icon: const Icon(Icons.outbox_outlined), label: tr('issuing')),
          NavigationDestination(icon: const Icon(Icons.point_of_sale_outlined), label: tr('sales')),
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
      ('sales', Icons.point_of_sale_outlined, 9),
      ('suppliers', Icons.local_shipping_outlined, 4),
      ('recipients', Icons.people_alt_outlined, 5),
      ('reports', Icons.assessment_outlined, 6),
      ('settings', Icons.settings_outlined, 7),
      ('supplierStatement', Icons.account_balance_wallet_outlined, 8),
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

class SettingsPage extends StatefulWidget {
  const SettingsPage({required this.locale, required this.onChanged, required this.tr, super.key});
  final Locale locale;
  final ValueChanged<Locale> onChanged;
  final String Function(String) tr;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _seeding = false;

  Future<void> _loadDemoData() async {
    if (_seeding) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تحميل بيانات تجريبية'),
        content: const Text('سيضيف النظام 5 أصناف وموردين اثنين وجهتي استلام، وينشئ فاتورتي توريد وسندي صرف معتمدين لتجربة سير العمل. لا تحذف هذه البيانات تلقائياً.'),
        actions: [
          TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('تحميل')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(()=>_seeding=true);
    try {
      final db=await LocalDatabase.instance.database;
      final result=await DemoDataSeeder(db).seed();
      if (!mounted) return;
      final already=result['alreadySeeded']==1;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:Text(already
          ? 'البيانات التجريبية موجودة مسبقاً.'
          : 'تم إنشاء 5 أصناف، وموردين، وجهتي استلام، وفاتورتي توريد وسندي صرف معتمدين.'),
        duration:const Duration(seconds:5),
      ));
    } catch(e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('تعذر تحميل البيانات التجريبية: $e')));
    } finally {
      if(mounted) setState(()=>_seeding=false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    Text(widget.tr('settings'), style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 14),
    DropdownButtonFormField<String>(
      initialValue: widget.locale.languageCode,
      decoration: InputDecoration(labelText: widget.tr('language')),
      items: const [
        DropdownMenuItem(value: 'ar', child: Text('العربية')),
        DropdownMenuItem(value: 'en', child: Text('English')),
        DropdownMenuItem(value: 'fr', child: Text('Français')),
      ],
      onChanged: (value) { if (value != null) widget.onChanged(Locale(value)); },
    ),
    const SizedBox(height: 18),
    ListTile(leading: const Icon(Icons.storage_outlined), title: Text(widget.tr('localDb')), subtitle: const Text('SQLite • App-private storage')),
    ListTile(leading: const Icon(Icons.wifi_off), title: Text(widget.tr('offlineOnly'))),
    ListTile(leading: const Icon(Icons.phone_android), title: Text(widget.tr('responsive'))),
    const Divider(height:28),
    Text('بيانات واختبارات التشغيل',style:Theme.of(context).textTheme.titleMedium),
    const SizedBox(height:8),
    FilledButton.icon(
      onPressed:_seeding?null:_loadDemoData,
      icon:_seeding?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.science_outlined),
      label:Text(_seeding?'جارٍ إنشاء البيانات...':'إضافة بيانات تجريبية وتشغيل دورتين'),
    ),
    const SizedBox(height:6),
    const Text('المنتجات التجريبية تشمل القلم والدفتر بالقطعة، السكر بالكيلو والجرام، وزيت الطبخ باللتر.'),
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
    'dashboard':'لوحة التحكم','products':'الأصناف','receiving':'قسم التوريد','issuing':'قسم الصرف','sales':'قسم المبيعات',
    'suppliers':'الموردون','recipients':'المستلمون','reports':'التقارير والكشوف','settings':'الإعدادات','more':'المزيد','supplierStatement':'كشف حساب المورد',
    'welcome':'مرحباً بك في NaeemSoft-WMS','offlineSingle':'إدارة مخزن واحد محلياً على هذا الجهاز دون الحاجة إلى الإنترنت.',
    'statusLegend':'دلالات ألوان الأصناف','noProducts':'لا توجد أصناف مسجلة بعد.','noAvailableProducts':'لا توجد أصناف متاحة للصرف.',
    'receivingRule':'اختر المورد ثم أضف الأصناف إلى فاتورة الاستلام. لا يضاف المخزون إلا بعد اعتماد الاستلام.',
    'issuingRule':'اختر المستلم ثم أضف الأصناف. كل سطر صرف يتضمن سعراً، ولا يخصم المخزون إلا بعد الاعتماد.',
    'cashierFoundation':'تم اختيار الصنف ضمن تأسيس شاشة الكاشير.','language':'لغة التطبيق','localDb':'قاعدة البيانات المحلية',
    'offlineOnly':'يعمل دون إنترنت','responsive':'متوافق مع الهواتف والأجهزة اللوحية',
    'draftSaved':'تم حفظ المسودة','documentApproved':'تم اعتماد المستند وتحديث المخزون',
    'selectSupplier':'اختر المورد','selectRecipient':'اختر المستلم','invoiceCart':'سلة الفاتورة',
    'documentNumber':'رقم المستند','cartEmpty':'أضف الأصناف من المعرض','quantity':'الكمية',
    'unitCost':'تكلفة الوحدة','unitPrice':'سعر الوحدة','remove':'حذف','total':'الإجمالي',
    'saveDraft':'حفظ المسودة','approveDocument':'اعتماد المستند','cancelDraft':'إلغاء المسودة',
    'addSupplierFirst':'أضف مورداً قبل تنفيذ الاستلام','addRecipientFirst':'أضف مستلماً قبل تنفيذ الصرف',
    'refresh':'تحديث',
    'addProduct':'إضافة صنف','productName':'اسم الصنف','baseUnit':'وحدة الأساس',
    'minimumStock':'حد إعادة الطلب','save':'حفظ','cancel':'إلغاء','addPartner':'إضافة جهة',
    'name':'الاسم','phone':'الهاتف','address':'العنوان','noPartners':'لا توجد جهات مسجلة',
    'approvedReceipts':'الاستلامات المعتمدة','approvedIssues':'عمليات الصرف المعتمدة','stockMovements':'حركات المخزون',
  },
  'en': {
    'dashboard':'Dashboard','products':'Products','receiving':'Receiving','issuing':'Issues','sales':'Sales',
    'suppliers':'Suppliers','recipients':'Recipients','reports':'Reports & statements','settings':'Settings','more':'More','supplierStatement':'Supplier statement',
    'welcome':'Welcome to NaeemSoft-WMS','offlineSingle':'Manage one warehouse locally on this device without internet.',
    'statusLegend':'Product status colors','noProducts':'No products have been registered yet.','noAvailableProducts':'No products are available to issue.',
    'receivingRule':'Select a supplier and add products to a receipt. Stock increases only after approval.',
    'issuingRule':'Select a recipient and add products. Every issue line is priced; stock decreases only after approval.',
    'cashierFoundation':'The product grid is part of the cashier foundation.','language':'Application language','localDb':'Local database',
    'offlineOnly':'Works offline','responsive':'Responsive on phones and tablets',
    'draftSaved':'Draft saved','documentApproved':'Document approved and stock updated',
    'selectSupplier':'Select supplier','selectRecipient':'Select recipient','invoiceCart':'Invoice cart',
    'documentNumber':'Document number','cartEmpty':'Add products from the grid','quantity':'Quantity',
    'unitCost':'Unit cost','unitPrice':'Unit price','remove':'Remove','total':'Total',
    'saveDraft':'Save draft','approveDocument':'Approve document','cancelDraft':'Cancel draft',
    'addSupplierFirst':'Add a supplier before receiving stock','addRecipientFirst':'Add a recipient before issuing stock',
    'refresh':'Refresh',
    'addProduct':'Add product','productName':'Product name','baseUnit':'Base unit',
    'minimumStock':'Minimum stock','save':'Save','cancel':'Cancel','addPartner':'Add contact',
    'name':'Name','phone':'Phone','address':'Address','noPartners':'No contacts registered',
    'approvedReceipts':'Approved receipts','approvedIssues':'Approved issues','stockMovements':'Stock movements',
  },
  'fr': {
    'dashboard':'Tableau de bord','products':'Articles','receiving':'Réception','issuing':'Sorties','sales':'Ventes',
    'suppliers':'Fournisseurs','recipients':'Destinataires','reports':'Rapports et relevés','settings':'Paramètres','more':'Plus','supplierStatement':'Relevé fournisseur',
    'welcome':'Bienvenue dans NaeemSoft-WMS','offlineSingle':'Gérez un seul dépôt localement sur cet appareil, sans Internet.',
    'statusLegend':'Couleurs d’état des articles','noProducts':'Aucun article enregistré.','noAvailableProducts':'Aucun article disponible pour la sortie.',
    'receivingRule':'Choisissez un fournisseur et ajoutez les articles au reçu. Le stock augmente après validation.',
    'issuingRule':'Choisissez un destinataire et ajoutez les articles. Chaque ligne est tarifée; le stock diminue après validation.',
    'cashierFoundation':'La grille des articles fait partie de la base de la caisse.','language':'Langue de l’application','localDb':'Base de données locale',
    'offlineOnly':'Fonctionne hors ligne','responsive':'Adapté aux téléphones et tablettes',
    'draftSaved':'Brouillon enregistré','documentApproved':'Document validé et stock mis à jour',
    'selectSupplier':'Choisir un fournisseur','selectRecipient':'Choisir un destinataire','invoiceCart':'Panier du document',
    'documentNumber':'Numéro du document','cartEmpty':'Ajoutez des articles depuis la grille','quantity':'Quantité',
    'unitCost':'Coût unitaire','unitPrice':'Prix unitaire','remove':'Supprimer','total':'Total',
    'saveDraft':'Enregistrer le brouillon','approveDocument':'Valider le document','cancelDraft':'Annuler le brouillon',
    'addSupplierFirst':'Ajoutez un fournisseur avant la réception','addRecipientFirst':'Ajoutez un destinataire avant la sortie',
    'refresh':'Actualiser',
    'addProduct':'Ajouter un article','productName':'Nom de l’article','baseUnit':'Unité de base',
    'minimumStock':'Stock minimum','save':'Enregistrer','cancel':'Annuler','addPartner':'Ajouter un contact',
    'name':'Nom','phone':'Téléphone','address':'Adresse','noPartners':'Aucun contact enregistré',
    'approvedReceipts':'Réceptions validées','approvedIssues':'Sorties validées','stockMovements':'Mouvements de stock',
  },
};
