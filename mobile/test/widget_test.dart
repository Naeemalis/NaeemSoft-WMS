import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:naeemsoft_wms/data/inventory_operations.dart';
import 'package:naeemsoft_wms/data/local_database.dart';
import 'package:naeemsoft_wms/data/supplier_account_operations.dart';
import 'package:naeemsoft_wms/data/recipient_account_operations.dart';
import 'package:naeemsoft_wms/data/demo_data_seeder.dart';
import 'package:naeemsoft_wms/screens/management_pages.dart';
import 'package:naeemsoft_wms/screens/cashier_page.dart';
import 'package:naeemsoft_wms/screens/issue_cashier_page.dart';

Future<void> _pumpDatabase(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

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




  testWidgets('cashier empty states expose working add-partner and add-product actions', (tester) async {
    await tester.runAsync(() => db.delete('suppliers'));
    var partnerAction = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CashierPage(
          key: const ValueKey('partner-action'),
          tr: (key) => key,
          receiving: true,
          onOpenPartners: () => partnerAction = true,
        ),
      ),
    ));
    await _pumpDatabase(tester);
    await tester.tap(find.text('addPartner'));
    expect(partnerAction, isTrue);

    await tester.runAsync(() => db.insert('suppliers', {'name': 'Supplier for product action'}));
    await tester.runAsync(() => db.delete('product_units'));
    await tester.runAsync(() => db.delete('products'));
    var productAction = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CashierPage(
          key: const ValueKey('product-action'),
          tr: (key) => key,
          receiving: true,
          onOpenProducts: () => productAction = true,
        ),
      ),
    ));
    await _pumpDatabase(tester);
    await tester.tap(find.text('addProduct'));
    expect(productAction, isTrue);
  });

  testWidgets('product shortcut opens visible fields and saves a product', (tester) async {
    var returnedToCashier = false;
    await tester.pumpWidget(MaterialApp(
      home: ProductManagementPage(
        tr: (key) => key,
        autoOpenAdd: true,
        onDone: () => returnedToCashier = true,
      ),
    ));
    await _pumpDatabase(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(TextField), findsAtLeastNWidgets(4));
    await tester.enterText(find.byType(TextField).at(0), 'Widget test product');
    await tester.enterText(find.byType(TextField).at(1), '3');
    await tester.enterText(find.byType(TextField).at(3), '5');
    await tester.tap(find.text('save'));
    await _pumpDatabase(tester);

    final saved = await tester.runAsync(() => db.query('products', where: 'name_ar = ?', whereArgs: ['Widget test product'])) ?? [];
    expect(saved, hasLength(1));
    final mappings = await tester.runAsync(() => db.query('product_units', where: 'product_id = ?', whereArgs: [saved.single['id']])) ?? [];
    expect(mappings, hasLength(1));
    expect(mappings.single['sale_price'], 5.0);
    expect(returnedToCashier, isTrue);
  });

  testWidgets('existing product can receive its saved unit sale price', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ProductManagementPage(tr: (key) => key),
    ));
    await _pumpDatabase(tester);

    expect(find.text('صنف تجريبي'), findsOneWidget);
    await tester.tap(find.text('صنف تجريبي'));
    await _pumpDatabase(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(TextField), findsAtLeastNWidgets(4));
    await tester.enterText(find.byType(TextField).at(3), '8');
    await tester.tap(find.text('save'));
    await _pumpDatabase(tester);

    final rows = await tester.runAsync(() => db.query(
      'product_units',
      where: 'product_id = ? AND unit_id = ?',
      whereArgs: [productId, unitId],
    )) ?? [];
    expect(rows, hasLength(1));
    expect(rows.single['sale_price'], 8.0);
  });

  testWidgets('supplier shortcut opens fields and persists supplier', (tester) async {
    var returnedToCashier = false;
    await tester.pumpWidget(MaterialApp(
      home: PartnerManagementPage(
        tr: (key) => key,
        suppliers: true,
        autoOpenAdd: true,
        onDone: () => returnedToCashier = true,
      ),
    ));
    await _pumpDatabase(tester);

    expect(find.byType(TextField), findsNWidgets(3));
    await tester.enterText(find.byType(TextField).at(0), 'Widget supplier');
    await tester.enterText(find.byType(TextField).at(1), '77712345');
    await tester.enterText(find.byType(TextField).at(2), 'Test address');
    await tester.tap(find.text('save'));
    await _pumpDatabase(tester);

    final rows = await tester.runAsync(() => db.query('suppliers', where: 'name = ?', whereArgs: ['Widget supplier'])) ?? [];
    expect(rows, hasLength(1));
    expect(rows.single['phone'], '77712345');
    expect(returnedToCashier, isTrue);
  });

  testWidgets('recipient shortcut opens fields and persists recipient', (tester) async {
    var returnedToCashier = false;
    await tester.pumpWidget(MaterialApp(
      home: PartnerManagementPage(
        tr: (key) => key,
        suppliers: false,
        autoOpenAdd: true,
        onDone: () => returnedToCashier = true,
      ),
    ));
    await _pumpDatabase(tester);

    expect(find.byType(TextField), findsNWidgets(3));
    await tester.enterText(find.byType(TextField).at(0), 'Widget recipient');
    await tester.tap(find.text('save'));
    await _pumpDatabase(tester);

    final rows = await tester.runAsync(() => db.query('recipients', where: 'name = ?', whereArgs: ['Widget recipient'])) ?? [];
    expect(rows, hasLength(1));
    expect(returnedToCashier, isTrue);
  });

  testWidgets('issue cashier selects product units dynamically and deducts stock only on approval', (tester) async {
    await tester.runAsync(() async {
      await db.update('product_units', {'sale_price': 5},
        where: 'product_id = ? AND unit_id = ?', whereArgs: [productId, unitId]);
      final receiptId = await operations.createReceipt(
        number: 'R-ISSUE-CASHIER-UI',
        supplierId: supplierId,
        receiptDate: DateTime(2026, 11, 23),
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
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: IssueCashierPage(tr: (key) => key),
      ),
    ));
    await _pumpDatabase(tester);

    expect(find.text('صنف تجريبي'), findsOneWidget);
    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.tap(find.text('صنف تجريبي'));
    await tester.pump();
    expect(find.text('كيلوغرام'), findsOneWidget);
    await tester.tap(find.text('كيلوغرام'));
    await tester.pump();
    final addButton = find.widgetWithText(FilledButton, 'إضافة إلى السلة');
    expect(tester.widget<FilledButton>(addButton).onPressed, isNotNull);
    await tester.tap(addButton);
    await tester.pump();

    expect(find.text('السلة (1) • 10'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test recipient').last);
    await tester.pump();
    final stockBeforeDraft = await tester.runAsync(() async =>
      (await db.query('inventory_batches')).single['remaining_quantity_base']);
    expect(stockBeforeDraft, 20);

    await tester.tap(find.text('السلة (1) • 10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('saveDraft'));
    await _pumpDatabase(tester);
    final draftState = await tester.runAsync(() async => {
      'stock': (await db.query('inventory_batches')).single['remaining_quantity_base'],
      'status': (await db.query('issues')).single['status'],
    }) ?? <String, Object?>{};
    expect(draftState['stock'], 20);
    expect(draftState['status'], 'draft');

    await tester.tap(find.text('approveDocument'));
    await _pumpDatabase(tester);
    final approvedState = await tester.runAsync(() async => {
      'stock': (await db.query('inventory_batches')).single['remaining_quantity_base'],
      'status': (await db.query('issues')).single['status'],
    }) ?? <String, Object?>{};
    expect(approvedState['stock'], 18);
    expect(approvedState['status'], 'approved');
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


  test('approved issue posts recipient debit once and recipient payment reduces balance', () async {
    final receiptId = await operations.createReceipt(
      number: 'R-RECIPIENT-LEDGER',
      supplierId: supplierId,
      receiptDate: DateTime(2026, 11, 20),
      lines: [
        ReceiptLineInput(
          productId: productId, unitId: unitId,
          quantity: 10, factorToBase: 1, unitCost: 2,
        ),
      ],
    );
    await operations.approveReceipt(receiptId);
    final issueId = await operations.createIssue(
      number: 'I-RECIPIENT-LEDGER',
      recipientId: recipientId,
      issueDate: DateTime(2026, 11, 21),
      lines: [
        IssueLineInput(
          productId: productId, unitId: unitId,
          quantity: 3, factorToBase: 1, unitPrice: 5,
        ),
      ],
    );
    await operations.approveIssue(issueId);
    final accounts = RecipientAccountOperations(db);
    var balance = await accounts.getBalances(recipientId: recipientId);
    expect(balance['debit'], 15);
    expect(balance['credit'], 0);
    expect(balance['closing'], 15);
    expect(Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM recipient_transactions WHERE document_type = 'issue' AND document_id = ?",
      [issueId],
    )), 1);

    await accounts.recordPayment(
      number: 'RP-001',
      recipientId: recipientId,
      date: DateTime(2026, 11, 22),
      amount: 6,
    );
    balance = await accounts.getBalances(recipientId: recipientId);
    expect(balance['debit'], 15);
    expect(balance['credit'], 6);
    expect(balance['closing'], 9);
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


  test('stocktake freeze blocks issue approval and preserves the issue draft', () async {
    final receiptId = await operations.createReceipt(
      number: 'R-FREEZE-ISSUE',
      supplierId: supplierId,
      receiptDate: DateTime(2026, 11, 20),
      lines: [
        ReceiptLineInput(
          productId: productId,
          unitId: unitId,
          quantity: 8,
          factorToBase: 1,
          unitCost: 2,
        ),
      ],
    );
    await operations.approveReceipt(receiptId);
    final issueId = await operations.createIssue(
      number: 'I-FROZEN',
      recipientId: recipientId,
      issueDate: DateTime(2026, 11, 20),
      lines: [
        IssueLineInput(
          productId: productId,
          unitId: unitId,
          quantity: 2,
          factorToBase: 1,
          unitPrice: 4,
        ),
      ],
    );
    await db.insert('stock_counts', {
      'count_number': 'SC-ISSUE-001',
      'status': 'in_progress',
      'started_at': DateTime(2026, 11, 20).toIso8601String(),
    });

    await expectLater(operations.approveIssue(issueId), throwsA(anything));
    expect((await db.query('inventory_batches')).single['remaining_quantity_base'], 8);
    expect((await db.query('issues')).single['status'], 'draft');
    expect(Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM stock_movements WHERE direction = 'OUT'",
    )), 0);
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
