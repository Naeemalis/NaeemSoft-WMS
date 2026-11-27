import 'package:flutter/material.dart';

import '../data/sales_operations.dart';
import '../data/local_database.dart';

class SalesCashierPage extends StatefulWidget {
  const SalesCashierPage({
    required this.tr,
    this.onOpenRecipients,
    this.onOpenProducts,
    super.key,
  });

  final String Function(String) tr;
  final VoidCallback? onOpenRecipients;
  final VoidCallback? onOpenProducts;

  @override
  State<SalesCashierPage> createState() => _SalesCashierPageState();
}

class _IssueCashierPageState extends State<IssueCashierPage> {
  List<Map<String, Object?>> _products = [];
  List<Map<String, Object?>> _recipients = [];
  final Map<int, List<Map<String, Object?>>> _unitsByProduct = {};
  final List<_SaleCartLine> _cart = [];

  int? _recipientId;
  int? _saleId;
  String? _saleNumber;
  String _quantity = '0';
  Map<String, Object?>? _selectedProduct;
  Map<String, Object?>? _selectedUnit;
  bool _loading = true;
  bool _busy = false;
  VoidCallback? _refreshCartSheet;

  String tr(String key) => widget.tr(key);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await LocalDatabase.instance.database;
    final products = await LocalDatabase.instance.getProducts();
    final unitRows = await db.rawQuery('''
      SELECT pu.product_id, pu.unit_id, pu.factor_to_base, pu.sale_price,
             u.name_ar, u.code
      FROM product_units pu
      JOIN units u ON u.id = pu.unit_id
      WHERE pu.can_sell = 1
      ORDER BY pu.id
    ''');
    final recipients = await db.query(
      'recipients',
      where: 'is_active = 1',
      orderBy: 'name COLLATE NOCASE',
    );
    if (!mounted) return;
    setState(() {
      _products = products.where((p) =>
        ((p['available_quantity'] as num?) ?? 0) > 0).toList();
      _recipients = recipients;
      _unitsByProduct.clear();
      for (final row in unitRows) {
        final id = row['product_id'] as int;
        _unitsByProduct.putIfAbsent(id, () => []).add(row);
      }
      if (_recipientId != null &&
          !_recipients.any((p) => p['id'] == _recipientId)) {
        _recipientId = null;
      }
      _loading = false;
    });
  }

  void _enterDigit(String digit) {
    if (_issueId != null || _busy) return;
    setState(() {
      _quantity = _quantity == '0' ? digit : _quantity + digit;
    });
  }

  void _backspace() {
    if (_issueId != null || _busy) return;
    setState(() {
      _quantity = _quantity.length <= 1
          ? '0'
          : _quantity.substring(0, _quantity.length - 1);
    });
  }

  void _addHalf() {
    if (_issueId != null || _busy) return;
    final value = double.tryParse(_quantity) ?? 0;
    setState(() => _quantity = _format(value + 0.5));
  }

  String _format(double value) =>
      value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');

  void _selectProduct(Map<String, Object?> product) {
    if (_issueId != null || _busy) return;
    final units = _unitsByProduct[product['id'] as int] ?? [];
    if (units.isEmpty) {
      _message('لا توجد وحدات بيع معرفة لهذا الصنف.');
      return;
    }
    setState(() {
      _selectedProduct = product;
      _selectedUnit = null;
    });
  }

  void _selectUnit(Map<String, Object?> unit) {
    if (_issueId != null || _busy) return;
    final price = (unit['sale_price'] as num?)?.toDouble() ?? 0;
    if (price <= 0) {
      _message('سعر بيع هذه الوحدة غير معرّف. حدّث تعريف الصنف أولاً.');
      return;
    }
    setState(() => _selectedUnit = unit);
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _addToCart() {
    final product = _selectedProduct;
    final unit = _selectedUnit;
    final quantity = double.tryParse(_quantity);
    if (product == null || unit == null || quantity == null ||
        !quantity.isFinite || quantity <= 0) {
      _message('أدخل الكمية واختر الصنف والوحدة أولاً.');
      return;
    }
    final price = (unit['sale_price'] as num?)?.toDouble() ?? 0;
    final factor = (unit['factor_to_base'] as num?)?.toDouble() ?? 0;
    if (price <= 0 || factor <= 0) {
      _message('سعر البيع أو معامل التحويل غير صحيح.');
      return;
    }
    setState(() {
      _cart.add(_IssueCartLine(
        product: product,
        unitId: unit['unit_id'] as int,
        unitName: (unit['name_ar'] ?? unit['code']).toString(),
        quantity: quantity,
        factorToBase: factor,
        unitPrice: price,
      ));
      _selectedProduct = null;
      _selectedUnit = null;
    });
  }

  double get _total =>
      _cart.fold<double>(0, (sum, line) => sum + line.quantity * line.unitPrice);

  Future<void> _saveDraft() async {
    if (_busy || _issueId != null) return;
    if (_recipientId == null) {
      _message('اختر العميل أولاً.');
      return;
    }
    if (_cart.isEmpty) {
      _message('أضف صنفاً واحداً على الأقل إلى السلة.');
      return;
    }
    setState(() => _busy = true);
    try {
      final db = await LocalDatabase.instance.database;
      final operations = SalesOperations(db);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final number = 'S-' + stamp.toString();
      final id = await operations.createSale(
        number: number,
        recipientId: _recipientId!,
        saleDate: DateTime.now(),
        lines: _cart.map((line) => SaleLineInput(
          productId: line.product['id'] as int,
          unitId: line.unitId,
          quantity: line.quantity,
          factorToBase: line.factorToBase,
          unitPrice: line.unitPrice,
        )).toList(),
      );
      if (!mounted) return;
      setState(() {
        _issueId = id;
        _issueNumber = number;
      });
      _refreshCartSheet?.call();
      _message('تم حفظ مسودة المبيعات • ' + number);
    } catch (error) {
      if (mounted) _message('تعذر حفظ المسودة: ' + error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final id = _issueId;
    if (id == null || _busy) return;
    setState(() => _busy = true);
    try {
      final db = await LocalDatabase.instance.database;
      await InventoryOperations(db).approveSale(id);
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _issueId = null;
        _issueNumber = null;
        _recipientId = null;
        _selectedProduct = null;
        _selectedUnit = null;
        _quantity = '0';
      });
      await _load();
      if (mounted) {
        Navigator.of(context).pop();
        _message(tr('documentApproved'));
      }
    } catch (error) {
      if (mounted) _message('تعذر اعتماد المبيعات: ' + error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelDraft() async {
    final id = _issueId;
    if (id == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إلغاء فاتورة المبيعات'),
        content: const Text('هل تريد إلغاء المسودة؟ لن يتغير المخزون.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('cancelDraft')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final db = await LocalDatabase.instance.database;
      await db.transaction((txn) async {
        final changed = await txn.update(
          'sales',
          {'status': 'cancelled'},
          where: "id = ? AND status IN ('draft','pending_approval')",
          whereArgs: [id],
        );
        if (changed != 1) {
          throw StateError('لا يمكن إلغاء المستند لأنه لم يعد مسودة.');
        }
        await txn.insert('audit_logs', {
          'action': 'cancel',
          'entity_type': 'sale',
          'entity_id': id,
          'details': 'Issue draft cancelled from issue cashier.',
        });
      });
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _issueId = null;
        _issueNumber = null;
        _recipientId = null;
      });
      Navigator.of(context).pop();
      _message('تم إلغاء مسودة المبيعات دون تغيير المخزون.');
    } catch (error) {
      if (mounted) _message('تعذر إلغاء المسودة: ' + error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _recipientPicker() {
    if (_recipients.isEmpty) {
      return Row(children: [
        const Expanded(child: Text('لا توجد عملاء مسجلون.')),
        TextButton.icon(
          onPressed: widget.onOpenRecipients,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('إضافة عميل'),
        ),
      ]);
    }
    return DropdownButtonFormField<int>(
      initialValue: _recipientId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'جهة الاستلام',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: _recipients.map((recipient) => DropdownMenuItem<int>(
        value: recipient['id'] as int,
        child: Text((recipient['name'] ?? '').toString(),
          overflow: TextOverflow.ellipsis),
      )).toList(),
      onChanged: _issueId == null
          ? (value) => setState(() => _recipientId = value)
          : null,
    );
  }

  Widget _productGallery(double width) {
    if (_products.isEmpty) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inventory_2_outlined, size: 34),
          const SizedBox(height: 6),
          const Text('لا توجد أصناف متاحة للبيع.'),
          TextButton.icon(
            onPressed: widget.onOpenProducts,
            icon: const Icon(Icons.add),
            label: const Text('إضافة صنف'),
          ),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: Text(tr('refresh')),
          ),
        ],
      ));
    }
    final columns = width < 600 ? 4 : width < 900 ? 5 : 6;
    return GridView.builder(
      padding: const EdgeInsets.all(5),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 5,
        mainAxisSpacing: 5,
        childAspectRatio: 1.25,
      ),
      itemCount: _products.length,
      itemBuilder: (context, index) {
        final product = _products[index];
        final selected = _selectedProduct?['id'] == product['id'];
        final quantity = (product['available_quantity'] as num?)?.toDouble() ?? 0;
        return Card(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _issueId == null ? () => _selectProduct(product) : null,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 20),
                  const SizedBox(height: 3),
                  Text((product['name_ar'] ?? '').toString(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(_format(quantity) + ' ' +
                    (product['base_unit_name'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _numberButton(String label, VoidCallback action) => FilledButton.tonal(
    onPressed: _issueId == null && !_busy ? action : null,
    style: FilledButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size(30, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: Text(label,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
  );

  Widget _unitPanel() {
    final units = _selectedProduct == null
        ? <Map<String, Object?>>[]
        : (_unitsByProduct[_selectedProduct!['id'] as int] ?? []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _selectedProduct == null
              ? 'اختر الصنف'
              : 'وحدات ' + (_selectedProduct!['name_ar'] ?? '').toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: units.isEmpty
              ? const Center(child: Text('تظهر الوحدات هنا بعد اختيار الصنف'))
              : ListView(
                  children: units.map((unit) {
                    final isSelected =
                        _selectedUnit?['unit_id'] == unit['unit_id'];
                    final price =
                        (unit['sale_price'] as num?)?.toDouble() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: OutlinedButton(
                        onPressed: () => _selectUnit(unit),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 5),
                          backgroundColor: isSelected
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          side: isSelected
                              ? BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2)
                              : null,
                        ),
                        child: Column(children: [
                          Text((unit['name_ar'] ?? unit['code']).toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                          Text(_format(price),
                            style: Theme.of(context).textTheme.bodySmall),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  Widget _cashierControls() {
    return Card(
      margin: const EdgeInsets.all(5),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Column(children: [
          Row(children: [
            const Icon(Icons.calculate_outlined, size: 20),
            const SizedBox(width: 8),
            const Text('الكمية', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(_quantity,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 5),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: GridView.count(
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    childAspectRatio: 1.7,
                    children: [
                      for (final digit in
                        ['1','2','3','4','5','6','7','8','9'])
                        _numberButton(digit, () => _enterDigit(digit)),
                      _numberButton('½', _addHalf),
                      _numberButton('0', () => _enterDigit('0')),
                      _numberButton('⌫', _backspace),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: _unitPanel()),
              ],
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _issueId == null && !_busy &&
                  _selectedProduct != null && _selectedUnit != null
                  ? _addToCart
                  : null,
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('إضافة إلى السلة'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _cartSheet() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('invoiceCart'),
              style: Theme.of(context).textTheme.titleLarge),
            if (_issueNumber != null)
              Text(tr('documentNumber') + ': ' + _issueNumber!),
            const SizedBox(height: 8),
            Expanded(
              child: _cart.isEmpty
                  ? Center(child: Text(tr('cartEmpty')))
                  : ListView.separated(
                      itemCount: _cart.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final line = _cart[index];
                        return ListTile(
                          title: Text((line.product['name_ar'] ?? '').toString()),
                          subtitle: Text(
                            _format(line.quantity) + ' ' + line.unitName +
                            ' × ' + _format(line.unitPrice)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_format(line.quantity * line.unitPrice)),
                              if (_issueId == null)
                                IconButton(
                                  onPressed: () => setState(() => _cart.removeAt(index)),
                                  icon: const Icon(Icons.close),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(tr('total'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(_format(_total),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            if (_issueId == null)
              FilledButton.icon(
                onPressed: _busy || _recipientId == null || _cart.isEmpty
                    ? null
                    : _saveDraft,
                icon: const Icon(Icons.save_outlined),
                label: Text(tr('saveDraft')),
              )
            else
              FilledButton.icon(
                onPressed: _busy ? null : _approve,
                icon: const Icon(Icons.verified_outlined),
                label: Text(tr('approveDocument')),
              ),
            if (_issueId != null)
              TextButton(
                onPressed: _busy ? null : _cancelDraft,
                child: Text(tr('cancelDraft')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cartBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 1, 5, 3),
      child: SizedBox(
        height: 42,
        child: OutlinedButton.icon(
          onPressed: _cart.isEmpty
              ? null
              : () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => StatefulBuilder(
                    builder: (context, setSheetState) {
                      _refreshCartSheet = () => setSheetState(() {});
                      return SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.78,
                        child: _cartSheet(),
                      );
                    },
                  ),
                ),
          icon: const Icon(Icons.shopping_cart_outlined),
          label: Text('السلة (' + _cart.length.toString() +
            ') • ' + _format(_total)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Padding(
      padding: const EdgeInsets.all(7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('كاشير المبيعات',
            style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 5),
          _recipientPicker(),
          const SizedBox(height: 3),
          Expanded(flex: 5, child: _productGallery(width)),
          Expanded(flex: 5, child: _cashierControls()),
          _cartBar(),
        ],
      ),
    );
  }
}

class _IssueCartLine {
  const _IssueCartLine({
    required this.product,
    required this.unitId,
    required this.unitName,
    required this.quantity,
    required this.factorToBase,
    required this.unitPrice,
  });

  final Map<String, Object?> product;
  final int unitId;
  final String unitName;
  final double quantity;
  final double factorToBase;
  final double unitPrice;
}
