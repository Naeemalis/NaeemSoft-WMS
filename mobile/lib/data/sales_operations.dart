import 'package:sqflite/sqflite.dart';

/// Independent sales workflow sharing the same physical stock batches as issues.
class SalesOperations {
  SalesOperations(this.db);
  final Database db;

  Future<int> createSale({
    required String number,
    required int recipientId,
    required DateTime saleDate,
    required List<SaleLineInput> lines,
    int? createdBy,
    String? notes,
  }) async {
    if (lines.isEmpty) throw ArgumentError('A sale must contain at least one line.');
    for (final line in lines) {
      if (!line.quantity.isFinite || line.quantity <= 0 ||
          !line.factorToBase.isFinite || line.factorToBase <= 0 ||
          !line.unitPrice.isFinite || line.unitPrice <= 0) {
        throw ArgumentError('Quantity, conversion factor and sale price must be positive.');
      }
    }
    return db.transaction((txn) async {
      for (final line in lines) {
        final units = await txn.query('product_units',
          columns: ['can_sell', 'factor_to_base'],
          where: 'product_id = ? AND unit_id = ?',
          whereArgs: [line.productId, line.unitId], limit: 1);
        if (units.isEmpty || units.first['can_sell'] != 1) {
          throw StateError('The selected product unit is not enabled for sales.');
        }
        final factor = (units.first['factor_to_base'] as num).toDouble();
        if ((factor - line.factorToBase).abs() > 0.0000001) {
          throw StateError('The unit conversion changed. Reload the product and try again.');
        }
      }
      final total = lines.fold<double>(0, (sum, line) => sum + line.quantity * line.unitPrice);
      final id = await txn.insert('sales', {
        'sale_number': number,
        'recipient_id': recipientId,
        'sale_date': _date(saleDate),
        'status': 'draft',
        'total_amount': total,
        'notes': notes,
        'created_by': createdBy,
      });
      for (final line in lines) {
        await txn.insert('sale_items', {
          'sale_id': id,
          'product_id': line.productId,
          'unit_id': line.unitId,
          'quantity': line.quantity,
          'factor_to_base': line.factorToBase,
          'unit_price': line.unitPrice,
          'line_total': line.quantity * line.unitPrice,
          'sold_quantity_base': line.quantity * line.factorToBase,
        });
      }
      return id;
    });
  }

  /// FEFO stock consumption, sales ledger posting and status update are atomic.
  Future<void> approveSale(int saleId, {int? approvedBy}) async {
    await db.transaction((txn) async {
      final rows = await txn.query('sales', where: 'id = ?', whereArgs: [saleId], limit: 1);
      if (rows.isEmpty) throw StateError('Sale not found.');
      final sale = rows.first;
      if (sale['status'] != 'draft' && sale['status'] != 'pending_approval') {
        throw StateError('Only draft or pending sales can be approved.');
      }
      final items = await txn.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
      if (items.isEmpty) throw StateError('Cannot approve an empty sale.');
      for (final item in items) {
        var remaining = (item['sold_quantity_base'] as num).toDouble();
        final batches = await txn.rawQuery('''
          SELECT * FROM inventory_batches
          WHERE product_id = ? AND status = 'active'
            AND remaining_quantity_base > 0
            AND (expiry_date IS NULL OR date(expiry_date) >= date('now'))
          ORDER BY CASE WHEN expiry_date IS NULL THEN 1 ELSE 0 END,
                   expiry_date ASC, received_at ASC, id ASC
        ''', [item['product_id']]);
        for (final batch in batches) {
          if (remaining <= 0.0000001) break;
          final available = (batch['remaining_quantity_base'] as num).toDouble();
          final take = available < remaining ? available : remaining;
          await txn.update('inventory_batches', {
            'remaining_quantity_base': available - take,
            if (available - take <= 0.0000001) 'status': 'depleted',
          }, where: 'id = ?', whereArgs: [batch['id']]);
          await txn.insert('sale_allocations', {
            'sale_item_id': item['id'],
            'batch_id': batch['id'],
            'quantity_base': take,
            'cost_at_sale': batch['unit_cost_base'],
          });
          await txn.insert('stock_movements', {
            'product_id': item['product_id'],
            'batch_id': batch['id'],
            'movement_type': 'sale',
            'direction': 'OUT',
            'quantity_base': take,
            'source_type': 'sale',
            'source_id': saleId,
            'occurred_at': sale['sale_date'],
            'created_by': approvedBy,
          });
          remaining -= take;
        }
        if (remaining > 0.0000001) {
          throw StateError('Insufficient available stock for product ${item['product_id']}.');
        }
      }
      await txn.update('sales', {
        'status': 'approved',
        'approved_by': approvedBy,
        'approved_at': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [saleId]);
      // Customers currently share the existing recipient directory and ledger.
      await txn.insert('recipient_transactions', {
        'recipient_id': sale['recipient_id'],
        'transaction_type': 'sale',
        'document_type': 'sale',
        'document_id': saleId,
        'debit': sale['total_amount'],
        'credit': 0,
        'transaction_date': sale['sale_date'],
        'notes': 'Approved sale ${sale['sale_number']}',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.insert('audit_logs', {
        'user_id': approvedBy,
        'action': 'approve',
        'entity_type': 'sale',
        'entity_id': saleId,
        'details': 'Sale approved; stock and customer ledger updated.',
      });
    });
  }

  Future<void> cancelDraft(int saleId) async {
    await db.transaction((txn) async {
      final changed = await txn.update('sales', {'status': 'cancelled'},
        where: "id = ? AND status IN ('draft','pending_approval')",
        whereArgs: [saleId]);
      if (changed != 1) throw StateError('Only a draft sale can be cancelled.');
      await txn.insert('audit_logs', {
        'action': 'cancel',
        'entity_type': 'sale',
        'entity_id': saleId,
        'details': 'Sale draft cancelled; stock unchanged.',
      });
    });
  }

  String _date(DateTime value) => value.toIso8601String().substring(0, 10);
}

class SaleLineInput {
  const SaleLineInput({
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
