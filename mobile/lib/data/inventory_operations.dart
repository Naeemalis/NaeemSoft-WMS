import 'package:sqflite/sqflite.dart';

/// Atomic receiving and issuing workflows for the single local warehouse.
/// Draft documents never change stock. Approval posts batches and movements.
class InventoryOperations {
  InventoryOperations(this.db);

  final Database db;

  Future<int> createReceipt({
    required String number,
    required int supplierId,
    required DateTime receiptDate,
    required List<ReceiptLineInput> lines,
    int? requestId,
    int? createdBy,
    String? notes,
  }) async {
    if (lines.isEmpty) throw ArgumentError('A receipt must contain at least one line.');
    _validateLines(lines.map((line) => (line.quantity, line.factorToBase, line.unitCost)));
    return db.transaction((txn) async {
      final total = lines.fold<double>(0, (sum, line) => sum + line.quantity * line.unitCost);
      final receiptId = await txn.insert('receipts', {
        'receipt_number': number,
        'supplier_id': supplierId,
        'request_id': requestId,
        'receipt_date': _date(receiptDate),
        'status': 'draft',
        'total_cost': total,
        'notes': notes,
        'created_by': createdBy,
      });
      for (final line in lines) {
        await txn.insert('receipt_items', {
          'receipt_id': receiptId,
          'product_id': line.productId,
          'unit_id': line.unitId,
          'quantity': line.quantity,
          'factor_to_base': line.factorToBase,
          'unit_cost': line.unitCost,
          'line_cost': line.quantity * line.unitCost,
          'batch_number': line.batchNumber,
          'manufacture_date': line.manufactureDate == null ? null : _date(line.manufactureDate!),
          'expiry_date': line.expiryDate == null ? null : _date(line.expiryDate!),
          'received_quantity_base': line.quantity * line.factorToBase,
        });
      }
      return receiptId;
    });
  }

  Future<void> approveReceipt(int receiptId, {int? approvedBy}) async {
    await db.transaction((txn) async {
      final rows = await txn.query('receipts', where: 'id = ?', whereArgs: [receiptId], limit: 1);
      if (rows.isEmpty) throw StateError('Receipt not found.');
      if (rows.first['status'] != 'draft' && rows.first['status'] != 'pending_approval') {
        throw StateError('Only draft or pending receipts can be approved.');
      }
      final receipt = rows.first;
      final items = await txn.query('receipt_items', where: 'receipt_id = ?', whereArgs: [receiptId]);
      if (items.isEmpty) throw StateError('Cannot approve an empty receipt.');
      final requestId = receipt['request_id'] as int?;
      for (final item in items) {
        final batchId = await txn.insert('inventory_batches', {
          'receipt_item_id': item['id'],
          'product_id': item['product_id'],
          'batch_number': item['batch_number'],
          'received_quantity_base': item['received_quantity_base'],
          'remaining_quantity_base': item['received_quantity_base'],
          'unit_cost_base': (item['unit_cost'] as num) / (item['factor_to_base'] as num),
          'received_at': receipt['receipt_date'],
          'manufacture_date': item['manufacture_date'],
          'expiry_date': item['expiry_date'],
          'status': 'active',
        });
        await txn.insert('stock_movements', {
          'product_id': item['product_id'],
          'batch_id': batchId,
          'movement_type': 'receipt',
          'direction': 'IN',
          'quantity_base': item['received_quantity_base'],
          'source_type': 'receipt',
          'source_id': receiptId,
          'occurred_at': receipt['receipt_date'],
          'created_by': approvedBy,
        });
        if (requestId != null) {
          final changed = await txn.rawUpdate('''
            UPDATE purchase_request_items
            SET received_quantity_base = received_quantity_base + ?
            WHERE request_id = ? AND product_id = ? AND unit_id = ?
          ''', [item['received_quantity_base'], requestId, item['product_id'], item['unit_id']]);
          if (changed != 1) {
            throw StateError('Receipt line does not match exactly one purchase-request line.');
          }
        }
      }
      await txn.update('receipts', {
        'status': 'approved',
        'approved_by': approvedBy,
        'approved_at': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [receiptId]);

      if (requestId != null) await _refreshRequestProgress(txn, requestId);
    });
  }

  Future<int> createIssue({
    required String number,
    required int recipientId,
    required DateTime issueDate,
    required List<IssueLineInput> lines,
    int? createdBy,
    String? notes,
  }) async {
    if (lines.isEmpty) throw ArgumentError('An issue must contain at least one line.');
    if (lines.any((line) => line.unitPrice <= 0)) {
      throw ArgumentError('Every issue line must have a sale price greater than zero.');
    }
    _validateLines(lines.map((line) => (line.quantity, line.factorToBase, line.unitPrice)));
    return db.transaction((txn) async {
      final total = lines.fold<double>(0, (sum, line) => sum + line.quantity * line.unitPrice);
      final issueId = await txn.insert('issues', {
        'issue_number': number,
        'recipient_id': recipientId,
        'issue_date': _date(issueDate),
        'status': 'draft',
        'total_amount': total,
        'notes': notes,
        'created_by': createdBy,
      });
      for (final line in lines) {
        await txn.insert('issue_items', {
          'issue_id': issueId,
          'product_id': line.productId,
          'unit_id': line.unitId,
          'quantity': line.quantity,
          'factor_to_base': line.factorToBase,
          'unit_price': line.unitPrice,
          'line_total': line.quantity * line.unitPrice,
          'issued_quantity_base': line.quantity * line.factorToBase,
        });
      }
      return issueId;
    });
  }

  /// FEFO: consumes the earliest non-expired batch first, atomically.
  Future<void> approveIssue(int issueId, {int? approvedBy}) async {
    await db.transaction((txn) async {
      final issueRows = await txn.query('issues', where: 'id = ?', whereArgs: [issueId], limit: 1);
      if (issueRows.isEmpty) throw StateError('Issue not found.');
      final issue = issueRows.first;
      if (issue['status'] != 'draft' && issue['status'] != 'pending_approval') {
        throw StateError('Only draft or pending issues can be approved.');
      }
      final items = await txn.query('issue_items', where: 'issue_id = ?', whereArgs: [issueId]);
      if (items.isEmpty) throw StateError('Cannot approve an empty issue.');

      for (final item in items) {
        var remaining = (item['issued_quantity_base'] as num).toDouble();
        final batches = await txn.rawQuery('''
          SELECT * FROM inventory_batches
          WHERE product_id = ? AND status = 'active'
            AND remaining_quantity_base > 0
            AND (expiry_date IS NULL OR date(expiry_date) >= date('now'))
          ORDER BY CASE WHEN expiry_date IS NULL THEN 1 ELSE 0 END,
                   expiry_date ASC, received_at ASC, id ASC
        ''', [item['product_id']]);
        for (final batch in batches) {
          if (remaining <= 0) break;
          final available = (batch['remaining_quantity_base'] as num).toDouble();
          final take = available < remaining ? available : remaining;
          await txn.update('inventory_batches', {
            'remaining_quantity_base': available - take,
            if (available - take <= 0) 'status': 'depleted',
          }, where: 'id = ?', whereArgs: [batch['id']]);
          await txn.insert('issue_allocations', {
            'issue_item_id': item['id'],
            'batch_id': batch['id'],
            'quantity_base': take,
            'cost_at_issue': batch['unit_cost_base'],
          });
          await txn.insert('stock_movements', {
            'product_id': item['product_id'],
            'batch_id': batch['id'],
            'movement_type': 'issue',
            'direction': 'OUT',
            'quantity_base': take,
            'source_type': 'issue',
            'source_id': issueId,
            'occurred_at': issue['issue_date'],
            'created_by': approvedBy,
          });
          remaining -= take;
        }
        if (remaining > 0.0000001) {
          throw StateError('Insufficient available stock for product ${item['product_id']}.');
        }
      }
      await txn.update('issues', {
        'status': 'approved',
        'approved_by': approvedBy,
        'approved_at': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [issueId]);
    });
  }

  Future<void> _refreshRequestProgress(Transaction txn, int requestId) async {
    final rows = await txn.rawQuery('''
      SELECT COUNT(*) AS line_count,
             SUM(CASE WHEN received_quantity_base >= requested_quantity * (
               SELECT factor_to_base FROM product_units pu
               WHERE pu.product_id = pri.product_id AND pu.unit_id = pri.unit_id LIMIT 1
             ) THEN 1 ELSE 0 END) AS complete_count,
             SUM(received_quantity_base) AS received_total
      FROM purchase_request_items pri WHERE request_id = ?
    ''', [requestId]);
    final lineCount = (rows.first['line_count'] as num?)?.toInt() ?? 0;
    final completeCount = (rows.first['complete_count'] as num?)?.toInt() ?? 0;
    final status = lineCount > 0 && completeCount == lineCount ? 'fulfilled' : 'partial';
    await txn.update('purchase_requests', {'status': status}, where: 'id = ?', whereArgs: [requestId]);
  }

  void _validateLines(Iterable<(double, double, double)> lines) {
    for (final (quantity, factor, price) in lines) {
      if (!quantity.isFinite || quantity <= 0 || !factor.isFinite || factor <= 0 ||
          !price.isFinite || price < 0) {
        throw ArgumentError('Quantity and unit conversion must be positive; price cannot be negative.');
      }
    }
  }

  String _date(DateTime value) => value.toIso8601String().substring(0, 10);
}

class ReceiptLineInput {
  const ReceiptLineInput({
    required this.productId,
    required this.unitId,
    required this.quantity,
    required this.factorToBase,
    required this.unitCost,
    this.batchNumber,
    this.manufactureDate,
    this.expiryDate,
  });
  final int productId;
  final int unitId;
  final double quantity;
  final double factorToBase;
  final double unitCost;
  final String? batchNumber;
  final DateTime? manufactureDate;
  final DateTime? expiryDate;
}

class IssueLineInput {
  const IssueLineInput({
    required this.productId,
    required this.unitId,
    required this.quantity,
    required this.factorToBase,
    required this.unitPrice,
  });
  final int productId;
  final int unitId;
  final double quantity;
  final double factorToBase;
  final double unitPrice;
}
