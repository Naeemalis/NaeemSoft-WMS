import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const NaeemWmsApp());

class WmsApi {
  WmsApi({required this.baseUrl, required this.apiKey});

  final String baseUrl;
  final String apiKey;

  Future<dynamic> get(String path) => _send('GET', path);

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) =>
      _send('POST', path, body);

  Future<dynamic> _send(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (baseUrl.trim().isEmpty) {
      throw Exception('أدخل رابط الخادم من الإعدادات أولاً');
    }
    final url = Uri.parse('${baseUrl.trim().replaceAll(RegExp(r'/+$'), '')}$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (path != '/health' && apiKey.isNotEmpty) 'X-API-Key': apiKey,
    };
    late http.Response response;
    try {
      if (method == 'GET') {
        response = await http.get(url, headers: headers).timeout(
              const Duration(seconds: 15),
            );
      } else {
        response = await http
            .post(url, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 20));
      }
    } catch (error) {
      throw Exception('تعذر الاتصال بالخادم: $error');
    }
    dynamic data;
    try {
      data = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    } catch (_) {
      data = response.body;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = data is Map ? data['detail'] : data.toString();
      throw Exception(message ?? 'خطأ من الخادم: ${response.statusCode}');
    }
    return data;
  }
}

class NaeemWmsApp extends StatefulWidget {
  const NaeemWmsApp({super.key});

  @override
  State<NaeemWmsApp> createState() => _NaeemWmsAppState();
}

class _NaeemWmsAppState extends State<NaeemWmsApp> {
  int _tab = 0;
  String _baseUrl = '';
  String _apiKey = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _baseUrl = prefs.getString('api_url') ?? '';
      _apiKey = prefs.getString('api_key') ?? '';
      _loaded = true;
    });
  }

  Future<void> _saveSettings(String url, String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_url', url.trim());
    await prefs.setString('api_key', key.trim());
    if (!mounted) return;
    setState(() {
      _baseUrl = url.trim();
      _apiKey = key.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    final api = WmsApi(baseUrl: _baseUrl, apiKey: _apiKey);
    final pages = <Widget>[
      DashboardPage(api: api),
      ProductsPage(api: api),
      StockPage(api: api),
      ReceiptsPage(api: api),
      SettingsPage(
        baseUrl: _baseUrl,
        apiKey: _apiKey,
        onSave: _saveSettings,
      ),
    ];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NaeemSoft-WMS',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF176B5B),
        scaffoldBackgroundColor: const Color(0xFFF5F7F6),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF5F7F6),
          centerTitle: false,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: !_loaded
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : Scaffold(
              appBar: AppBar(
                title: const Text(
                  'NaeemSoft-WMS',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                actions: [
                  IconButton(
                    tooltip: 'الإعدادات',
                    onPressed: () => setState(() => _tab = 4),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
              body: IndexedStack(index: _tab, children: pages),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (value) => setState(() => _tab = value),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    selectedIcon: Icon(Icons.dashboard),
                    label: 'الرئيسية',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.inventory_2_outlined),
                    selectedIcon: Icon(Icons.inventory_2),
                    label: 'الأصناف',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.warehouse_outlined),
                    selectedIcon: Icon(Icons.warehouse),
                    label: 'المخزون',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.local_shipping_outlined),
                    selectedIcon: Icon(Icons.local_shipping),
                    label: 'التوريد',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: 'الإعدادات',
                  ),
                ],
              ),
            ),
    );
  }
}

class PageFrame extends StatelessWidget {
  const PageFrame({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async {
          final state = context.findAncestorStateOfType<_RefreshableState>();
          await state?.reload();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          child: child,
        ),
      );
}

abstract class _RefreshableState<T extends StatefulWidget> extends State<T> {
  Future<void> reload();
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({required this.api, super.key});
  final WmsApi api;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends _RefreshableState<DashboardPage> {
  late Future<dynamic> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.get('/api/dashboard');
  }

  @override
  Future<void> reload() async {
    setState(() => _future = widget.api.get('/api/dashboard'));
    await _future;
  }

  @override
  Widget build(BuildContext context) => PageFrame(
        child: FutureBuilder<dynamic>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) return ErrorPanel(message: snapshot.error.toString());
            if (!snapshot.hasData) return const LoadingPanel();
            final data = snapshot.data as Map<String, dynamic>;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('ملخص المخزن', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('نظرة سريعة على حركة وأرصدة المخزون', style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(height: 18),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.35,
                  children: [
                    MetricCard(label: 'الأصناف المسجلة', value: '${data['products_count'] ?? 0}', icon: Icons.category_outlined),
                    MetricCard(label: 'أصناف لها رصيد', value: '${data['stocked_products_count'] ?? 0}', icon: Icons.inventory_outlined),
                    MetricCard(label: 'إجمالي الوحدات الأساسية', value: '${data['total_base_units'] ?? 0}', icon: Icons.scale_outlined),
                    MetricCard(label: 'توريدات بانتظار الاعتماد', value: '${data['pending_receipts_count'] ?? 0}', icon: Icons.pending_actions_outlined),
                  ],
                ),
                const SizedBox(height: 18),
                const InfoPanel(
                  icon: Icons.rule_folder_outlined,
                  title: 'قاعدة اعتماد المخزون',
                  message: 'لا تدخل كميات التوريد في الرصيد المتاح إلا بعد اعتماد الاستلام رسمياً.',
                ),
              ],
            );
          },
        ),
      );
}

class MetricCard extends StatelessWidget {
  const MetricCard({required this.label, required this.value, required this.icon, super.key});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              Text(value, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ],
          ),
        ),
      );
}

class ProductsPage extends StatefulWidget {
  const ProductsPage({required this.api, super.key});
  final WmsApi api;

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends _RefreshableState<ProductsPage> {
  late Future<dynamic> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.get('/api/products');
  }

  @override
  Future<void> reload() async {
    setState(() => _future = widget.api.get('/api/products'));
    await _future;
  }

  Future<void> _addProduct() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ProductFormDialog(api: widget.api),
    );
    if (result == true) await reload();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: Text('إدارة الأصناف', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
                FilledButton.icon(
                  onPressed: _addProduct,
                  icon: const Icon(Icons.add),
                  label: const Text('صنف جديد'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<dynamic>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) return ErrorPanel(message: snapshot.error.toString());
                if (!snapshot.hasData) return const LoadingPanel();
                final items = (snapshot.data as List).cast<Map<String, dynamic>>();
                if (items.isEmpty) return const EmptyPanel(message: 'لا توجد أصناف. أضف أول صنف من إدارة الأصناف.');
                return Column(
                  children: items.map((item) {
                    final units = (item['units'] as List? ?? []);
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 9),
                      child: ListTile(
                        title: Text(item['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${item['sku']} • ${units.length} وحدات معرفة'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${item['quantity_on_hand_base'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                            Text(item['base_unit_name']?.toString() ?? 'الوحدة الأساسية', style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      );
}

class _UnitFields {
  _UnitFields({this.isBase = false}) {
    factor.text = isBase ? '1' : '';
  }
  final bool isBase;
  final code = TextEditingController();
  final name = TextEditingController();
  final factor = TextEditingController();
  final price = TextEditingController();

  void dispose() {
    code.dispose();
    name.dispose();
    factor.dispose();
    price.dispose();
  }
}

class ProductFormDialog extends StatefulWidget {
  const ProductFormDialog({required this.api, super.key});
  final WmsApi api;

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _sku = TextEditingController();
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _currency = TextEditingController(text: 'DJF');
  final _units = <_UnitFields>[_UnitFields(isBase: true)];
  bool _saving = false;

  @override
  void dispose() {
    _sku.dispose();
    _name.dispose();
    _brand.dispose();
    _currency.dispose();
    for (final unit in _units) {
      unit.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) => value == null || value.trim().isEmpty ? 'هذا الحقل مطلوب' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final units = _units.map((unit) => {
        'code': unit.code.text.trim(),
        'name': unit.name.text.trim(),
        'factor_to_base': double.parse(unit.factor.text),
        'is_base': unit.isBase,
        'sale_price': double.parse(unit.price.text),
        'purchase_allowed': true,
        'sale_allowed': true,
      }).toList();
      await widget.api.post('/api/products', {
        'sku': _sku.text.trim(),
        'name': _name.text.trim(),
        'brand': _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        'currency_code': _currency.text.trim().toUpperCase(),
        'units': units,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController controller, String label, {String? Function(String?)? validator, TextInputType? keyboard}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('تعريف صنف جديد'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(_sku, 'رمز الصنف', validator: _required),
                  _field(_name, 'اسم الصنف', validator: _required),
                  _field(_brand, 'العلامة التجارية (اختياري)'),
                  _field(_currency, 'رمز العملة (3 أحرف)', validator: (v) => (v?.trim().length ?? 0) != 3 ? 'أدخل رمز عملة من 3 أحرف' : null),
                  const Divider(),
                  const Align(alignment: Alignment.centerRight, child: Text('الوحدات وأسعار البيع المستقلة', style: TextStyle(fontWeight: FontWeight.bold))),
                  const SizedBox(height: 8),
                  ..._units.asMap().entries.map((entry) {
                    final index = entry.key;
                    final unit = entry.value;
                    return Card(
                      elevation: 0,
                      color: const Color(0xFFF1F5F3),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(unit.isBase ? 'الوحدة الأساسية' : 'وحدة إضافية ${index}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(height: 8),
                            _field(unit.code, 'رمز الوحدة', validator: _required),
                            _field(unit.name, 'اسم الوحدة', validator: _required),
                            _field(unit.factor, 'كم وحدة أساسية داخلها', validator: (v) {
                              final n = double.tryParse(v ?? '');
                              if (n == null || n <= 0) return 'أدخل معامل تحويل صحيح';
                              if (unit.isBase && n != 1) return 'معامل الوحدة الأساسية يجب أن يساوي 1';
                              return null;
                            }, keyboard: const TextInputType.numberWithOptions(decimal: true)),
                            _field(unit.price, 'سعر البيع لهذه الوحدة', validator: (v) {
                              final n = double.tryParse(v ?? '');
                              return n == null || n < 0 ? 'أدخل السعر' : null;
                            }, keyboard: const TextInputType.numberWithOptions(decimal: true)),
                          ],
                        ),
                      ),
                    );
                  }),
                  TextButton.icon(
                    onPressed: () => setState(() => _units.add(_UnitFields())),
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('إضافة وحدة / عبوة'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ الصنف')),
        ],
      );
}

class StockPage extends StatefulWidget {
  const StockPage({required this.api, super.key});
  final WmsApi api;

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends _RefreshableState<StockPage> {
  late Future<dynamic> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.get('/api/stock');
  }

  @override
  Future<void> reload() async {
    setState(() => _future = widget.api.get('/api/stock'));
    await _future;
  }

  @override
  Widget build(BuildContext context) => PageFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('أرصدة المخزون', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text('يعرض الرصيد بأصغر وحدة فقط', style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 12),
            FutureBuilder<dynamic>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) return ErrorPanel(message: snapshot.error.toString());
                if (!snapshot.hasData) return const LoadingPanel();
                final rows = (snapshot.data as List).cast<Map<String, dynamic>>();
                if (rows.isEmpty) return const EmptyPanel(message: 'لا توجد أصناف مسجلة.');
                return Column(
                  children: rows.map((row) {
                    final qty = double.tryParse(row['quantity_on_hand_base'].toString()) ?? 0;
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(row['product_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(row['sku']?.toString() ?? ''),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_formatNumber(qty), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            Text(row['base_unit_name']?.toString() ?? '', style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      );
}

class ReceiptsPage extends StatefulWidget {
  const ReceiptsPage({required this.api, super.key});
  final WmsApi api;

  @override
  State<ReceiptsPage> createState() => _ReceiptsPageState();
}

class _ReceiptsPageState extends _RefreshableState<ReceiptsPage> {
  late Future<dynamic> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.get('/api/receipts');
  }

  @override
  Future<void> reload() async {
    setState(() => _future = widget.api.get('/api/receipts'));
    await _future;
  }

  Future<void> _newSupplier() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إضافة مورد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم المورد')),
            const SizedBox(height: 10),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              try {
                await widget.api.post('/api/suppliers', {'name': name.text.trim(), 'phone': phone.text.trim()});
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              } catch (error) {
                if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(error.toString())));
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    name.dispose();
    phone.dispose();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة المورد')));
    }
  }

  Future<void> _newReceipt() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => NewReceiptDialog(api: widget.api),
    );
    if (saved == true) await reload();
  }

  Future<void> _changeStatus(String id, String action) async {
    try {
      await widget.api.post('/api/receipts/$id/$action');
      await reload();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _statusLabel(String status) => switch (status) {
        'draft' => 'مسودة',
        'pending_approval' => 'بانتظار الاعتماد',
        'approved' => 'معتمدة',
        'cancelled' => 'ملغاة',
        _ => status,
      };

  @override
  Widget build(BuildContext context) => PageFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: Text('استلام التوريدات', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
                IconButton(onPressed: _newSupplier, tooltip: 'إضافة مورد', icon: const Icon(Icons.person_add_alt_1)),
                FilledButton.icon(onPressed: _newReceipt, icon: const Icon(Icons.add), label: const Text('توريد')),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<dynamic>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) return ErrorPanel(message: snapshot.error.toString());
                if (!snapshot.hasData) return const LoadingPanel();
                final rows = (snapshot.data as List).cast<Map<String, dynamic>>();
                if (rows.isEmpty) return const EmptyPanel(message: 'لا توجد فواتير توريد بعد.');
                return Column(
                  children: rows.map((row) {
                    final status = row['status']?.toString() ?? '';
                    final id = row['id'].toString();
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 9),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('فاتورة ${row['receipt_number']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('${row['supplier_name']} • ${row['receipt_date']}'),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Chip(label: Text(_statusLabel(status))),
                                const Spacer(),
                                Text('${row['total']} ${row['currency_code']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            if (status == 'draft')
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton(
                                  onPressed: () => _changeStatus(id, 'submit'),
                                  child: const Text('إرسال للاعتماد'),
                                ),
                              ),
                            if (status == 'pending_approval')
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton(
                                  onPressed: () => _changeStatus(id, 'approve'),
                                  child: const Text('اعتماد الاستلام'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      );
}

class NewReceiptDialog extends StatefulWidget {
  const NewReceiptDialog({required this.api, super.key});
  final WmsApi api;

  @override
  State<NewReceiptDialog> createState() => _NewReceiptDialogState();
}

class _NewReceiptDialogState extends State<NewReceiptDialog> {
  late Future<List<dynamic>> _lookups;
  String? _supplierId;
  String? _productUnitId;
  final _number = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _cost = TextEditingController(text: '0');
  final _currency = TextEditingController(text: 'DJF');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _lookups = Future.wait([
      widget.api.get('/api/suppliers'),
      widget.api.get('/api/products'),
    ]);
  }

  @override
  void dispose() {
    _number.dispose();
    _quantity.dispose();
    _cost.dispose();
    _currency.dispose();
    super.dispose();
  }

  Future<void> _save(List<dynamic> suppliers, List<dynamic> products) async {
    if (_supplierId == null || _productUnitId == null || _number.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أكمل المورد ورقم الفاتورة والصنف')));
      return;
    }
    final qty = double.tryParse(_quantity.text);
    final cost = double.tryParse(_cost.text);
    if (qty == null || qty <= 0 || cost == null || cost < 0) return;
    setState(() => _saving = true);
    try {
      await widget.api.post('/api/receipts', {
        'supplier_id': _supplierId,
        'receipt_number': _number.text.trim(),
        'currency_code': _currency.text.trim().toUpperCase(),
        'items': [
          {'product_unit_id': _productUnitId, 'quantity': qty, 'unit_cost': cost}
        ],
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('فاتورة توريد جديدة'),
        content: SizedBox(
          width: 460,
          child: FutureBuilder<List<dynamic>>(
            future: _lookups,
            builder: (context, snapshot) {
              if (snapshot.hasError) return ErrorPanel(message: snapshot.error.toString());
              if (!snapshot.hasData) return const SizedBox(height: 100, child: LoadingPanel());
              final suppliers = snapshot.data![0] as List;
              final products = snapshot.data![1] as List;
              final unitOptions = <Map<String, dynamic>>[];
              for (final product in products) {
                for (final unit in (product['units'] as List? ?? [])) {
                  unitOptions.add({
                    'id': unit['product_unit_id'].toString(),
                    'label': '${product['name']} — ${unit['unit_name']}',
                  });
                }
              }
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: _number, decoration: const InputDecoration(labelText: 'رقم فاتورة التوريد')),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _supplierId,
                      decoration: const InputDecoration(labelText: 'المورد'),
                      items: suppliers.map((s) => DropdownMenuItem<String>(value: s['id'].toString(), child: Text(s['name'].toString()))).toList(),
                      onChanged: (v) => setState(() => _supplierId = v),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _productUnitId,
                      decoration: const InputDecoration(labelText: 'الصنف ووحدة الشراء'),
                      items: unitOptions.map((u) => DropdownMenuItem<String>(value: u['id'].toString(), child: Text(u['label'].toString(), overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) => setState(() => _productUnitId = v),
                    ),
                    const SizedBox(height: 10),
                    TextField(controller: _quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الكمية بوحدة الشراء')),
                    const SizedBox(height: 10),
                    TextField(controller: _cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'تكلفة وحدة الشراء')),
                    const SizedBox(height: 10),
                    TextField(controller: _currency, decoration: const InputDecoration(labelText: 'رمز العملة')),
                    if (suppliers.isEmpty || unitOptions.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text('يجب تسجيل مورد وصنف واحد على الأقل قبل إنشاء التوريد.', style: TextStyle(color: Colors.red)),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: _saving ? null : () async {
              final data = await _lookups;
              await _save(data[0], data[1]);
            },
            child: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ كمسودة'),
          ),
        ],
      );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.baseUrl,
    required this.apiKey,
    required this.onSave,
    super.key,
  });

  final String baseUrl;
  final String apiKey;
  final Future<void> Function(String, String) onSave;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _url = TextEditingController(text: widget.baseUrl);
  late final TextEditingController _key = TextEditingController(text: widget.apiKey);
  bool _testing = false;
  String? _result;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      final api = WmsApi(baseUrl: _url.text, apiKey: _key.text);
      final response = await api.get('/health');
      if (mounted) setState(() => _result = 'الاتصال ناجح: ${response['service']}');
    } catch (error) {
      if (mounted) setState(() => _result = error.toString());
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    await widget.onSave(_url.text, _key.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ إعدادات الاتصال')));
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('إعدادات الاتصال', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const InfoPanel(
              icon: Icons.link,
              title: 'ربط التطبيق بالخادم',
              message: 'أدخل عنوان API الخاص بالخادم ومفتاح الوصول. إذا كان الهاتف والخادم على الشبكة نفسها، استخدم عنوان IP المحلي للخادم والمنفذ 8000.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'رابط الخادم', hintText: 'http://192.168.1.20:8000'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'مفتاح API'),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('حفظ الإعدادات')),
            OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: const Icon(Icons.wifi_tethering),
              label: Text(_testing ? 'جارٍ الاختبار...' : 'اختبار الاتصال'),
            ),
            if (_result != null) Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_result!, style: TextStyle(color: _result!.startsWith('الاتصال ناجح') ? Colors.green : Colors.red)),
            ),
            const SizedBox(height: 20),
            const Text('الإصدار 0.1.0 • Android', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
}

class InfoPanel extends StatelessWidget {
  const InfoPanel({required this.icon, required this.title, required this.message, super.key});
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: const Color(0xFFEAF2EF),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(message, style: const TextStyle(height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class LoadingPanel extends StatelessWidget {
  const LoadingPanel({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: CircularProgressIndicator()),
      );
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({required this.message, super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(26),
        child: Center(child: Text(message, textAlign: TextAlign.center)),
      );
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({required this.message, super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.cloud_off_outlined, size: 34, color: Colors.orange),
              const SizedBox(height: 8),
              const Text('تعذر تحميل البيانات', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              const Text('تحقق من إعداد رابط الخادم ومفتاح API.', textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}
