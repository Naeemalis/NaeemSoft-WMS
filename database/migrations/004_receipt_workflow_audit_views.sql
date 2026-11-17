-- NaeemSoft-WMS migration: 004_receipt_workflow_audit_views
BEGIN;
SET search_path TO naeemsoft_wms, public;

-- A sale-enabled product unit must have its own manually entered sale price.
-- Product, units and prices should be created in one transaction.
CREATE OR REPLACE FUNCTION check_sale_price_for_product_unit()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = naeemsoft_wms, public
AS $$
DECLARE
    v_unit_id uuid;
BEGIN
    IF TG_TABLE_NAME = 'product_units' THEN
        v_unit_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END;
    ELSE
        v_unit_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.product_unit_id ELSE NEW.product_unit_id END;
    END IF;

    IF EXISTS (
        SELECT 1 FROM product_units
         WHERE id = v_unit_id AND is_active = true AND is_sale_allowed = true
    ) AND NOT EXISTS (
        SELECT 1 FROM product_unit_prices WHERE product_unit_id = v_unit_id
    ) THEN
        RAISE EXCEPTION 'A sale price is required for sale-enabled product unit %', v_unit_id;
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER ct_sale_price_on_product_unit
AFTER INSERT OR UPDATE ON product_units
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_sale_price_for_product_unit();

CREATE CONSTRAINT TRIGGER ct_sale_price_on_price
AFTER INSERT OR UPDATE OR DELETE ON product_unit_prices
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_sale_price_for_product_unit();

-- Enforce the receipt state machine: draft -> pending_approval -> approved.
-- Cancellation is allowed only before approval. Approved receipts require a
-- separate reversal document; they cannot be edited or cancelled in place.
CREATE OR REPLACE FUNCTION guard_receipt_status_transition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = naeemsoft_wms, public
AS $$
BEGIN
    IF NEW.status = OLD.status THEN
        IF OLD.status = 'approved'
           AND (
               NEW.branch_id IS DISTINCT FROM OLD.branch_id
               OR NEW.warehouse_id IS DISTINCT FROM OLD.warehouse_id
               OR NEW.supplier_id IS DISTINCT FROM OLD.supplier_id
               OR NEW.receipt_number IS DISTINCT FROM OLD.receipt_number
               OR NEW.currency_code IS DISTINCT FROM OLD.currency_code
               OR NEW.exchange_rate IS DISTINCT FROM OLD.exchange_rate
               OR NEW.receipt_date IS DISTINCT FROM OLD.receipt_date
               OR NEW.notes IS DISTINCT FROM OLD.notes
           ) THEN
            RAISE EXCEPTION 'Approved receipts are immutable';
        END IF;
        RETURN NEW;
    END IF;

    IF OLD.status = 'draft' AND NEW.status IN ('pending_approval', 'cancelled') THEN
        RETURN NEW;
    ELSIF OLD.status = 'pending_approval' AND NEW.status IN ('approved', 'cancelled') THEN
        RETURN NEW;
    END IF;

    RAISE EXCEPTION 'Invalid receipt status transition: % -> %', OLD.status, NEW.status;
END;
$$;

CREATE TRIGGER trg_guard_receipt_status_transition
BEFORE UPDATE OF status ON receipts
FOR EACH ROW EXECUTE FUNCTION guard_receipt_status_transition();

CREATE OR REPLACE FUNCTION submit_receipt_for_approval(
    p_receipt_id uuid,
    p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SET search_path = naeemsoft_wms, public
AS $$
DECLARE
    v_status varchar(24);
    v_item_count integer;
BEGIN
    SELECT status INTO v_status
      FROM receipts
     WHERE id = p_receipt_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Receipt % not found', p_receipt_id;
    END IF;

    IF v_status <> 'draft' THEN
        RAISE EXCEPTION 'Only draft receipts can be submitted; current status: %', v_status;
    END IF;

    SELECT count(*) INTO v_item_count
      FROM receipt_items
     WHERE receipt_id = p_receipt_id;

    IF v_item_count = 0 THEN
        RAISE EXCEPTION 'Cannot submit an empty receipt';
    END IF;

    UPDATE receipts
       SET status = 'pending_approval',
           submitted_by = p_user_id,
           submitted_at = now()
     WHERE id = p_receipt_id;
END;
$$;

CREATE OR REPLACE FUNCTION approve_receipt(
    p_receipt_id uuid,
    p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SET search_path = naeemsoft_wms, public
AS $$
DECLARE
    v_receipt receipts%ROWTYPE;
    v_line receipt_items%ROWTYPE;
    v_batch_id uuid;
    v_movement_id uuid;
BEGIN
    SELECT * INTO v_receipt
      FROM receipts
     WHERE id = p_receipt_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Receipt % not found', p_receipt_id;
    END IF;

    -- Safe retry: an already approved receipt is not posted a second time.
    IF v_receipt.status = 'approved' THEN
        RETURN;
    END IF;

    IF v_receipt.status <> 'pending_approval' THEN
        RAISE EXCEPTION 'Only pending receipts can be approved; current status: %',
            v_receipt.status;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM receipt_items WHERE receipt_id = p_receipt_id) THEN
        RAISE EXCEPTION 'Cannot approve an empty receipt';
    END IF;

    FOR v_line IN
        SELECT * FROM receipt_items
         WHERE receipt_id = p_receipt_id
         ORDER BY line_number
    LOOP
        INSERT INTO batches (
            receipt_item_id, product_id, warehouse_id, batch_number,
            expiry_date, received_qty_base
        )
        VALUES (
            v_line.id, v_line.product_id, v_receipt.warehouse_id,
            v_line.supplier_batch_number, v_line.expiry_date, v_line.quantity_base
        )
        ON CONFLICT (receipt_item_id) DO NOTHING
        RETURNING id INTO v_batch_id;

        IF v_batch_id IS NULL THEN
            SELECT id INTO v_batch_id FROM batches WHERE receipt_item_id = v_line.id;
        END IF;

        INSERT INTO stock_movements (
            warehouse_id, product_id, batch_id, movement_type, direction,
            quantity_base, source_document_type, source_document_id,
            source_line_id, created_by, notes
        )
        VALUES (
            v_receipt.warehouse_id, v_line.product_id, v_batch_id,
            'receipt', 'IN', v_line.quantity_base, 'receipt', v_receipt.id,
            v_line.id, p_user_id, 'Posted by receipt approval'
        )
        ON CONFLICT (
            source_document_type, source_document_id, source_line_id, movement_type
        ) DO NOTHING
        RETURNING id INTO v_movement_id;

        -- The stock movement trigger updates inventory_balances atomically.
        -- The unique source key prevents duplicate posting on a retry.
        v_batch_id := NULL;
        v_movement_id := NULL;
    END LOOP;

    UPDATE receipts
       SET status = 'approved',
           approved_by = p_user_id,
           approved_at = now()
     WHERE id = p_receipt_id;
END;
$$;

CREATE TABLE audit_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES users(id),
    branch_id uuid REFERENCES branches(id),
    action varchar(80) NOT NULL,
    entity_name varchar(100) NOT NULL,
    entity_id uuid,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    details jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX ix_audit_logs_entity ON audit_logs(entity_name, entity_id, occurred_at DESC);
CREATE INDEX ix_audit_logs_user_date ON audit_logs(user_id, occurred_at DESC);

CREATE OR REPLACE VIEW v_receipt_totals AS
SELECT
    r.id AS receipt_id,
    r.branch_id,
    r.warehouse_id,
    r.supplier_id,
    r.receipt_number,
    r.status,
    r.currency_code,
    COALESCE(SUM(ri.line_total), 0) AS total_before_exchange,
    COALESCE(SUM(ri.quantity_base), 0) AS total_base_quantity
FROM receipts r
LEFT JOIN receipt_items ri ON ri.receipt_id = r.id
GROUP BY r.id, r.branch_id, r.warehouse_id, r.supplier_id,
         r.receipt_number, r.status, r.currency_code;

COMMIT;
