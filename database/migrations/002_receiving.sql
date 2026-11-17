-- NaeemSoft-WMS migration: 002_receiving
BEGIN;
SET search_path TO naeemsoft_wms, public;

CREATE TABLE suppliers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_code varchar(50) UNIQUE,
    name varchar(180) NOT NULL,
    phone varchar(40),
    email varchar(160),
    address text,
    notes text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE receipts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id uuid NOT NULL REFERENCES branches(id),
    warehouse_id uuid NOT NULL,
    supplier_id uuid NOT NULL REFERENCES suppliers(id),
    receipt_number varchar(60) NOT NULL,
    status varchar(24) NOT NULL DEFAULT 'draft',
    currency_code varchar(3) NOT NULL REFERENCES currencies(code),
    exchange_rate numeric(20,8) NOT NULL DEFAULT 1,
    supplier_invoice_number varchar(80),
    receipt_date date NOT NULL DEFAULT current_date,
    notes text,
    created_by uuid NOT NULL REFERENCES users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    submitted_by uuid REFERENCES users(id),
    submitted_at timestamptz,
    approved_by uuid REFERENCES users(id),
    approved_at timestamptz,
    cancelled_by uuid REFERENCES users(id),
    cancelled_at timestamptz,
    CONSTRAINT fk_receipt_warehouse_branch
        FOREIGN KEY (warehouse_id, branch_id) REFERENCES warehouses(id, branch_id),
    CONSTRAINT uq_receipt_number_per_branch UNIQUE (branch_id, receipt_number),
    CONSTRAINT ck_receipt_status CHECK (status IN ('draft', 'pending_approval', 'approved', 'cancelled')),
    CONSTRAINT ck_receipt_exchange_rate_positive CHECK (exchange_rate > 0),
    CONSTRAINT ck_receipt_submitted_fields
        CHECK (status NOT IN ('pending_approval', 'approved')
               OR (submitted_by IS NOT NULL AND submitted_at IS NOT NULL)),
    CONSTRAINT ck_receipt_approved_fields
        CHECK (status <> 'approved' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)),
    CONSTRAINT ck_receipt_cancelled_fields
        CHECK (status <> 'cancelled' OR (cancelled_by IS NOT NULL AND cancelled_at IS NOT NULL))
);

CREATE TABLE receipt_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    receipt_id uuid NOT NULL REFERENCES receipts(id) ON DELETE RESTRICT,
    line_number integer NOT NULL,
    product_id uuid NOT NULL,
    product_unit_id uuid NOT NULL,
    quantity numeric(20,6) NOT NULL,
    conversion_factor_snapshot numeric(20,6) NOT NULL,
    quantity_base numeric(24,6)
        GENERATED ALWAYS AS (quantity * conversion_factor_snapshot) STORED,
    unit_cost numeric(20,6) NOT NULL,
    line_total numeric(24,6)
        GENERATED ALWAYS AS (quantity * unit_cost) STORED,
    supplier_batch_number varchar(100),
    expiry_date date,
    notes text,
    CONSTRAINT uq_receipt_item_line UNIQUE (receipt_id, line_number),
    CONSTRAINT fk_receipt_item_product_unit
        FOREIGN KEY (product_id, product_unit_id) REFERENCES product_units(product_id, id),
    CONSTRAINT ck_receipt_item_line_positive CHECK (line_number > 0),
    CONSTRAINT ck_receipt_item_quantity_positive CHECK (quantity > 0),
    CONSTRAINT ck_receipt_item_conversion_positive CHECK (conversion_factor_snapshot > 0),
    CONSTRAINT ck_receipt_item_cost_nonnegative CHECK (unit_cost >= 0)
);

CREATE INDEX ix_receipt_items_receipt ON receipt_items(receipt_id);
CREATE INDEX ix_receipt_items_product ON receipt_items(product_id);

-- One receipt line creates one stock batch on approval. Use separate lines
-- when the same product arrives with different expiry dates or supplier lots.
CREATE TABLE batches (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    receipt_item_id uuid NOT NULL UNIQUE REFERENCES receipt_items(id) ON DELETE RESTRICT,
    product_id uuid NOT NULL REFERENCES products(id),
    warehouse_id uuid NOT NULL REFERENCES warehouses(id),
    batch_number varchar(100),
    expiry_date date,
    received_qty_base numeric(24,6) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_batch_received_qty_positive CHECK (received_qty_base > 0),
    CONSTRAINT uq_batch_id_product_warehouse UNIQUE (id, product_id, warehouse_id)
);

CREATE OR REPLACE FUNCTION guard_receipt_item_edits()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = naeemsoft_wms, public
AS $$
DECLARE
    v_receipt_id uuid;
    v_status varchar(24);
BEGIN
    v_receipt_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.receipt_id ELSE NEW.receipt_id END;

    IF TG_OP = 'UPDATE' AND OLD.receipt_id <> NEW.receipt_id THEN
        RAISE EXCEPTION 'A receipt item cannot be moved to another receipt';
    END IF;

    SELECT status INTO v_status
      FROM receipts
     WHERE id = v_receipt_id
     FOR UPDATE;

    IF v_status IS DISTINCT FROM 'draft' THEN
        RAISE EXCEPTION 'Receipt items can only be changed while receipt is in draft';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_guard_receipt_item_edits
BEFORE INSERT OR UPDATE OR DELETE ON receipt_items
FOR EACH ROW EXECUTE FUNCTION guard_receipt_item_edits();

COMMIT;
