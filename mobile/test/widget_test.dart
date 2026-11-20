import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:naeemsoft_wms/data/inventory_operations.dart';
import 'package:naeemsoft_wms/data/local_database.dart';
import 'package:naeemsoft_wms/data/supplier_account_operations.dart';
import 'package:naeemsoft_wms/data/demo_data_seeder.dart';
import 'package:naeemsoft_wms/screens/management_pages.dart';

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
    LocalDatabase.useDatabaseForTesting(db);
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

  tearDown(() async {
    LocalDatabase.clearDatabaseForTesting();
    await db.close();
  });



  testWidgets('product shortcut opens visible fields and saves a product', (tester) async {
    await tester.view.setPhysicalSize(const Size(800, 1200));
    await tester.view.setDevicePixelRatio(1);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: ProductManagementPage(
        tr: (key) => key,
        autoOpenAdd: true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('addProduct'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.enterText(find.byType(TextField).at(0), 'Widget test product');
    await tester.enterText(find.byType(TextField).at(1), '3');
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    final saved = await db.query('products', where: 'name_ar = ?', whereArgs: ['Widget test product']);
    expect(saved, hasLength(1));
    final mappings = await db.query('product_units', where: 'product_id = ?', whereArgs: [saved.single['id']]);
    expect(mappings, hasLength(1));
    expect(find.text('Widget test product'), findsOneWidget);
  });

  testWidgets('supplier shortcut opens fields and persists supplier', (tester) async {
    await tester.view.setPhysicalSize(const Size(800, 1200));
    await tester.view.setDevicePixelRatio(1);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: PartnerManagementPage(
        tr: (key) => key,
        suppliers: true,
        autoOpenAdd: true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(3));
    await tester.enterText(find.byType(TextField).at(0), 'Widget supplier');
    await tester.enterText(find.byType(TextField).at(1), '77712345');
    await tester.enterText(find.byType(TextField).at(2), 'Test address');
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    final rows = await db.query('suppliers', where: 'name = ?', whereArgs: ['Widget supplier']);
    expect(rows, hasLength(1));
    expect(rows.single['phone'], '77712345');
    expect(find.text('Widget supplier'), findsOneWidget);
  });

  testWidgets('recipient shortcut opens fields and persists recipient', (tester) async {
    await tester.view.setPhysicalSize(const Size(800, 1200));
    await tester.view.setDevicePixelRatio(1);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: PartnerManagementPage(
        tr: (key) => key,
        suppliers: false,
        autoOpenAdd: true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(3));
    await tester.enterText(find.byType(TextField).at(0), 'Widget recipient');
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    final rows = await db.query('recipients', where: 'name = ?', whereArgs: ['Widget recipient']);
    expect(rows, hasLength(1));
    expect(find.text('Widget recipient'), findsOneWidget);
  });

  test('fresh database seeds the units required by product and cashier forms', () async {
    final rows = await db.query('units', orderBy: 'code');
    final codes = rows.map((row) => row['code']).toSet();
    expect(codes, containsAll({'pcs', 'box', 'carton', 'pack', 'kg', 'g', 'l'}));
    expect(rows, isNotEmpty);
  });

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


  test('supplier return reduces the original batch and supplier payable', () async {
    final receiptId = await operations.createReceipt(
      number: 'R-RETURN-001',
      supplierId: supplierId,
      receiptDate: DateTime(2026, 11, 20),
      lines: [
        ReceiptLineInput(
          productId: productId, unitId: unitId,
          quantity: 10, factorToBase: 1, unitCost: 4,
        ),
      ],
    );
    await operations.approveReceipt(receiptId);
    final receiptItem = (await db.query('receipt_items')).single;
    final batch = (await db.query('inventory_batches')).single;
    final accounts = SupplierAccountOperations(db);
    final returnId = await accounts.createSupplierReturn(
      number: 'SR-001', supplierId: supplierId,
      date: DateTime(2026, 11, 20),
      lines: [
        SupplierReturnLineInput(
          receiptItemId: receiptItem['id'] as int,
          batchId: batch['id'] as int,
          productId: productId, unitId: unitId,
          quantity: 3, factorToBase: 1,
        ),
      ],
    );
    await accounts.approveSupplierReturn(returnId);
    expect((await db.query('inventory_batches')).single['remaining_quantity_base'], 7);
    final balance = await accounts.getBalances(supplierId: supplierId);
    expect(balance['credit'], 40);
    expect(balance['debit'], 12);
    expect(balance['closing'], 28);
    expect(Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM stock_movements WHERE source_type = 'supplier_return'",
    )), 1);
  });


  test('demo seed creates five products, two suppliers, two recipients and two full workflow cycles', () async {
    final result = await DemoDataSeeder(db).seed();
    expect(result['products'], 5);
    expect(result['suppliers'], 2);
    expect(result['recipients'], 2);
    expect(result['receipts'], 2);
    expect(result['issues'], 2);
    expect(Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM products WHERE sku LIKE 'DEMO-%'")), 5);
    expect(Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM receipts WHERE status='approved'")), 2);
    expect(Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM issues WHERE status='approved'")), 2);
    expect(Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM stock_movements WHERE direction='IN'")), 5);
    expect(Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM stock_movements WHERE direction='OUT'")), 5);
    final sugar = await db.rawQuery('''
      SELECT pu.factor_to_base, u.code FROM product_units pu
      JOIN products p ON p.id=pu.product_id JOIN units u ON u.id=pu.unit_id
      WHERE p.sku='DEMO-003' ORDER BY pu.factor_to_base
    ''');
    expect(sugar.map((r)=>r['code']).toSet(), {'kg','g'});
    expect(sugar.first['factor_to_base'], 0.001);

    final sugarId = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT id FROM products WHERE sku='DEMO-003'"));
    final gramId = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT id FROM units WHERE code='g'"));
    final recipient = Sqflite.firstIntValue(await db.rawQuery(
      "SELECT id FROM recipients WHERE name='جهة الاستلام الأولى'"));
    final gramIssue = await operations.createIssue(
      number:'DEMO-I-GRAM', recipientId:recipient!,
      issueDate:DateTime(2026,11,20),
      lines:[IssueLineInput(productId:sugarId!,unitId:gramId!,
        quantity:500,factorToBase:0.001,unitPrice:0.02)]);
    await operations.approveIssue(gramIssue);
    final sugarStock = await db.rawQuery(
      "SELECT SUM(remaining_quantity_base) AS qty FROM inventory_batches WHERE product_id=?",
      [sugarId]);
    expect((sugarStock.first['qty'] as num).toDouble(), 44.5);
    final second = await DemoDataSeeder(db).seed();
    expect(second['alreadySeeded'], 1);
    expect(Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM products WHERE sku LIKE 'DEMO-%'")), 5);
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
