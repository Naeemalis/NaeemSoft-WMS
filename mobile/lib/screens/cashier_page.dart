import 'package:flutter/material.dart';

import '../data/inventory_operations.dart';
import '../data/local_database.dart';

class CashierPage extends StatefulWidget {
  const CashierPage({required this.tr, required this.receiving, super.key});
  final String Function(String) tr;
  final bool receiving;

  @override
  State<CashierPage> createState() => _CashierPageState();
}

class _CashierPageState extends State<CashierPage> {
  List<Map<String, Object?>> _products = [];
  List<Map<String, Object?>> _partners = [];
  final List<_CashierLine> _cart = [];
  int? _partnerId;
  int? _documentId;
  bool _busy = false;
  String? _documentNumber;

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
    super.dispose();
  }

  Future<void> _load() async {
    final db = await LocalDatabase.instance.database;
    final products = await LocalDatabase.instance.getProducts();
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
      if (_partnerId != null && !_partners.any((p) => p['id'] == _partnerId)) {
        _partnerId = null;
      }
    });
  }

  String _label(String key) => widget.tr(key);

  void _addProduct(Map<String, Object?> product) {
    if (_documentId != null) return;
    final line = _CashierLine(product);
    setState(() => _cart.add(line));
  }

  Future<void> _saveDraft() async {
    if (_busy || _partnerId == null || _cart.isEmpty) return;
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
            unitId: line.product['base_unit_id'] as int,
            quantity: line.quantityValue,
            factorToBase: 1,
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
            unitId: line.product['base_unit_id'] as int,
            quantity: line.quantityValue,
            factorToBase: 1,
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

  void _cancelDraft() async {
    if (_documentId == null || _busy) return;
    final db = await LocalDatabase.instance.database;
    final table = widget.receiving ? 'receipts' : 'issues';
    await db.update(table, {'status': 'cancelled'}, where: 'id = ?', whereArgs: [_documentId]);
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
          Text(_label(widget.receiving ? 'addSupplierFirst' : 'addRecipientFirst')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
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
  _CashierLine(this.product)
      : quantity = TextEditingController(text: '1'),
        price = TextEditingController(text: '0');
  final Map<String, Object?> product;
  final TextEditingController quantity;
  final TextEditingController price;
  double get quantityValue => double.tryParse(quantity.text) ?? 0;
  double get priceValue => double.tryParse(price.text) ?? 0;
}
