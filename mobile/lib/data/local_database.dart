import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase instance = LocalDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final root = await getDatabasesPath();
    final path = p.join(root, 'naeemsoft_wms.db');
    _database = await openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA journal_mode = WAL');
        await db.execute('PRAGMA busy_timeout = 5000');
      },
      onCreate: _createSchema,
    );
    return _database!;
  }

  Future<void> _createSchema(Database db, int version) async {
    final statements = <String>[
      '''CREATE TABLE app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )''',
      '''CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name_ar TEXT NOT NULL,
        name_en TEXT NOT NULL,
        name_fr TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )''',
      '''CREATE TABLE units (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        name_ar TEXT NOT NULL,
        name_en TEXT NOT NULL,
        name_fr TEXT NOT NULL
      )''',
      '''CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sku TEXT UNIQUE,
        category_id INTEGER REFERENCES categories(id),
        name_ar TEXT NOT NULL,
        name_en TEXT NOT NULL DEFAULT '',
        name_fr TEXT NOT NULL DEFAULT '',
        base_unit_id INTEGER NOT NULL REFERENCES units(id),
        minimum_stock REAL NOT NULL DEFAULT 0 CHECK(minimum_stock >= 0),
        stagnation_days INTEGER NOT NULL DEFAULT 90 CHECK(stagnation_days > 0),
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )''',
      '''CREATE TABLE product_units (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL REFERENCES products(id),
        unit_id INTEGER NOT NULL REFERENCES units(id),
        factor_to_base REAL NOT NULL CHECK(factor_to_base > 0),
        can_receive INTEGER NOT NULL DEFAULT 1 CHECK(can_receive IN (0,1)),
        can_issue INTEGER NOT NULL DEFAULT 1 CHECK(can_issue IN (0,1)),
        UNIQUE(product_id, unit_id)
      )''',
      '''CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )''',
      '''CREATE TABLE recipients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )''',
      '''CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        full_name TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )''',
      '''CREATE TABLE roles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        role_name TEXT NOT NULL UNIQUE
      )''',
      '''CREATE TABLE permissions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        permission_code TEXT NOT NULL UNIQUE,
        description TEXT NOT NULL
      )''',
      '''CREATE TABLE user_roles (
        user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        role_id INTEGER NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
        PRIMARY KEY(user_id, role_id)
      )''',
      '''CREATE TABLE role_permissions (
        role_id INTEGER NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
        permission_id INTEGER NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
        PRIMARY KEY(role_id, permission_id)
      )''',
      '''CREATE TABLE purchase_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_number TEXT NOT NULL UNIQUE,
        supplier_id INTEGER REFERENCES suppliers(id),
        request_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'draft'
          CHECK(status IN ('draft','pending_approval','approved','sent','partial','fulfilled','cancelled')),
        notes TEXT,
        created_by INTEGER REFERENCES users(id),
        approved_by INTEGER REFERENCES users(id),
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )''',
      '''CREATE TABLE purchase_request_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id INTEGER NOT NULL REFERENCES purchase_requests(id) ON DELETE CASCADE,
        product_id INTEGER NOT NULL REFERENCES products(id),
        unit_id INTEGER NOT NULL REFERENCES units(id),
        requested_quantity REAL NOT NULL CHECK(requested_quantity > 0),
        estimated_unit_cost REAL CHECK(estimated_unit_cost IS NULL OR estimated_unit_cost >= 0),
        received_quantity_base REAL NOT NULL DEFAULT 0 CHECK(received_quantity_base >= 0)
      )''',
      '''CREATE TABLE receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_number TEXT NOT NULL UNIQUE,
        supplier_id INTEGER NOT NULL REFERENCES suppliers(id),
        request_id INTEGER REFERENCES purchase_requests(id),
        receipt_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'draft'
          CHECK(status IN ('draft','pending_approval','approved','cancelled')),
        total_cost REAL NOT NULL DEFAULT 0 CHECK(total_cost >= 0),
        notes TEXT,
        created_by INTEGER REFERENCES users(id),
        approved_by INTEGER REFERENCES users(id),
        approved_at TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )''',
      '''CREATE TABLE receipt_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_id INTEGER NOT NULL REFERENCES receipts(id) ON DELETE CASCADE,
        product_id INTEGER NOT NULL REFERENCES products(id),
        unit_id INTEGER NOT NULL REFERENCES units(id),
        quantity REAL NOT NULL CHECK(quantity > 0),
        factor_to_base REAL NOT NULL CHECK(factor_to_base > 0),
        unit_cost REAL NOT NULL CHECK(unit_cost >= 0),
        line_cost REAL NOT NULL CHECK(line_cost >= 0),
        batch_number TEXT,
        manufacture_date TEXT,
        expiry_date TEXT,
        received_quantity_base REAL NOT NULL CHECK(received_quantity_base > 0),
        CHECK(expiry_date IS NULL OR manufacture_date IS NULL OR expiry_date >= manufacture_date)
      )''',
      '''CREATE TABLE inventory_batches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_item_id INTEGER NOT NULL UNIQUE REFERENCES receipt_items(id),
        product_id INTEGER NOT NULL REFERENCES products(id),
        batch_number TEXT,
        received_quantity_base REAL NOT NULL CHECK(received_quantity_base > 0),
        remaining_quantity_base REAL NOT NULL CHECK(remaining_quantity_base >= 0),
        unit_cost_base REAL NOT NULL CHECK(unit_cost_base >= 0),
        received_at TEXT NOT NULL,
        manufacture_date TEXT,
        expiry_date TEXT,
        status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','quarantined','expired','depleted'))
      )''',
      '''CREATE TABLE issues (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        issue_number TEXT NOT NULL UNIQUE,
        recipient_id INTEGER NOT NULL REFERENCES recipients(id),
        issue_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'draft'
          CHECK(status IN ('draft','pending_approval','approved','cancelled')),
        total_amount REAL NOT NULL DEFAULT 0 CHECK(total_amount >= 0),
        notes TEXT,
        created_by INTEGER REFERENCES users(id),
        approved_by INTEGER REFERENCES users(id),
        approved_at TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )''',
      '''CREATE TABLE issue_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        issue_id INTEGER NOT NULL REFERENCES issues(id) ON DELETE CASCADE,
        product_id INTEGER NOT NULL REFERENCES products(id),
        unit_id INTEGER NOT NULL REFERENCES units(id),
        quantity REAL NOT NULL CHECK(quantity > 0),
        factor_to_base REAL NOT NULL CHECK(factor_to_base > 0),
        unit_price REAL NOT NULL CHECK(unit_price >= 0),
        line_total REAL NOT NULL CHECK(line_total >= 0),
        issued_quantity_base REAL NOT NULL CHECK(issued_quantity_base > 0)
      )''',
      '''CREATE TABLE issue_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        issue_item_id INTEGER NOT NULL REFERENCES issue_items(id),
        batch_id INTEGER NOT NULL REFERENCES inventory_batches(id),
        quantity_base REAL NOT NULL CHECK(quantity_base > 0),
        cost_at_issue REAL NOT NULL CHECK(cost_at_issue >= 0)
      )''',
      '''CREATE TABLE stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL REFERENCES products(id),
        batch_id INTEGER REFERENCES inventory_batches(id),
        movement_type TEXT NOT NULL CHECK(movement_type IN
          ('receipt','issue','customer_return','supplier_return','count_adjustment','reversal')),
        direction TEXT NOT NULL CHECK(direction IN ('IN','OUT')),
        quantity_base REAL NOT NULL CHECK(quantity_base > 0),
        source_type TEXT NOT NULL,
        source_id INTEGER NOT NULL,
        occurred_at TEXT NOT NULL,
        created_by INTEGER REFERENCES users(id),
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )''',
      '''CREATE TABLE supplier_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL REFERENCES suppliers(id),
        transaction_type TEXT NOT NULL,
        document_type TEXT NOT NULL,
        document_id INTEGER NOT NULL,
        debit REAL NOT NULL DEFAULT 0 CHECK(debit >= 0),
        credit REAL NOT NULL DEFAULT 0 CHECK(credit >= 0),
        transaction_date TEXT NOT NULL,
        notes TEXT
      )''',
      '''CREATE TABLE recipient_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recipient_id INTEGER NOT NULL REFERENCES recipients(id),
        transaction_type TEXT NOT NULL,
        document_type TEXT NOT NULL,
        document_id INTEGER NOT NULL,
        debit REAL NOT NULL DEFAULT 0 CHECK(debit >= 0),
        credit REAL NOT NULL DEFAULT 0 CHECK(credit >= 0),
        transaction_date TEXT NOT NULL,
        notes TEXT
      )''',
      '''CREATE TABLE stock_counts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        count_number TEXT NOT NULL UNIQUE,
        status TEXT NOT NULL DEFAULT 'draft'
          CHECK(status IN ('draft','in_progress','approved','cancelled')),
        started_at TEXT NOT NULL,
        completed_at TEXT,
        created_by INTEGER REFERENCES users(id),
        approved_by INTEGER REFERENCES users(id)
      )''',
      '''CREATE TABLE stock_count_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stock_count_id INTEGER NOT NULL REFERENCES stock_counts(id) ON DELETE CASCADE,
        product_id INTEGER NOT NULL REFERENCES products(id),
        batch_id INTEGER REFERENCES inventory_batches(id),
        system_quantity_base REAL NOT NULL CHECK(system_quantity_base >= 0),
        counted_quantity_base REAL CHECK(counted_quantity_base IS NULL OR counted_quantity_base >= 0),
        variance_base REAL
      )''',
      '''CREATE TABLE audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER REFERENCES users(id),
        action TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id INTEGER,
        details TEXT,
        occurred_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      )''',
      'CREATE INDEX idx_products_category ON products(category_id)',
      'CREATE INDEX idx_batches_product_expiry ON inventory_batches(product_id, expiry_date)',
      'CREATE INDEX idx_movements_product_date ON stock_movements(product_id, occurred_at)',
      'CREATE INDEX idx_receipts_supplier_date ON receipts(supplier_id, receipt_date)',
      'CREATE INDEX idx_issues_recipient_date ON issues(recipient_id, issue_date)',
      'CREATE INDEX idx_purchase_requests_date_status ON purchase_requests(request_date, status)',
    ];
    for (final statement in statements) {
      await db.execute(statement);
    }
    await db.insert('app_settings', {'setting_key': 'language', 'setting_value': 'ar'});
    await db.insert('app_settings', {'setting_key': 'stagnation_days', 'setting_value': '90'});
    await db.insert('app_settings', {'setting_key': 'expiry_warning_days', 'setting_value': '30'});
  }

  Future<List<Map<String, Object?>>> getProducts() async {
    final db = await database;
    return db.rawQuery('''
      SELECT p.*, u.name_ar AS base_unit_name,
        COALESCE(SUM(CASE WHEN b.status = 'active' AND
          (b.expiry_date IS NULL OR date(b.expiry_date) >= date('now'))
          THEN b.remaining_quantity_base ELSE 0 END), 0) AS available_quantity
      FROM products p
      JOIN units u ON u.id = p.base_unit_id
      LEFT JOIN inventory_batches b ON b.product_id = p.id
      WHERE p.is_active = 1
      GROUP BY p.id
      ORDER BY p.name_ar COLLATE NOCASE
    ''');
  }
}
