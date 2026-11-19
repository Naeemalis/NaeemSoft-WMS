-- NaeemSoft-WMS migration 009: linked lifecycle documents, returns, counts, transfers and reorder controls.
BEGIN;
SET search_path TO naeemsoft_wms, public;

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS reorder_level_base numeric(24,6) NOT NULL DEFAULT 0
  CHECK (reorder_level_base >= 0);

-- All lifecycle documents use the same branch/warehouse/product/user relationships.
CREATE TABLE IF NOT EXISTS stock_returns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES branches(id),
  warehouse_id uuid NOT NULL,
  party_type varchar(20) NOT NULL CHECK (party_type IN ('supplier','recipient')),
  supplier_id uuid REFERENCES suppliers(id),
  recipient_id uuid REFERENCES recipients(id),
  return_number varchar(60) NOT NULL,
  return_direction varchar(20) NOT NULL CHECK (return_direction IN ('to_supplier','from_recipient')),
  status varchar(24) NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','pending_approval','approved','cancelled')),
  currency_code varchar(3) NOT NULL REFERENCES currencies(code),
  notes text,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  submitted_by uuid REFERENCES users(id),
  submitted_at timestamptz,
  approved_by uuid REFERENCES users(id),
  approved_at timestamptz,
  UNIQUE(branch_id, return_number),
  FOREIGN KEY (warehouse_id, branch_id) REFERENCES warehouses(id, branch_id),
  CHECK (
    (party_type='supplier' AND supplier_id IS NOT NULL AND recipient_id IS NULL AND return_direction='to_supplier')
    OR
    (party_type='recipient' AND recipient_id IS NOT NULL AND supplier_id IS NULL AND return_direction='from_recipient')
  ),
  CHECK (status NOT IN ('pending_approval','approved') OR (submitted_by IS NOT NULL AND submitted_at IS NOT NULL)),
  CHECK (status <> 'approved' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS stock_return_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  return_id uuid NOT NULL REFERENCES stock_returns(id) ON DELETE RESTRICT,
  line_number integer NOT NULL,
  product_id uuid NOT NULL REFERENCES products(id),
  product_unit_id uuid NOT NULL,
  batch_id uuid NOT NULL,
  quantity numeric(20,6) NOT NULL CHECK (quantity > 0),
  conversion_factor_snapshot numeric(20,6) NOT NULL CHECK (conversion_factor_snapshot > 0),
  quantity_base numeric(24,6) GENERATED ALWAYS AS (quantity * conversion_factor_snapshot) STORED,
  unit_amount numeric(20,6) NOT NULL DEFAULT 0 CHECK (unit_amount >= 0),
  UNIQUE(return_id,line_number),
  FOREIGN KEY (product_id,product_unit_id) REFERENCES product_units(product_id,id),
  FOREIGN KEY (batch_id,product_id) REFERENCES batches(id,product_id)
);

CREATE TABLE IF NOT EXISTS stock_counts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES branches(id),
  warehouse_id uuid NOT NULL,
  count_number varchar(60) NOT NULL,
  status varchar(24) NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','pending_approval','approved','cancelled')),
  notes text,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  submitted_by uuid REFERENCES users(id),
  submitted_at timestamptz,
  approved_by uuid REFERENCES users(id),
  approved_at timestamptz,
  UNIQUE(branch_id,count_number),
  FOREIGN KEY (warehouse_id,branch_id) REFERENCES warehouses(id,branch_id)
);

CREATE TABLE IF NOT EXISTS stock_count_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  count_id uuid NOT NULL REFERENCES stock_counts(id) ON DELETE RESTRICT,
  product_id uuid NOT NULL REFERENCES products(id),
  batch_id uuid NOT NULL,
  system_quantity_base numeric(24,6) NOT NULL,
  counted_quantity_base numeric(24,6) NOT NULL CHECK (counted_quantity_base >= 0),
  variance_base numeric(24,6) GENERATED ALWAYS AS (counted_quantity_base-system_quantity_base) STORED,
  UNIQUE(count_id,batch_id),
  FOREIGN KEY (batch_id,product_id) REFERENCES batches(id,product_id)
);

CREATE TABLE IF NOT EXISTS stock_transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_branch_id uuid NOT NULL REFERENCES branches(id),
  from_warehouse_id uuid NOT NULL,
  to_branch_id uuid NOT NULL REFERENCES branches(id),
  to_warehouse_id uuid NOT NULL,
  transfer_number varchar(60) NOT NULL UNIQUE,
  status varchar(24) NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','pending_approval','approved','cancelled')),
  notes text,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  approved_by uuid REFERENCES users(id),
  approved_at timestamptz,
  FOREIGN KEY (from_warehouse_id,from_branch_id) REFERENCES warehouses(id,branch_id),
  FOREIGN KEY (to_warehouse_id,to_branch_id) REFERENCES warehouses(id,branch_id),
  CHECK (from_warehouse_id <> to_warehouse_id)
);

CREATE TABLE IF NOT EXISTS stock_transfer_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_id uuid NOT NULL REFERENCES stock_transfers(id) ON DELETE RESTRICT,
  line_number integer NOT NULL,
  product_id uuid NOT NULL REFERENCES products(id),
  source_batch_id uuid NOT NULL,
  quantity_base numeric(24,6) NOT NULL CHECK (quantity_base > 0),
  UNIQUE(transfer_id,line_number),
  FOREIGN KEY (source_batch_id,product_id) REFERENCES batches(id,product_id)
);

-- Unified, traceable product card. Ledger is authoritative; balances are its projection.
CREATE OR REPLACE VIEW v_product_movement_ledger AS
SELECT sm.product_id, p.sku, p.name AS product_name, sm.warehouse_id,
       sm.batch_id, sm.movement_type, sm.direction, sm.quantity_base,
       sm.source_document_type, sm.source_document_id, sm.source_line_id,
       sm.created_by, sm.created_at, sm.notes,
       CASE WHEN sm.direction='IN' THEN sm.quantity_base ELSE -sm.quantity_base END AS signed_quantity_base
FROM stock_movements sm
JOIN products p ON p.id=sm.product_id;

CREATE OR REPLACE VIEW v_reorder_alerts AS
SELECT p.id AS product_id, p.sku, p.name AS product_name,
       p.reorder_level_base,
       COALESCE(SUM(ib.quantity_on_hand_base),0) AS quantity_on_hand_base
FROM products p
LEFT JOIN inventory_balances ib ON ib.product_id=p.id
WHERE p.is_active=true AND p.reorder_level_base>0
GROUP BY p.id,p.sku,p.name,p.reorder_level_base
HAVING COALESCE(SUM(ib.quantity_on_hand_base),0) <= p.reorder_level_base;

CREATE INDEX IF NOT EXISTS ix_stock_returns_party ON stock_returns(supplier_id,recipient_id,created_at DESC);
CREATE INDEX IF NOT EXISTS ix_stock_counts_warehouse ON stock_counts(warehouse_id,created_at DESC);
CREATE INDEX IF NOT EXISTS ix_stock_transfers_source ON stock_transfers(from_warehouse_id,created_at DESC);
CREATE INDEX IF NOT EXISTS ix_stock_transfers_target ON stock_transfers(to_warehouse_id,created_at DESC);

COMMIT;
