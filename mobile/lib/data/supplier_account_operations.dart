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
