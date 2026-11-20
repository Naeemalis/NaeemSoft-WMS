import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:naeemsoft_wms/data/inventory_operations.dart';
import 'package:naeemsoft_wms/data/local_database.dart';
import 'package:naeemsoft_wms/data/supplier_account_operations.dart';

void main() {
  late Database db;
  late InventoryOperations operations;
  late int supplierId;
  late int recipientId;
  late int productId;
  late int unitId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await LocalDatabase.openInMemoryForTesting();
    operations = InventoryOperations(db);
    unitId = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT id FROM units WHERE code = 'kg'",
    ))!;
    supplierId = await db.insert('suppliers', {'name': 'Test supplier'});
    recipientId = await db.insert('recipients', {'name': 'Test recipient'});
    productId = await db.insert('products', {
      'name_ar': 'صنف تجريبي',
      'base_unit_id': unitId,
    });
    await db.insert('product_units', {
      'product_id': productId,
      'unit_id': unitId,
      'factor_to_base': 1,
    });
  });

  tearDown(() async => db.close());

  test('draft receipt does not change stock; approval creates a batch', () async {
    final receiptId = await operations.createReceipt(
      number: 'R-001',
      supplierId: supplierId,
      receiptDate: DateTime(2026, 11, 20),
      lines: [
        ReceiptLineInput(
          productId: productId,
          unitId: unitId,
          quantity: 20,
          factorToBase: 1,
          unitCost: 3.5,
        ),
      ],
    );

    expect(Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM inventory_batches',
    )), 0);

    await operations.approveReceipt(receiptId);
    final batch = (await db.query('inventory_batches')).single;
    expect(batch['remaining_quantity_base'], 20);
    expect(batch['unit_cost_base'], 3.5);
    expect(Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM stock_movements WHERE direction = 'IN'",
    )), 1);
  });

  test('approved issue consumes stock using batch allocation', () async {
    final receiptId = await operations.createReceipt(
      number: 'R-002',
      supplierId: supplierId,
      receiptDate: DateTime(2026, 11, 20),
      lines: [
        ReceiptLineInput(
          productId: productId,
          unitId: unitId,
          quantity: 20,
          factorToBase: 1,
          unitCost: 2,
        ),
      ],
    );
    await operations.approveReceipt(receiptId);

    final issueId = await operations.createIssue(
      number: 'I-001',
      recipientId: recipientId,
      issueDate: DateTime(2026, 11, 20),
      lines: [
        IssueLineInput(
          productId: productId,
          unitId: unitId,
          quantity: 7,
          factorToBase: 1,
          unitPrice: 5,
        ),
      ],
    );
    await operations.approveIssue(issueId);

    expect((await db.query('inventory_batches')).single['remaining_quantity_base'], 13);
    expect(Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM issue_allocations',
    )), 1);
    expect((await db.query('issues')).single['status'], 'approved');
  });

  test('insufficient stock rolls back the whole issue approval', () async {
    final receiptId = await operations.createReceipt(
      number: 'R-003',
      supplierId: supplierId,
      receiptDate: DateTime(2026, 11, 20),
      lines: [
        ReceiptLineInput(
          productId: productId,
          unitId: unitId,
          quantity: 4,
          factorToBase: 1,
          unitCost: 2,
        ),
      ],
    );
    await operations.approveReceipt(receiptId);
    final issueId = await operations.createIssue(
      number: 'I-002',
      recipientId: recipientId,
      issueDate: DateTime(2026, 11, 20),
      lines: [
        IssueLineInput(
          productId: productId,
          unitId: unitId,
          quantity: 5,
          factorToBase: 1,
          unitPrice: 5,
        ),
      ],
    );

    await expectLater(operations.approveIssue(issueId), throwsStateError);
    expect((await db.query('inventory_batches')).single['remaining_quantity_base'], 4);
    expect((await db.query('issues')).single['status'], 'draft');
    expect(Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM issue_allocations',
    )), 0);
  });


  test('supplier payment is posted once and reduces supplier payable', () async {
    final receiptId = await operations.createReceipt(
      number: 'R-LEDGER-001',
      supplierId: supplierId,
      receiptDate: DateTime(2026, 11, 20),
      lines: [
        ReceiptLineInput(
          productId: productId,
          unitId: unitId,
          quantity: 10,
          factorToBase: 1,
          unitCost: 4,
        ),
      ],
    );
    await operations.approveReceipt(receiptId);
    await operations.approveReceipt(receiptId);
    final accounts = SupplierAccountOperations(db);
    await accounts.recordPayment(
      number: 'SP-001',
      supplierId: supplierId,
      date: DateTime(2026, 11, 20),
      amount: 15,
    );
    final balance = await accounts.getBalances(supplierId: supplierId);
    expect(balance['credit'], 40);
    expect(balance['debit'], 15);
    expect(balance['closing'], 25);
    expect(Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM supplier_transactions WHERE document_type = 'receipt' AND document_id = ?",
      [receiptId],
    )), 1);
  });

  test('stocktake freeze blocks receipt approval', () async {
    final receiptId = await operations.createReceipt(
      number: 'R-004',
      supplierId: supplierId,
      receiptDate: DateTime(2026, 11, 20),
      lines: [
        ReceiptLineInput(
          productId: productId,
          unitId: unitId,
          quantity: 3,
          factorToBase: 1,
          unitCost: 2,
        ),
      ],
    );
    await db.insert('stock_counts', {
      'count_number': 'SC-001',
      'status': 'in_progress',
      'started_at': DateTime(2026, 11, 20).toIso8601String(),
    });

    await expectLater(operations.approveReceipt(receiptId), throwsA(anything));
    expect(await db.query('inventory_batches'), isEmpty);
    expect((await db.query('receipts')).single['status'], 'draft');
  });
}
