import 'package:flutter/material.dart';

import '../data/inventory_operations.dart';
import '../data/local_database.dart';

class CashierPage extends StatefulWidget {
  const CashierPage({required this.tr, required this.receiving, this.onOpenPartners, this.onOpenProducts, super.key});
  final String Function(String) tr;
  final bool receiving;
  final VoidCallback? onOpenPartners;
  final VoidCallback? onOpenProducts;

  @override
  State<CashierPage> createState() => _CashierPageState();
}

class _CashierPageState extends State<CashierPage> {
  List<Map<String, Object?>> _products = [];
  List<Map<String, Object?>> _partners = [];
  final Map<int, List<Map<String, Object?>>> _unitOptions = {};
  final List<_CashierLine> _cart = [];
  int? _partnerId;
  int? _documentId;
  bool _busy = false;
  String? _documentNumber;
  final TextEditingController _issueQuantity = TextEditingController(text: '0');
  Map<String, Object?>? _selectedIssueProduct;
  Map<String, Object?>? _selectedIssueUnit;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final line in _cart) {
      line.quantity.dispose();
      line.price.dispose();
    }
    _issueQuantity.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = await LocalDatabase.instance.database;
    final products = await LocalDatabase.instance.getProducts();
    final unitRows = await db.rawQuery('''
      SELECT pu.product_id, pu.unit_id, pu.factor_to_base, pu.sale_price, u.name_ar, u.code
      FROM product_units pu JOIN units u ON u.id = pu.unit_id
      WHERE pu.${widget.receiving ? 'can_receive' : 'can_issue'} = 1
      ORDER BY pu.id
    ''');
    final partners = await db.query(
      widget.receiving ? 'suppliers' : 'recipients',
      where: 'is_active = 1',
      orderBy: 'name COLLATE NOCASE',
    );
    if (!mounted) return;
    setState(() {
      _products = widget.receiving
          ? products
          : products.where((p) => ((p['available_quantity'] as num?) ?? 0) > 0).toList();
      _partners = partners;
      _unitOptions.clear();
      for (final row in unitRows) {
        final productId = row['product_id'] as int;
        _unitOptions.putIfAbsent(productId, () => []).add(row);
      }
      if (_partnerId != null && !_partners.any((p) => p['id'] == _partnerId)) {
        _partnerId = null;
      }
    });
  }

  String _label(String key) => widget.tr(key);

  void _addProduct(Map<String, Object?> product) {
    if (_documentId != null || _busy) return;
    final options = _unitOptions[product['id'] as int] ?? [];
    final baseUnitId = product['base_unit_id'] as int;
    final baseOption = options.where((u) => u['unit_id'] == baseUnitId).toList();
    if (options.isEmpty || baseOption.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد وحدات مفعّلة لهذه العملية لهذا الصنف.')),
      );
      return;
    }
    final line = _CashierLine(product, options);
    setState(() {
      line.factorToBase = (baseOption.first['factor_to_base'] as num).toDouble();
      _cart.add(line);
    });
  }

  void _selectIssueProduct(Map<String, Object?> product) {
    if (widget.receiving || _documentId != null || _busy) return;
    final options = _unitOptions[product['id'] as int] ?? [];
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد وحدات مفعّلة للصرف لهذا الصنف.')),
      );
      return;
    }
    setState(() {
      _selectedIssueProduct = product;
      _selectedIssueUnit = null;
    });
  }

  void _selectIssueUnit(Map<String, Object?> unit) {
    if (_documentId != null || _busy) return;
    final price = (unit['sale_price'] as num?)?.toDouble() ?? 0;
    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سعر بيع هذه الوحدة غير معرّف. حدّث بيانات الصنف أولاً.')),
      );
      return;
    }
    setState(() => _selectedIssueUnit = unit);
  }

  void _appendIssueDigit(String digit) {
    if (_documentId != null || _busy) return;
    setState(() {
      _issueQuantity.text = _issueQuantity.text == '0'
          ? digit
          : _issueQuantity.text + digit;
    });
  }

  void _deleteIssueDigit() {
    if (_documentId != null || _busy) return;
    setState(() {
      final value = _issueQuantity.text;
      _issueQuantity.text = value.length <= 1 ? '0' : value.substring(0, value.length - 1);
    });
  }

  void _addHalfIssueQuantity() {
    if (_documentId != null || _busy) return;
    final current = double.tryParse(_issueQuantity.text) ?? 0;
    setState(() => _issueQuantity.text = _formatNumber(current + 0.5));
  }

  String _formatNumber(double value) =>
      value.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+    if (_busy) return;
    if (_partnerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى اختيار الجهة أولاً.')));
      return;
    }
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف صنفاً واحداً على الأقل.')));
      return;
    }
    for (final line in _cart) {
      if (!line.quantityValue.isFinite || line.quantityValue <= 0 ||
          !line.priceValue.isFinite || line.priceValue < 0 ||
          (!widget.receiving && line.priceValue <= 0) ||
          !line.factorToBase.isFinite || line.factorToBase <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تحقق من الكمية والسعر والوحدة للصنف: ${line.product['name_ar']}')),
        );
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final db = await LocalDatabase.instance.database;
      final operations = InventoryOperations(db);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      if (widget.receiving) {
        _documentNumber = 'R-$stamp';
        _documentId = await operations.createReceipt(
          number: _documentNumber!,
          supplierId: _partnerId!,
          receiptDate: DateTime.now(),
          lines: _cart.map((line) => ReceiptLineInput(
            productId: line.product['id'] as int,
            unitId: line.unitId,
            quantity: line.quantityValue,
            factorToBase: line.factorToBase,
            unitCost: line.priceValue,
          )).toList(),
        );
      } else {
        _documentNumber = 'I-$stamp';
        _documentId = await operations.createIssue(
          number: _documentNumber!,
          recipientId: _partnerId!,
          issueDate: DateTime.now(),
          lines: _cart.map((line) => IssueLineInput(
            productId: line.product['id'] as int,
            unitId: line.unitId,
            quantity: line.quantityValue,
            factorToBase: line.factorToBase,
            unitPrice: line.priceValue,
          )).toList(),
        );
      }
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_label('draftSaved')} • $_documentNumber')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final id = _documentId;
    if (id == null || _busy) return;
    setState(() => _busy = true);
    try {
      final db = await LocalDatabase.instance.database;
      final operations = InventoryOperations(db);
      if (widget.receiving) {
        await operations.approveReceipt(id);
      } else {
        await operations.approveIssue(id);
      }
      if (!mounted) return;
      for (final line in _cart) {
        line.quantity.dispose();
        line.price.dispose();
      }
      setState(() {
        _cart.clear();
        _documentId = null;
        _documentNumber = null;
        _partnerId = null;
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_label('documentApproved'))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelDraft() async {
    final id = _documentId;
    if (id == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إلغاء المستند'),
        content: const Text('هل تريد إلغاء المسودة؟ لن يتم تعديل المخزون.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_label('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_label('cancelDraft'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final db = await LocalDatabase.instance.database;
      final table = widget.receiving ? 'receipts' : 'issues';
      await db.transaction((txn) async {
        final changed = await txn.update(
          table, {'status': 'cancelled'},
          where: "id = ? AND status IN ('draft','pending_approval')",
          whereArgs: [id],
        );
        if (changed != 1) throw StateError('لا يمكن إلغاء هذا المستند لأنه لم يعد مسودة.');
        await txn.insert('audit_logs', {
          'action': 'cancel',
          'entity_type': widget.receiving ? 'receipt' : 'issue',
          'entity_id': id,
          'details': 'Draft document cancelled from cashier.',
        });
      });
      if (!mounted) return;
      for (final line in _cart) {
        line.quantity.dispose();
        line.price.dispose();
      }
      setState(() {
        _cart.clear();
        _documentId = null;
        _documentNumber = null;
        _partnerId = null;
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إلغاء المسودة بنجاح.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إلغاء المسودة: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _partnerPicker() {
    return DropdownButtonFormField<int>(
      initialValue: _partnerId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: _label(widget.receiving ? 'selectSupplier' : 'selectRecipient'),
        border: const OutlineInputBorder(),
      ),
      items: _partners.map((partner) => DropdownMenuItem<int>(
        value: partner['id'] as int,
        child: Text((partner['name'] ?? '').toString(), overflow: TextOverflow.ellipsis),
      )).toList(),
      onChanged: _documentId == null ? (value) => setState(() => _partnerId = value) : null,
    );
  }

  Widget _productGallery(double width) {
    if (_products.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.inventory_2_outlined, size: 44),
          const SizedBox(height: 10),
          Text(_label('noProducts')),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => widget.onOpenProducts?.call(),
            icon: const Icon(Icons.add),
            label: Text(_label('addProduct')),
          ),
          TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(_label('refresh'))),
        ]),
      ));
    }
    final columns = width < 600 ? 4 : width < 900 ? 5 : 6;
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.18,
      ),
      itemCount: _products.length,
      itemBuilder: (context, index) {
        final product = _products[index];
        final quantity = (product['available_quantity'] as num?)?.toDouble() ?? 0;
        final isSelectedIssueProduct = !widget.receiving && _selectedIssueProduct?['id'] == product['id'];
        return Card(
          color: isSelectedIssueProduct ? Theme.of(context).colorScheme.primaryContainer : null,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _documentId == null ? () {
              if (widget.receiving) {
                _addProduct(product);
              } else {
                _selectIssueProduct(product);
              }
            } : null,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 25),
                  const SizedBox(height: 6),
                  Text((product['name_ar'] ?? '').toString(),
                    textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('${quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 2)} ${product['base_unit_name'] ?? ''}',
                    style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _cartPanel() {
    final total = _cart.fold<double>(0, (sum, line) => sum + line.quantityValue * line.priceValue);
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_label('invoiceCart'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_documentNumber != null)
              Text('${_label('documentNumber')}: $_documentNumber',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: _cart.isEmpty
                  ? Center(child: Text(_label('cartEmpty')))
                  : ListView.separated(
                      itemCount: _cart.length,
                      separatorBuilder: (_, __) => const Divider(height: 12),
                      itemBuilder: (context, index) {
                        final line = _cart[index];
                        return Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text((line.product['name_ar'] ?? '').toString(),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<int>(
                                value: line.unitId,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'الوحدة'),
                                items: line.units.map((u) => DropdownMenuItem<int>(
                                  value: u['unit_id'] as int,
                                  child: Text((u['name_ar'] ?? u['code']).toString(),
                                    overflow: TextOverflow.ellipsis),
                                )).toList(),
                                onChanged: _documentId == null && widget.receiving ? (value) {
                                  if (value == null) return;
                                  final selected = line.units.firstWhere((u) => u['unit_id'] == value);
                                  setState(() {
                                    line.unitId = value;
                                    line.factorToBase = (selected['factor_to_base'] as num).toDouble();
                                  });
                                } : null,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: line.quantity,
                                enabled: _documentId == null && widget.receiving,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(labelText: _label('quantity')),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: line.price,
                                enabled: _documentId == null && widget.receiving,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(labelText: _label(widget.receiving ? 'unitCost' : 'unitPrice')),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            if (_documentId == null)
                              IconButton(
                                tooltip: _label('remove'),
                                onPressed: () {
                                  setState(() => _cart.removeAt(index));
                                  line.quantity.dispose();
                                  line.price.dispose();
                                },
                                icon: const Icon(Icons.close),
                              ),
                          ],
                        );
                      },
                    ),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_label('total'), style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(total.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            if (_documentId == null)
              FilledButton.icon(
                onPressed: _busy || _partnerId == null || _cart.isEmpty ? null : _saveDraft,
                icon: const Icon(Icons.save_outlined),
                label: Text(_label('saveDraft')),
              )
            else ...[
              FilledButton.icon(
                onPressed: _busy ? null : _approve,
                icon: const Icon(Icons.verified_outlined),
                label: Text(_label('approveDocument')),
              ),
              TextButton(
                onPressed: _busy ? null : _cancelDraft,
                child: Text(_label('cancelDraft')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (_partners.isEmpty && !_busy) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(widget.receiving ? Icons.local_shipping_outlined : Icons.people_alt_outlined, size: 44),
          const SizedBox(height: 12),
          Text(_label(widget.receiving ? 'addSupplierFirst' : 'addRecipientFirst')),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => widget.onOpenPartners?.call(),
            icon: const Icon(Icons.person_add_alt_1),
            label: Text(_label('addPartner')),
          ),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: Text(_label('refresh')),
          ),
        ]),
      ));
    }
    if (!widget.receiving) return _buildIssueCashier(width);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_label(widget.receiving ? 'receiving' : 'issuing'),
            style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          _partnerPicker(),
          const SizedBox(height: 8),
          Expanded(
            child: width >= 850
                ? Row(children: [
                    Expanded(flex: 6, child: _productGallery(width * .62)),
                    Expanded(flex: 5, child: _cartPanel()),
                  ])
                : Column(children: [
                    Expanded(flex: 5, child: _productGallery(width)),
                    Expanded(flex: 4, child: _cartPanel()),
                  ]),
          ),
        ],
      ),
    );
  }
}

class _CashierLine {
  _CashierLine(this.product, this.units)
      : quantity = TextEditingController(text: '1'),
        price = TextEditingController(text: '0'),
        unitId = product['base_unit_id'] as int,
        factorToBase = 1;
  final Map<String, Object?> product;
  final List<Map<String, Object?>> units;
  final TextEditingController quantity;
  final TextEditingController price;
  int unitId;
  double factorToBase;
  double get quantityValue => double.tryParse(quantity.text) ?? 0;
  double get priceValue => double.tryParse(price.text) ?? 0;
}
), '');

  void _addSelectedIssueToCart() {
    final product = _selectedIssueProduct;
    final unit = _selectedIssueUnit;
    final quantity = double.tryParse(_issueQuantity.text.trim());
    if (product == null || unit == null || quantity == null ||
        !quantity.isFinite || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل الكمية واختر الصنف والوحدة أولاً.')),
      );
      return;
    }
    final price = (unit['sale_price'] as num?)?.toDouble() ?? 0;
    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سعر بيع الوحدة غير معرّف.')),
      );
      return;
    }
    final options = _unitOptions[product['id'] as int] ?? [];
    final line = _CashierLine(product, options)
      ..unitId = unit['unit_id'] as int
      ..factorToBase = (unit['factor_to_base'] as num).toDouble()
      ..quantity.text = _formatNumber(quantity)
      ..price.text = _formatNumber(price);
    setState(() {
      _cart.add(line);
      _selectedIssueProduct = null;
      _selectedIssueUnit = null;
    });
  }

  Widget _issueControls() {
    final units = _selectedIssueProduct == null
        ? <Map<String, Object?>>[]
        : (_unitOptions[_selectedIssueProduct!['id'] as int] ?? []);
    return Card(
      margin: const EdgeInsets.all(6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            TextField(
              controller: _issueQuantity,
              readOnly: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                labelText: 'الكمية',
                prefixIcon: Icon(Icons.numbers),
                isDense: true,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: GridView.count(
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 3,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      childAspectRatio: 1.65,
                      children: [
                        for (final digit in ['1','2','3','4','5','6','7','8','9'])
                          _keyButton(digit, () => _appendIssueDigit(digit)),
                        _keyButton('½', _addHalfIssueQuantity),
                        _keyButton('0', () => _appendIssueDigit('0')),
                        _keyButton('⌫', _deleteIssueDigit),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _selectedIssueProduct == null
                              ? 'اختر الصنف'
                              : 'وحدات ' + (_selectedIssueProduct!['name_ar'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 5),
                        Expanded(
                          child: units.isEmpty
                              ? const Center(child: Text('لا توجد وحدات'))
                              : ListView(
                                  children: units.map((unit) {
                                    final selected = _selectedIssueUnit?['unit_id'] == unit['unit_id'];
                                    final price = (unit['sale_price'] as num?)?.toDouble() ?? 0;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 5),
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
                                          backgroundColor: selected
                                              ? Theme.of(context).colorScheme.primaryContainer
                                              : null,
                                          side: selected ? BorderSide(
                                            color: Theme.of(context).colorScheme.primary, width: 2,
                                          ) : null,
                                        ),
                                        onPressed: () => _selectIssueUnit(unit),
                                        child: Column(children: [
                                          Text((unit['name_ar'] ?? unit['code']).toString(),
                                            maxLines: 1, overflow: TextOverflow.ellipsis),
                                          Text(_formatNumber(price),
                                            style: Theme.of(context).textTheme.bodySmall),
                                        ]),
                                      ),
                                    );
                                  }).toList(),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _selectedIssueProduct != null && _selectedIssueUnit != null &&
                    !_busy && _documentId == null ? _addSelectedIssueToCart : null,
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('إضافة إلى السلة'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _keyButton(String label, VoidCallback onPressed) => FilledButton.tonal(
    onPressed: _documentId == null && !_busy ? onPressed : null,
    style: FilledButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: const Size(32, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
  );

  Widget _issueCartBar() {
    final total = _cart.fold<double>(0, (sum, line) => sum + line.quantityValue * line.priceValue);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 4),
      child: SizedBox(
        height: 44,
        child: OutlinedButton.icon(
          onPressed: _cart.isEmpty ? null : () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (context) => SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.78,
              child: _cartPanel(),
            ),
          ),
          icon: const Icon(Icons.shopping_cart_outlined),
          label: Text('السلة (' + _cart.length.toString() + ')  •  ' + _formatNumber(total)),
        ),
      ),
    );
  }

  Widget _buildIssueCashier(double width) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_label('issuing'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          _partnerPicker(),
          const SizedBox(height: 4),
          Expanded(flex: 5, child: _productGallery(width)),
          Expanded(flex: 5, child: _issueControls()),
          _issueCartBar(),
        ],
      ),
    );
  }

  Future<void> _saveDraft() async {
    if (_busy) return;
    if (_partnerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى اختيار الجهة أولاً.')));
      return;
    }
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف صنفاً واحداً على الأقل.')));
      return;
    }
    for (final line in _cart) {
      if (!line.quantityValue.isFinite || line.quantityValue <= 0 ||
          !line.priceValue.isFinite || line.priceValue < 0 ||
          (!widget.receiving && line.priceValue <= 0) ||
          !line.factorToBase.isFinite || line.factorToBase <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تحقق من الكمية والسعر والوحدة للصنف: ${line.product['name_ar']}')),
        );
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final db = await LocalDatabase.instance.database;
      final operations = InventoryOperations(db);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      if (widget.receiving) {
        _documentNumber = 'R-$stamp';
        _documentId = await operations.createReceipt(
          number: _documentNumber!,
          supplierId: _partnerId!,
          receiptDate: DateTime.now(),
          lines: _cart.map((line) => ReceiptLineInput(
            productId: line.product['id'] as int,
            unitId: line.unitId,
            quantity: line.quantityValue,
            factorToBase: line.factorToBase,
            unitCost: line.priceValue,
          )).toList(),
        );
      } else {
        _documentNumber = 'I-$stamp';
        _documentId = await operations.createIssue(
          number: _documentNumber!,
          recipientId: _partnerId!,
          issueDate: DateTime.now(),
          lines: _cart.map((line) => IssueLineInput(
            productId: line.product['id'] as int,
            unitId: line.unitId,
            quantity: line.quantityValue,
            factorToBase: line.factorToBase,
            unitPrice: line.priceValue,
          )).toList(),
        );
      }
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_label('draftSaved')} • $_documentNumber')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final id = _documentId;
    if (id == null || _busy) return;
    setState(() => _busy = true);
    try {
      final db = await LocalDatabase.instance.database;
      final operations = InventoryOperations(db);
      if (widget.receiving) {
        await operations.approveReceipt(id);
      } else {
        await operations.approveIssue(id);
      }
      if (!mounted) return;
      for (final line in _cart) {
        line.quantity.dispose();
        line.price.dispose();
      }
      setState(() {
        _cart.clear();
        _documentId = null;
        _documentNumber = null;
        _partnerId = null;
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_label('documentApproved'))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelDraft() async {
    final id = _documentId;
    if (id == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إلغاء المستند'),
        content: const Text('هل تريد إلغاء المسودة؟ لن يتم تعديل المخزون.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_label('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_label('cancelDraft'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final db = await LocalDatabase.instance.database;
      final table = widget.receiving ? 'receipts' : 'issues';
      await db.transaction((txn) async {
        final changed = await txn.update(
          table, {'status': 'cancelled'},
          where: "id = ? AND status IN ('draft','pending_approval')",
          whereArgs: [id],
        );
        if (changed != 1) throw StateError('لا يمكن إلغاء هذا المستند لأنه لم يعد مسودة.');
        await txn.insert('audit_logs', {
          'action': 'cancel',
          'entity_type': widget.receiving ? 'receipt' : 'issue',
          'entity_id': id,
          'details': 'Draft document cancelled from cashier.',
        });
      });
      if (!mounted) return;
      for (final line in _cart) {
        line.quantity.dispose();
        line.price.dispose();
      }
      setState(() {
        _cart.clear();
        _documentId = null;
        _documentNumber = null;
        _partnerId = null;
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إلغاء المسودة بنجاح.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إلغاء المسودة: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _partnerPicker() {
    return DropdownButtonFormField<int>(
      initialValue: _partnerId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: _label(widget.receiving ? 'selectSupplier' : 'selectRecipient'),
        border: const OutlineInputBorder(),
      ),
      items: _partners.map((partner) => DropdownMenuItem<int>(
        value: partner['id'] as int,
        child: Text((partner['name'] ?? '').toString(), overflow: TextOverflow.ellipsis),
      )).toList(),
      onChanged: _documentId == null ? (value) => setState(() => _partnerId = value) : null,
    );
  }

  Widget _productGallery(double width) {
    if (_products.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.inventory_2_outlined, size: 44),
          const SizedBox(height: 10),
          Text(_label('noProducts')),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => widget.onOpenProducts?.call(),
            icon: const Icon(Icons.add),
            label: Text(_label('addProduct')),
          ),
          TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(_label('refresh'))),
        ]),
      ));
    }
    final columns = width < 380 ? 2 : width < 600 ? 3 : width < 900 ? 4 : 6;
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.18,
      ),
      itemCount: _products.length,
      itemBuilder: (context, index) {
        final product = _products[index];
        final quantity = (product['available_quantity'] as num?)?.toDouble() ?? 0;
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _documentId == null ? () => _addProduct(product) : null,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 25),
                  const SizedBox(height: 6),
                  Text((product['name_ar'] ?? '').toString(),
                    textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('${quantity.toStringAsFixed(quantity % 1 == 0 ? 0 : 2)} ${product['base_unit_name'] ?? ''}',
                    style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _cartPanel() {
    final total = _cart.fold<double>(0, (sum, line) => sum + line.quantityValue * line.priceValue);
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_label('invoiceCart'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_documentNumber != null)
              Text('${_label('documentNumber')}: $_documentNumber',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: _cart.isEmpty
                  ? Center(child: Text(_label('cartEmpty')))
                  : ListView.separated(
                      itemCount: _cart.length,
                      separatorBuilder: (_, __) => const Divider(height: 12),
                      itemBuilder: (context, index) {
                        final line = _cart[index];
                        return Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text((line.product['name_ar'] ?? '').toString(),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<int>(
                                value: line.unitId,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'الوحدة'),
                                items: line.units.map((u) => DropdownMenuItem<int>(
                                  value: u['unit_id'] as int,
                                  child: Text((u['name_ar'] ?? u['code']).toString(),
                                    overflow: TextOverflow.ellipsis),
                                )).toList(),
                                onChanged: _documentId == null ? (value) {
                                  if (value == null) return;
                                  final selected = line.units.firstWhere((u) => u['unit_id'] == value);
                                  setState(() {
                                    line.unitId = value;
                                    line.factorToBase = (selected['factor_to_base'] as num).toDouble();
                                  });
                                } : null,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: line.quantity,
                                enabled: _documentId == null,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(labelText: _label('quantity')),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: line.price,
                                enabled: _documentId == null,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(labelText: _label(widget.receiving ? 'unitCost' : 'unitPrice')),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            if (_documentId == null)
                              IconButton(
                                tooltip: _label('remove'),
                                onPressed: () {
                                  setState(() => _cart.removeAt(index));
                                  line.quantity.dispose();
                                  line.price.dispose();
                                },
                                icon: const Icon(Icons.close),
                              ),
                          ],
                        );
                      },
                    ),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_label('total'), style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(total.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            if (_documentId == null)
              FilledButton.icon(
                onPressed: _busy || _partnerId == null || _cart.isEmpty ? null : _saveDraft,
                icon: const Icon(Icons.save_outlined),
                label: Text(_label('saveDraft')),
              )
            else ...[
              FilledButton.icon(
                onPressed: _busy ? null : _approve,
                icon: const Icon(Icons.verified_outlined),
                label: Text(_label('approveDocument')),
              ),
              TextButton(
                onPressed: _busy ? null : _cancelDraft,
                child: Text(_label('cancelDraft')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (_partners.isEmpty && !_busy) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(widget.receiving ? Icons.local_shipping_outlined : Icons.people_alt_outlined, size: 44),
          const SizedBox(height: 12),
          Text(_label(widget.receiving ? 'addSupplierFirst' : 'addRecipientFirst')),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => widget.onOpenPartners?.call(),
            icon: const Icon(Icons.person_add_alt_1),
            label: Text(_label('addPartner')),
          ),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: Text(_label('refresh')),
          ),
        ]),
      ));
    }
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_label(widget.receiving ? 'receiving' : 'issuing'),
            style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          _partnerPicker(),
          const SizedBox(height: 8),
          Expanded(
            child: width >= 850
                ? Row(children: [
                    Expanded(flex: 6, child: _productGallery(width * .62)),
                    Expanded(flex: 5, child: _cartPanel()),
                  ])
                : Column(children: [
                    Expanded(flex: 5, child: _productGallery(width)),
                    Expanded(flex: 4, child: _cartPanel()),
                  ]),
          ),
        ],
      ),
    );
  }
}

class _CashierLine {
  _CashierLine(this.product, this.units)
      : quantity = TextEditingController(text: '1'),
        price = TextEditingController(text: '0'),
        unitId = product['base_unit_id'] as int,
        factorToBase = 1;
  final Map<String, Object?> product;
  final List<Map<String, Object?>> units;
  final TextEditingController quantity;
  final TextEditingController price;
  int unitId;
  double factorToBase;
  double get quantityValue => double.tryParse(quantity.text) ?? 0;
  double get priceValue => double.tryParse(price.text) ?? 0;
}
