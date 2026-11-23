import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../data/local_database.dart';

class ProductManagementPage extends StatefulWidget {
  const ProductManagementPage({required this.tr, this.autoOpenAdd = false, this.onDone, super.key});
  final String Function(String) tr;
  final bool autoOpenAdd;
  final VoidCallback? onDone;

  @override
  State<ProductManagementPage> createState() => _ProductManagementPageState();
}

class _ProductManagementPageState extends State<ProductManagementPage> {
  List<Map<String, Object?>> _products = [];
  List<Map<String, Object?>> _units = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (widget.autoOpenAdd && mounted) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _addProduct(); });
    });
  }

  Future<void> _load() async {
    final db = await LocalDatabase.instance.database;
    final products = await LocalDatabase.instance.getProducts();
    final units = await db.query('units', orderBy: 'name_ar');
    if (!mounted) return;
    setState(() {
      _products = products;
      _units = units;
      _loading = false;
    });
  }

  Future<void> _addProduct() async {
    final name = TextEditingController();
    final minimum = TextEditingController(text: '0');
    int? baseUnitId = _units.isEmpty ? null : _units.first['id'] as int;
    final drafts = <int, _ProductUnitDraft>{};
    if (baseUnitId != null) {
      drafts[baseUnitId] = _ProductUnitDraft(isSelected: true, factor: '1');
    }

    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(widget.tr('addProduct')),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 460,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                    controller: name,
                    autofocus: true,
                    decoration: InputDecoration(labelText: widget.tr('productName')),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: baseUnitId,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: widget.tr('baseUnit')),
                    items: _units.map((unit) => DropdownMenuItem<int>(
                      value: unit['id'] as int,
                      child: Text((unit['name_ar'] ?? unit['code']).toString()),
                    )).toList(),
                    onChanged: (value) => setDialogState(() {
                      baseUnitId = value;
                      if (value != null) {
                        final draft = drafts.putIfAbsent(
                          value, () => _ProductUnitDraft(isSelected: true, factor: '1'),
                        );
                        draft.isSelected = true;
                        draft.factor.text = '1';
                      }
                    }),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: minimum,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: widget.tr('minimumStock')),
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text('وحدات الصنف وأسعار البيع ومعاملات التحويل',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 330,
                    child: ListView(
                      children: _units.map((unit) {
                        final id = unit['id'] as int;
                        final isBase = id == baseUnitId;
                        final draft = drafts.putIfAbsent(
                          id, () => _ProductUnitDraft(isSelected: false, factor: '1'),
                        );
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              children: [
                                CheckboxListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  value: draft.isSelected || isBase,
                                  title: Text((unit['name_ar'] ?? unit['code']).toString()),
                                  subtitle: isBase ? const Text('وحدة الأساس — معامل التحويل = 1') : null,
                                  onChanged: isBase ? null : (value) => setDialogState(
                                    () => draft.isSelected = value ?? false,
                                  ),
                                ),
                                if (draft.isSelected || isBase) ...[
                                  Row(children: [
                                    Expanded(
                                      child: TextField(
                                        controller: draft.factor,
                                        enabled: !isBase,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          labelText: 'كم وحدة أساس؟',
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: draft.salePrice,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          labelText: 'سعر البيع',
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                  ]),
                                  Wrap(
                                    spacing: 12,
                                    children: [
                                      Row(mainAxisSize: MainAxisSize.min, children: [
                                        Checkbox(
                                          value: draft.canReceive,
                                          onChanged: (v) => setDialogState(() => draft.canReceive = v ?? false),
                                        ),
                                        const Text('يستخدم في التوريد'),
                                      ]),
                                      Row(mainAxisSize: MainAxisSize.min, children: [
                                        Checkbox(
                                          value: draft.canIssue,
                                          onChanged: (v) => setDialogState(() => draft.canIssue = v ?? false),
                                        ),
                                        const Text('يستخدم في الصرف'),
                                      ]),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ]),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(widget.tr('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(widget.tr('save')),
              ),
            ],
          ),
        ),
      );
      if (result != true || !mounted) return;

      final parsedMinimum = double.tryParse(minimum.text.trim());
      if (name.text.trim().isEmpty || baseUnitId == null ||
          parsedMinimum == null || !parsedMinimum.isFinite || parsedMinimum < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أدخل اسم الصنف ووحدة الأساس وحد إعادة طلب صحيحاً.')),
        );
        return;
      }
      final selected = drafts.entries.where((entry) =>
        entry.value.isSelected || entry.key == baseUnitId).toList();
      if (selected.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اختر وحدة واحدة على الأقل للصنف.')),
        );
        return;
      }
      for (final entry in selected) {
        final draft = entry.value;
        final factor = entry.key == baseUnitId ? 1.0 : double.tryParse(draft.factor.text.trim());
        final price = double.tryParse(draft.salePrice.text.trim());
        if (factor == null || !factor.isFinite || factor <= 0 ||
            price == null || !price.isFinite || price < 0 ||
            (draft.canIssue && price <= 0) ||
            (!draft.canIssue && !draft.canReceive)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تحقق من معامل التحويل وسعر البيع واختيار استخدام الوحدة.')),
          );
          return;
        }
      }

      final db = await LocalDatabase.instance.database;
      await db.transaction((txn) async {
        final productId = await txn.insert('products', {
          'name_ar': name.text.trim(),
          'name_en': name.text.trim(),
          'name_fr': name.text.trim(),
          'base_unit_id': baseUnitId,
          'minimum_stock': parsedMinimum,
        });
        for (final entry in selected) {
          final draft = entry.value;
          await txn.insert('product_units', {
            'product_id': productId,
            'unit_id': entry.key,
            'factor_to_base': entry.key == baseUnitId ? 1 : double.parse(draft.factor.text.trim()),
            'sale_price': double.parse(draft.salePrice.text.trim()),
            'can_receive': draft.canReceive ? 1 : 0,
            'can_issue': draft.canIssue ? 1 : 0,
          });
        }
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت إضافة الصنف ووحداته وأسعار البيع بنجاح.')),
        );
        widget.onDone?.call();
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذرت إضافة الصنف: $error')),
      );
    } finally {
      name.dispose();
      minimum.dispose();
      for (final draft in drafts.values) {
        draft.dispose();
      }
    }
  }

  Future<void> _editProduct(Map<String, Object?> product) async {
    final name = TextEditingController(text: (product['name_ar'] ?? '').toString());
    final minimum = TextEditingController(text: ((product['minimum_stock'] as num?) ?? 0).toString());
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تعديل بيانات الصنف'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: InputDecoration(labelText: widget.tr('productName'))),
              const SizedBox(height: 10),
              TextField(controller: minimum,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: widget.tr('minimumStock'))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(widget.tr('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(widget.tr('save'))),
          ],
        ),
      );
      if (result != true || !mounted) return;
      final min = double.tryParse(minimum.text.trim());
      if (name.text.trim().isEmpty || min == null || !min.isFinite || min < 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل اسم الصنف وحد إعادة طلب صحيحاً.')));
        return;
      }
      final db = await LocalDatabase.instance.database;
      await db.update('products', {
        'name_ar': name.text.trim(),
        'name_en': name.text.trim(),
        'name_fr': name.text.trim(),
        'minimum_stock': min,
      }, where: 'id = ?', whereArgs: [product['id']]);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث بيانات الصنف.')),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحديث الصنف: $error')),
      );
    } finally {
      name.dispose();
      minimum.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width < 420 ? 2 : width < 720 ? 3 : width < 1100 ? 5 : 7;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _units.isEmpty ? null : _addProduct,
        icon: const Icon(Icons.add),
        label: Text(widget.tr('addProduct')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _products.isEmpty
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.inventory_2_outlined, size: 44),
                    const SizedBox(height: 10),
                    Text(widget.tr('noProducts')),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _units.isEmpty ? null : _addProduct,
                      icon: const Icon(Icons.add),
                      label: Text(widget.tr('addProduct')),
                    ),
                  ]),
                ))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: columns >= 5 ? 0.85 : 1.2,
                  ),
                  itemCount: _products.length,
                  itemBuilder: (context, index) {
                    final product = _products[index];
                    final quantity = (product['available_quantity'] as num?)?.toDouble() ?? 0;
                    final minimum = (product['minimum_stock'] as num?)?.toDouble() ?? 0;
                    final color = quantity <= 0 ? Colors.red : quantity <= minimum && minimum > 0 ? Colors.orange : Colors.green;
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _editProduct(product),
                        child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.inventory_2_outlined, color: color, size: 28),
                          const SizedBox(height: 8),
                          Text((product['name_ar'] ?? '').toString(), textAlign: TextAlign.center,
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text('${quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 2)} ${product['base_unit_name'] ?? ''}'),
                        ]),
                      ),
                      ),
                    );
                  },
                ),
    );
  }
}

class PartnerManagementPage extends StatefulWidget {
  const PartnerManagementPage({required this.tr, required this.suppliers, this.autoOpenAdd = false, this.onDone, super.key});
  final String Function(String) tr;
  final bool suppliers;
  final bool autoOpenAdd;
  final VoidCallback? onDone;

  @override
  State<PartnerManagementPage> createState() => _PartnerManagementPageState();
}

class _PartnerManagementPageState extends State<PartnerManagementPage> {
  List<Map<String, Object?>> _items = [];
  bool _loading = true;
  String get _table => widget.suppliers ? 'suppliers' : 'recipients';

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (widget.autoOpenAdd && mounted) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _add(); });
    });
  }

  Future<void> _load() async {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(_table, orderBy: 'name COLLATE NOCASE');
    if (!mounted) return;
    setState(() { _items = rows; _loading = false; });
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final address = TextEditingController();
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(widget.tr('addPartner')),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: name, autofocus: true,
                  decoration: InputDecoration(labelText: widget.tr('name'))),
                const SizedBox(height: 10),
                TextField(controller: phone, keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: widget.tr('phone'))),
                const SizedBox(height: 10),
                TextField(controller: address, decoration: InputDecoration(labelText: widget.tr('address'))),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(widget.tr('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(widget.tr('save'))),
          ],
        ),
      );
      if (result != true || !mounted) return;
      if (name.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اسم المورد أو المستلم مطلوب.')),
        );
        return;
      }
      final db = await LocalDatabase.instance.database;
      await db.insert(_table, {
        'name': name.text.trim(),
        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'address': address.text.trim().isEmpty ? null : address.text.trim(),
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.suppliers ? 'تمت إضافة المورد بنجاح.' : 'تمت إضافة المستلم بنجاح.')));
        widget.onDone?.call();
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذرت إضافة الجهة: $error')),
      );
    } finally {
      name.dispose();
      phone.dispose();
      address.dispose();
    }
  }

  Future<void> _edit(Map<String, Object?> item) async {
    final name = TextEditingController(text: (item['name'] ?? '').toString());
    final phone = TextEditingController(text: (item['phone'] ?? '').toString());
    final address = TextEditingController(text: (item['address'] ?? '').toString());
    var active = item['is_active'] == 1;
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('تعديل بيانات الجهة'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 420,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(controller: name, decoration: InputDecoration(labelText: widget.tr('name'))),
                  const SizedBox(height: 10),
                  TextField(controller: phone, keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: widget.tr('phone'))),
                  const SizedBox(height: 10),
                  TextField(controller: address, decoration: InputDecoration(labelText: widget.tr('address'))),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('الجهة نشطة'),
                    value: active,
                    onChanged: (value) => setDialogState(() => active = value),
                  ),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(widget.tr('cancel'))),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(widget.tr('save'))),
            ],
          ),
        ),
      );
      if (result != true || !mounted) return;
      if (name.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اسم الجهة مطلوب.')));
        return;
      }
      final db = await LocalDatabase.instance.database;
      await db.update(_table, {
        'name': name.text.trim(),
        'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'address': address.text.trim().isEmpty ? null : address.text.trim(),
        'is_active': active ? 1 : 0,
      }, where: 'id = ?', whereArgs: [item['id']]);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث بيانات الجهة.')),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحديث بيانات الجهة: $error')),
      );
    } finally {
      name.dispose();
      phone.dispose();
      address.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _add,
      icon: const Icon(Icons.person_add_alt_1),
      label: Text(widget.tr('addPartner')),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _items.isEmpty
            ? Center(child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(widget.suppliers ? Icons.local_shipping_outlined : Icons.people_alt_outlined, size: 44),
                  const SizedBox(height: 10),
                  Text(widget.tr('noPartners')),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: Text(widget.tr('addPartner')),
                  ),
                ]),
              ))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return ListTile(
                    leading: CircleAvatar(child: Icon(widget.suppliers ? Icons.local_shipping_outlined : Icons.person_outline)),
                    title: Text((item['name'] ?? '').toString()),
                    subtitle: Text([
                      if ((item['phone'] ?? '').toString().isNotEmpty) item['phone'].toString(),
                      if ((item['address'] ?? '').toString().isNotEmpty) item['address'].toString(),
                    ].join(' • ')),
                    onTap: () => _edit(item),
                    trailing: IconButton(
                      tooltip: 'تعديل / تفعيل الجهة',
                      onPressed: () => _edit(item),
                      icon: Icon(item['is_active'] == 1 ? Icons.edit_outlined : Icons.edit_off_outlined),
                    ),
                  );
                },
              ),
  );
}

class BasicReportsPage extends StatefulWidget {
  const BasicReportsPage({required this.tr, super.key});
  final String Function(String) tr;

  @override
  State<BasicReportsPage> createState() => _BasicReportsPageState();
}

class _BasicReportsPageState extends State<BasicReportsPage> {
  Map<String, int> _counts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await LocalDatabase.instance.database;
    final values = <String, int>{
      'products': Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM products WHERE is_active = 1')) ?? 0,
      'suppliers': Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM suppliers WHERE is_active = 1')) ?? 0,
      'recipients': Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM recipients WHERE is_active = 1')) ?? 0,
      'receipts': Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM receipts WHERE status = 'approved'")) ?? 0,
      'issues': Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM issues WHERE status = 'approved'")) ?? 0,
      'movements': Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM stock_movements')) ?? 0,
    };
    if (!mounted) return;
    setState(() { _counts = values; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final labels = {
      'products': 'products',
      'suppliers': 'suppliers',
      'recipients': 'recipients',
      'receipts': 'approvedReceipts',
      'issues': 'approvedIssues',
      'movements': 'stockMovements',
    };
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.tr('reports'), style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          ..._counts.entries.map((entry) => Card(
            child: ListTile(
              leading: const Icon(Icons.assessment_outlined),
              title: Text(widget.tr(labels[entry.key] ?? entry.key)),
              trailing: Text(entry.value.toString(), style: Theme.of(context).textTheme.titleLarge),
            ),
          )),
        ],
      ),
    );
  }
}


class _ProductUnitDraft {
  _ProductUnitDraft({required this.isSelected, String factor = '1'})
      : factor = TextEditingController(text: factor),
        salePrice = TextEditingController(text: '0');

  bool isSelected;
  bool canReceive = true;
  bool canIssue = true;
  final TextEditingController factor;
  final TextEditingController salePrice;

  void dispose() {
    factor.dispose();
    salePrice.dispose();
  }
}
