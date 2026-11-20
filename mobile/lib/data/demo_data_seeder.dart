import 'package:sqflite/sqflite.dart';

import 'inventory_operations.dart';

/// Creates a repeat-safe demonstration dataset and runs two real receipts
/// and two real issues through the same production approval services.
class DemoDataSeeder {
  DemoDataSeeder(this.db);
  final Database db;

  Future<Map<String, int>> seed() async {
    final already = await db.query('app_settings',
      where: 'setting_key = ?', whereArgs: ['demo_seed_v1'], limit: 1);
    if (already.isNotEmpty) {
      return {'products': 5, 'suppliers': 2, 'recipients': 2,
        'receipts': 2, 'issues': 2, 'alreadySeeded': 1};
    }

    return db.transaction((txn) async {
      Future<int> unit(String code) async {
        final rows = await txn.query('units', columns: ['id'],
          where: 'code = ?', whereArgs: [code], limit: 1);
        if (rows.isEmpty) throw StateError('Missing required unit: $code');
        return rows.first['id'] as int;
      }
      final pcs = await unit('pcs');
      final kg = await unit('kg');
      final gram = await unit('g');
      final litre = await unit('l');

      final category = await txn.insert('categories', {
        'name_ar':'مواد تجريبية', 'name_en':'Demo supplies', 'name_fr':'Articles de démonstration',
      });
      final products = <String,int>{};
      Future<int> product(String sku, String ar, String en, String fr, int base) async {
        final id = await txn.insert('products', {
          'sku':sku, 'category_id':category, 'name_ar':ar, 'name_en':en,
          'name_fr':fr, 'base_unit_id':base, 'minimum_stock':5,
        });
        await txn.insert('product_units', {
          'product_id':id, 'unit_id':base, 'factor_to_base':1,
          'can_receive':1, 'can_issue':1,
        });
        return id;
      }
      products['pen'] = await product('DEMO-001','قلم حبر','Ink pen','Stylo à encre',pcs);
      products['notebook'] = await product('DEMO-002','دفتر','Notebook','Cahier',pcs);
      products['sugar'] = await product('DEMO-003','سكر','Sugar','Sucre',kg);
      products['oil'] = await product('DEMO-004','زيت طبخ','Cooking oil','Huile de cuisson',litre);
      products['soap'] = await product('DEMO-005','صابون','Soap','Savon',pcs);
      await txn.insert('product_units', {
        'product_id':products['sugar'], 'unit_id':gram,
        'factor_to_base':0.001, 'can_receive':1, 'can_issue':1,
      });

      final supplierA = await txn.insert('suppliers', {
        'name':'مورد التجربة الأول', 'phone':'770000001', 'address':'مورد تجريبي',
      });
      final supplierB = await txn.insert('suppliers', {
        'name':'مورد التجربة الثاني', 'phone':'770000002', 'address':'مورد تجريبي',
      });
      final recipientA = await txn.insert('recipients', {
        'name':'جهة الاستلام الأولى', 'phone':'770000011', 'address':'جهة تجريبية',
      });
      final recipientB = await txn.insert('recipients', {
        'name':'جهة الاستلام الثانية', 'phone':'770000012', 'address':'جهة تجريبية',
      });
      // Store a marker only after all demo documents have been created.
      // Transaction rollback means a partial seed is never left behind.
      final stamp = DateTime.now().toIso8601String().substring(0,10);
      final receipt1 = await txn.insert('receipts', {
        'receipt_number':'DEMO-R-001','supplier_id':supplierA,
        'receipt_date':stamp,'status':'draft','total_cost':0,
        'notes':'فاتورة توريد تجريبية - المورد الأول',
      });
      final receipt2 = await txn.insert('receipts', {
        'receipt_number':'DEMO-R-002','supplier_id':supplierB,
        'receipt_date':stamp,'status':'draft','total_cost':0,
        'notes':'فاتورة توريد تجريبية - المورد الثاني',
      });
      Future<void> addReceiptLine(int receiptId,int productId,int unitId,
          double quantity,double factor,double cost) async {
        final lineCost=quantity*cost;
        await txn.insert('receipt_items', {
          'receipt_id':receiptId,'product_id':productId,'unit_id':unitId,
          'quantity':quantity,'factor_to_base':factor,'unit_cost':cost,
          'line_cost':lineCost,'received_quantity_base':quantity*factor,
        });
        // The production approval service consumes these prepared receipt lines.
        await txn.rawUpdate('UPDATE receipts SET total_cost = total_cost + ? WHERE id = ?',
          [lineCost,receiptId]);
      }
      await addReceiptLine(receipt1,pen,pcs,100,1,1.5);
      await addReceiptLine(receipt1,sugar,kg,50,1,2.0);
      await addReceiptLine(receipt1,oil,litre,40,1,3.0);
      await addReceiptLine(receipt2,notebook,pcs,60,1,2.5);
      await addReceiptLine(receipt2,soap,pcs,80,1,1.0);

      // Approval is performed after the seed transaction commits, using the
      // same InventoryOperations path as live cashier receipts.
      await txn.insert('app_settings', {
        'setting_key':'demo_seed_pending', 'setting_value':'1',
      });
      return {
        'products':5,'suppliers':2,'recipients':2,
        'receipts':2,'issues':0,'alreadySeeded':0,
        'receipt1':receipt1,'receipt2':receipt2,
        'recipient1':recipientA,'recipient2':recipientB,
      };
    }).then((seeded) async {
      if (seeded['alreadySeeded'] == 1) return seeded;
      final ops=InventoryOperations(db);
      final r1=seeded['receipt1']!;
      final r2=seeded['receipt2']!;
      await ops.approveReceipt(r1);
      await ops.approveReceipt(r2);
      Future<int> findUnit(String code) async {
        final rows=await db.query('units',columns:['id'],where:'code = ?',whereArgs:[code],limit:1);
        return rows.first['id'] as int;
      }
      final pcs=await findUnit('pcs');
      final kg=await findUnit('kg');
      final litre=await findUnit('l');
      final productRows=await db.query('products',columns:['id','sku'],where:'sku LIKE ?',whereArgs:['DEMO-%']);
      final demoProducts={for(final row in productRows) row['sku'].toString():row['id'] as int};
      final pen=demoProducts['DEMO-001']!;
      final notebook=demoProducts['DEMO-002']!;
      final sugar=demoProducts['DEMO-003']!;
      final oil=demoProducts['DEMO-004']!;
      final soap=demoProducts['DEMO-005']!;
      final recA=seeded['recipient1']!;
      final recB=seeded['recipient2']!;
      final now=DateTime.now();
      final issue1=await ops.createIssue(
        number:'DEMO-I-001',recipientId:recA,issueDate:now,
        lines:[
          IssueLineInput(productId:pen,unitId:pcs,quantity:10,factorToBase:1,unitPrice:2.5),
          IssueLineInput(productId:sugar,unitId:kg,quantity:5,factorToBase:1,unitPrice:3.0),
          IssueLineInput(productId:oil,unitId:litre,quantity:3,factorToBase:1,unitPrice:4.0),
        ]);
      await ops.approveIssue(issue1);
      final issue2=await ops.createIssue(
        number:'DEMO-I-002',recipientId:recB,issueDate:now,
        lines:[
          IssueLineInput(productId:notebook,unitId:pcs,quantity:8,factorToBase:1,unitPrice:3.5),
          IssueLineInput(productId:soap,unitId:pcs,quantity:12,factorToBase:1,unitPrice:1.5),
        ]);
      await ops.approveIssue(issue2);
      await db.delete('app_settings',where:'setting_key = ?',whereArgs:['demo_seed_pending']);
      await db.insert('app_settings',{'setting_key':'demo_seed_v1','setting_value':'completed'});
      return {...seeded,'issues':2};
    });
  }
}
