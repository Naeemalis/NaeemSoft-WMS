import 'package:sqflite/sqflite.dart';

/// Recipient account ledger. Issues increase the amount owed; payments and
/// approved customer returns reduce it.
class RecipientAccountOperations {
  RecipientAccountOperations(this.db);
  final Database db;

  Future<int> recordPayment({
    required String number,
    required int recipientId,
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
        'recipient_id': recipientId,
        'payment_date': _date(date),
        'amount': amount,
        'payment_method': method,
        'reference_number': reference,
        'notes': notes,
        'created_by': createdBy,
      });
      await txn.insert('recipient_transactions', {
        'recipient_id': recipientId,
        'transaction_type': 'payment',
        'document_type': 'payment',
        'document_id': id,
        'debit': 0,
        'credit': amount,
        'transaction_date': _date(date),
        'notes': notes ?? 'Recipient payment $number',
      });
      await txn.insert('audit_logs', {
        'user_id': createdBy,
        'action': 'create',
        'entity_type': 'recipient_payment',
        'entity_id': id,
        'details': 'Payment $number amount $amount',
      });
      return id;
    });
  }

  Future<void> setOpeningBalance({
    required int recipientId,
    required double amount,
    required DateTime date,
    String? notes,
  }) async {
    if (!amount.isFinite || amount < 0) {
      throw ArgumentError('Opening balance cannot be negative.');
    }
    if (amount == 0) return;
    await db.transaction((txn) async {
      await txn.insert('recipient_transactions', {
        'recipient_id': recipientId,
        'transaction_type': 'opening_balance',
        'document_type': 'opening_balance',
        'document_id': recipientId,
        'debit': amount,
        'credit': 0,
        'transaction_date': _date(date),
        'notes': notes ?? 'Recipient opening balance',
      });
      await txn.insert('audit_logs', {
        'action': 'create',
        'entity_type': 'recipient_opening_balance',
        'entity_id': recipientId,
        'details': 'Opening balance $amount',
      });
    });
  }

  Future<Map<String, double>> getBalances({
    required int recipientId,
    DateTime? from,
    DateTime? to,
  }) async {
    final openingRows = from == null
        ? <Map<String, Object?>>[]
        : await db.rawQuery('''
            SELECT COALESCE(SUM(debit - credit), 0) AS balance
            FROM recipient_transactions
            WHERE recipient_id = ? AND date(transaction_date) < date(?)
          ''', [recipientId, _date(from)]);
    final opening = openingRows.isEmpty
        ? 0.0
        : ((openingRows.first['balance'] as num?)?.toDouble() ?? 0.0);

    final clauses = <String>['recipient_id = ?'];
    final args = <Object?>[recipientId];
    if (from != null) {
      clauses.add('date(transaction_date) >= date(?)');
      args.add(_date(from));
    }
    if (to != null) {
      clauses.add('date(transaction_date) <= date(?)');
      args.add(_date(to));
    }
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(debit), 0) AS debit,
             COALESCE(SUM(credit), 0) AS credit
      FROM recipient_transactions WHERE ${clauses.join(' AND ')}
    ''', args);
    final debit = (rows.first['debit'] as num).toDouble();
    final credit = (rows.first['credit'] as num).toDouble();
    return {
      'opening': opening,
      'debit': debit,
      'credit': credit,
      'closing': opening + debit - credit,
    };
  }

  Future<List<Map<String, Object?>>> getStatement({
    required int recipientId,
    DateTime? from,
    DateTime? to,
  }) async {
    final clauses = <String>['recipient_id = ?'];
    final args = <Object?>[recipientId];
    if (from != null) {
      clauses.add('date(transaction_date) >= date(?)');
      args.add(_date(from));
    }
    if (to != null) {
      clauses.add('date(transaction_date) <= date(?)');
      args.add(_date(to));
    }
    return db.query(
      'recipient_transactions',
      where: clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'transaction_date ASC, id ASC',
    );
  }

  String _date(DateTime value) => value.toIso8601String().substring(0, 10);
}
