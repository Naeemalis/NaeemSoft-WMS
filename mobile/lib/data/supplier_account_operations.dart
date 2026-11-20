import 'package:sqflite/sqflite.dart';

class SupplierAccountOperations {
  SupplierAccountOperations(this.db);
  final Database db;

  Future<int> recordPayment({
    required String number,
    required int supplierId,
    required DateTime date,
    required double amount,
    String method = 'cash',
    String? reference,
    String? notes,
    int? createdBy,
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError('Payment amount must be greater than zero.');
    }
    return db.transaction((txn) async {
      final id = await txn.insert('payments', {
        'payment_number': number,
        'supplier_id': supplierId,
        'payment_date': _date(date),
        'amount': amount,
        'payment_method': method,
        'reference_number': reference,
        'notes': notes,
        'created_by': createdBy,
      });
      await txn.insert('supplier_transactions', {
        'supplier_id': supplierId,
        'transaction_type': 'payment',
        'document_type': 'payment',
        'document_id': id,
        'debit': amount,
        'credit': 0,
        'transaction_date': _date(date),
        'notes': notes ?? 'Supplier payment $number',
      });
      await txn.insert('audit_logs', {
        'user_id': createdBy,
        'action': 'create',
        'entity_type': 'supplier_payment',
        'entity_id': id,
        'details': 'Payment $number amount $amount',
      });
      return id;
    });
  }

  Future<void> setOpeningBalance({
    required int supplierId,
    required double amount,
    required bool supplierIsCreditor,
    required DateTime date,
    String? notes,
  }) async {
    if (!amount.isFinite || amount < 0) throw ArgumentError('Opening balance cannot be negative.');
    if (amount == 0) return;
    await db.transaction((txn) async {
      await txn.insert('supplier_transactions', {
        'supplier_id': supplierId,
        'transaction_type': 'opening_balance',
        'document_type': 'opening_balance',
        'document_id': supplierId,
        'debit': supplierIsCreditor ? 0 : amount,
        'credit': supplierIsCreditor ? amount : 0,
        'transaction_date': _date(date),
        'notes': notes ?? 'Supplier opening balance',
      });
      await txn.insert('audit_logs', {
        'action': 'create', 'entity_type': 'supplier_opening_balance',
        'entity_id': supplierId, 'details': 'Opening balance $amount',
      });
    });
  }

  Future<int> createSupplierReturn({
    required String number,
    required int supplierId,
    required DateTime date,
    required List<SupplierReturnLineInput> lines,
    String? reason,
    String? notes,
  }) async {
    if (lines.isEmpty) throw ArgumentError('A supplier return needs at least one line.');
    return db.transaction((txn) async {
      var total = 0.0;
      final validated = <Map<String,Object?>>[];
      for (final line in lines) {
        if (!line.quantity.isFinite || line.quantity <= 0 ||
            !line.factorToBase.isFinite || line.factorToBase <= 0) {
          throw ArgumentError('Return quantity and conversion factor must be positive.');
        }
        final source = await txn.rawQuery('''
          SELECT ri.product_id, ri.unit_id, r.supplier_id, r.status AS receipt_status,
                 b.product_id AS batch_product_id, b.receipt_item_id AS batch_receipt_item_id,
                 b.unit_cost_base, b.remaining_quantity_base
          FROM receipt_items ri
          JOIN receipts r ON r.id = ri.receipt_id
          JOIN inventory_batches b ON b.id = ?
          WHERE ri.id = ? AND b.receipt_item_id = ri.id
        ''', [line.batchId, line.receiptItemId]);
        if (source.isEmpty || source.first['supplier_id'] != supplierId ||
            source.first['receipt_status'] != 'approved' ||
            source.first['product_id'] != line.productId ||
            source.first['batch_product_id'] != line.productId ||
            source.first['batch_receipt_item_id'] != line.receiptItemId) {
          throw StateError('Return line must reference the supplier original approved receipt and its batch.');
        }
        final quantityBase = line.quantity * line.factorToBase;
        final remaining = (source.first['remaining_quantity_base'] as num).toDouble();
        if (quantityBase > remaining + 0.0000001) {
          throw StateError('Return quantity exceeds the remaining quantity in the original batch.');
        }
        final cost = (source.first['unit_cost_base'] as num).toDouble();
        final lineTotal = quantityBase * cost;
        total += lineTotal;
        validated.add({
          'receipt_item_id': line.receiptItemId, 'batch_id': line.batchId,
          'product_id': line.productId, 'unit_id': line.unitId,
          'quantity': line.quantity, 'factor_to_base': line.factorToBase,
          'quantity_base': quantityBase, 'unit_cost_base': cost,
          'line_total': lineTotal,
        });
      }
      final returnId = await txn.insert('supplier_returns', {
        'return_number': number, 'supplier_id': supplierId,
        'return_date': _date(date), 'status': 'draft',
        'total_amount': total, 'reason': reason, 'notes': notes,
      });
      for (final line in validated) {
        await txn.insert('supplier_return_items', {
          'supplier_return_id': returnId, ...line,
        });
      }
      return returnId;
    });
  }

  Future<void> approveSupplierReturn(int returnId, {int? approvedBy}) async {
    await db.transaction((txn) async {
      final headers = await txn.query('supplier_returns',
        where: 'id = ?', whereArgs: [returnId], limit: 1);
      if (headers.isEmpty) throw StateError('Supplier return not found.');
      final header = headers.first;
      if (header['status'] != 'draft' && header['status'] != 'pending_approval') {
        throw StateError('Only draft or pending supplier returns can be approved.');
      }
      final lines = await txn.query('supplier_return_items',
        where: 'supplier_return_id = ?', whereArgs: [returnId]);
      if (lines.isEmpty) throw StateError('Cannot approve an empty supplier return.');

      // Validate aggregate quantity per batch before any mutation.
      final batchTotals = <int, double>{};
      for (final line in lines) {
        final batchId = line['batch_id'] as int;
        batchTotals[batchId] = (batchTotals[batchId] ?? 0) +
            (line['quantity_base'] as num).toDouble();
      }
      for (final entry in batchTotals.entries) {
        final batches = await txn.query('inventory_batches',
          where: 'id = ?', whereArgs: [entry.key], limit: 1);
        if (batches.isEmpty ||
            (batches.first['remaining_quantity_base'] as num).toDouble() + 0.0000001 < entry.value) {
          throw StateError('Insufficient remaining quantity in original receipt batch.');
        }
      }

      // Trigger validates original receipt ownership and lifetime return cap.
      // All checks happen before stock is changed; transaction rollback is atomic.
      await txn.update('supplier_returns', {
        'status': 'approved', 'approved_by': approvedBy,
        'approved_at': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [returnId]);

      for (final entry in batchTotals.entries) {
        final batches = await txn.query('inventory_batches',
          where: 'id = ?', whereArgs: [entry.key], limit: 1);
        final available = (batches.first['remaining_quantity_base'] as num).toDouble();
        final left = available - entry.value;
        await txn.update('inventory_batches', {
          'remaining_quantity_base': left,
          if (left <= 0.0000001) 'status': 'depleted',
        }, where: 'id = ?', whereArgs: [entry.key]);
      }
      for (final line in lines) {
        await txn.insert('stock_movements', {
          'product_id': line['product_id'], 'batch_id': line['batch_id'],
          'movement_type': 'supplier_return', 'direction': 'OUT',
          'quantity_base': line['quantity_base'], 'source_type': 'supplier_return',
          'source_id': returnId, 'occurred_at': header['return_date'],
          'created_by': approvedBy,
        });
      }
      await txn.insert('supplier_transactions', {
        'supplier_id': header['supplier_id'],
        'transaction_type': 'supplier_return',
        'document_type': 'supplier_return',
        'document_id': returnId,
        'debit': header['total_amount'], 'credit': 0,
        'transaction_date': header['return_date'],
        'notes': 'Approved supplier return ${header['return_number']}',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.insert('audit_logs', {
        'user_id': approvedBy, 'action': 'approve',
        'entity_type': 'supplier_return', 'entity_id': returnId,
        'details': 'Supplier return approved and original batches reduced.',
      });
    });
  }

  Future<List<Map<String, Object?>>> getStatement({
    required int supplierId,
    DateTime? from,
    DateTime? to,
  }) async {
    final where = <String>['supplier_id = ?'];
    final args = <Object?>[supplierId];
    if (from != null) {
      where.add("date(transaction_date) >= date(?)");
      args.add(_date(from));
    }
    if (to != null) {
      where.add("date(transaction_date) <= date(?)");
      args.add(_date(to));
    }
    return db.query('supplier_transactions',
      where: where.join(' AND '), whereArgs: args,
      orderBy: 'transaction_date ASC, id ASC');
  }

  Future<Map<String, double>> getBalances({
    required int supplierId,
    DateTime? from,
    DateTime? to,
  }) async {
    final opening = from == null ? 0.0 : _sum(
      await db.rawQuery('''
        SELECT COALESCE(SUM(credit - debit), 0) AS balance
        FROM supplier_transactions
        WHERE supplier_id = ? AND date(transaction_date) < date(?)
      ''', [supplierId, _date(from)]),
    );
    final clauses = <String>['supplier_id = ?'];
    final args = <Object?>[supplierId];
    if (from != null) { clauses.add('date(transaction_date) >= date(?)'); args.add(_date(from)); }
    if (to != null) { clauses.add('date(transaction_date) <= date(?)'); args.add(_date(to)); }
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(debit),0) AS debit,
             COALESCE(SUM(credit),0) AS credit
      FROM supplier_transactions WHERE ${clauses.join(' AND ')}
    ''', args);
    final debit = _sumColumn(rows, 'debit');
    final credit = _sumColumn(rows, 'credit');
    return {'opening': opening, 'debit': debit, 'credit': credit,
      'closing': opening + credit - debit};
  }

  double _sum(List<Map<String, Object?>> rows) =>
      rows.isEmpty ? 0 : ((rows.first['balance'] as num?)?.toDouble() ?? 0);
  double _sumColumn(List<Map<String, Object?>> rows, String key) =>
      rows.isEmpty ? 0 : ((rows.first[key] as num?)?.toDouble() ?? 0);
  String _date(DateTime d) => d.toIso8601String().substring(0, 10);
}

class SupplierReturnLineInput {
  const SupplierReturnLineInput({
    required this.receiptItemId, required this.batchId,
    required this.productId, required this.unitId,
    required this.quantity, required this.factorToBase,
  });
  final int receiptItemId;
  final int batchId;
  final int productId;
  final int unitId;
  final double quantity;
  final double factorToBase;
}
