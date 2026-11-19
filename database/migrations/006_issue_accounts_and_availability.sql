-- NaeemSoft-WMS migration: 006_issue_accounts_and_availability
BEGIN;
SET search_path TO naeemsoft_wms, public;

CREATE TABLE recipients (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_code varchar(50) UNIQUE,
    name varchar(180) NOT NULL,
    phone varchar(40),
    address text,
    notes text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE supplier_payments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id uuid NOT NULL REFERENCES suppliers(id),
    payment_number varchar(60) NOT NULL UNIQUE,
    payment_date date NOT NULL DEFAULT current_date,
    currency_code varchar(3) NOT NULL REFERENCES currencies(code),
    amount numeric(20,6) NOT NULL CHECK (amount > 0),
    notes text,
    created_by uuid NOT NULL REFERENCES users(id),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE issues (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id uuid NOT NULL REFERENCES branches(id),
    warehouse_id uuid NOT NULL REFERENCES warehouses(id),
    recipient_id uuid NOT NULL REFERENCES recipients(id),
    issue_number varchar(60) NOT NULL,
    issue_date date NOT NULL DEFAULT current_date,
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
    UNIQUE(branch_id, issue_number),
    FOREIGN KEY (warehouse_id, branch_id) REFERENCES warehouses(id, branch_id),
    CHECK (status NOT IN ('pending_approval','approved') OR (submitted_by IS NOT NULL AND submitted_at IS NOT NULL)),
    CHECK (status <> 'approved' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL))
);

CREATE TABLE issue_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    issue_id uuid NOT NULL REFERENCES issues(id) ON DELETE RESTRICT,
    line_number integer NOT NULL,
    product_id uuid NOT NULL,
    product_unit_id uuid NOT NULL,
    quantity numeric(20,6) NOT NULL CHECK (quantity > 0),
    conversion_factor_snapshot numeric(20,6) NOT NULL CHECK (conversion_factor_snapshot > 0),
    quantity_base numeric(24,6) GENERATED ALWAYS AS (quantity * conversion_factor_snapshot) STORED,
    unit_price numeric(20,6) NOT NULL CHECK (unit_price >= 0),
    line_total numeric(24,6) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    UNIQUE(issue_id, line_number),
    FOREIGN KEY (product_id, product_unit_id) REFERENCES product_units(product_id, id)
);

CREATE TABLE recipient_payments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_id uuid NOT NULL REFERENCES recipients(id),
    payment_number varchar(60) NOT NULL UNIQUE,
    payment_date date NOT NULL DEFAULT current_date,
    currency_code varchar(3) NOT NULL REFERENCES currencies(code),
    amount numeric(20,6) NOT NULL CHECK (amount > 0),
    notes text,
    created_by uuid NOT NULL REFERENCES users(id),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION guard_issue_item_edits()
RETURNS trigger LANGUAGE plpgsql
SET search_path = naeemsoft_wms, public AS $$
DECLARE v_id uuid; v_status varchar(24);
BEGIN
    v_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.issue_id ELSE NEW.issue_id END;
    IF TG_OP = 'UPDATE' AND OLD.issue_id <> NEW.issue_id THEN
        RAISE EXCEPTION 'An issue line cannot be moved to another issue';
    END IF;
    SELECT status INTO v_status FROM issues WHERE id = v_id FOR UPDATE;
    IF v_status IS DISTINCT FROM 'draft' THEN
        RAISE EXCEPTION 'Issue lines can only be changed while issue is draft';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END; $$;

CREATE TRIGGER trg_guard_issue_item_edits
BEFORE INSERT OR UPDATE OR DELETE ON issue_items
FOR EACH ROW EXECUTE FUNCTION guard_issue_item_edits();

CREATE OR REPLACE FUNCTION guard_issue_header_update()
RETURNS trigger LANGUAGE plpgsql
SET search_path = naeemsoft_wms, public AS $$
BEGIN
    IF OLD.status = 'approved' THEN RAISE EXCEPTION 'Approved issues are immutable'; END IF;
    IF OLD.status = 'pending_approval' AND
       (to_jsonb(NEW) - ARRAY['status','approved_by','approved_at']) IS DISTINCT FROM
       (to_jsonb(OLD) - ARRAY['status','approved_by','approved_at']) THEN
        RAISE EXCEPTION 'Pending issues cannot be edited';
    END IF;
    IF NEW.status IS DISTINCT FROM OLD.status AND NOT (
       (OLD.status='draft' AND NEW.status IN ('pending_approval','cancelled')) OR
       (OLD.status='pending_approval' AND NEW.status IN ('approved','cancelled'))
    ) THEN RAISE EXCEPTION 'Invalid issue status transition'; END IF;
    RETURN NEW;
END; $$;
CREATE TRIGGER trg_guard_issue_header_update
BEFORE UPDATE ON issues FOR EACH ROW EXECUTE FUNCTION guard_issue_header_update();

CREATE OR REPLACE FUNCTION submit_issue_for_approval(p_issue_id uuid, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SET search_path = naeemsoft_wms, public AS $$
BEGIN
    PERFORM 1 FROM issues WHERE id=p_issue_id AND status='draft' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Only draft issues can be submitted'; END IF;
    IF NOT EXISTS (SELECT 1 FROM issue_items WHERE issue_id=p_issue_id) THEN
        RAISE EXCEPTION 'Cannot submit an empty issue';
    END IF;
    UPDATE issues SET status='pending_approval', submitted_by=p_user_id, submitted_at=now()
    WHERE id=p_issue_id;
END; $$;

CREATE OR REPLACE FUNCTION approve_issue(p_issue_id uuid, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SET search_path = naeemsoft_wms, public AS $$
DECLARE h issues%ROWTYPE; ln issue_items%ROWTYPE; b record; remaining numeric(24,6); take_qty numeric(24,6);
BEGIN
    SELECT * INTO h FROM issues WHERE id=p_issue_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Issue not found'; END IF;
    IF h.status='approved' THEN RETURN; END IF;
    IF h.status <> 'pending_approval' THEN RAISE EXCEPTION 'Only pending issues can be approved'; END IF;

    FOR ln IN SELECT * FROM issue_items WHERE issue_id=p_issue_id ORDER BY line_number LOOP
        remaining := ln.quantity_base;
        FOR b IN
            SELECT ib.batch_id, ib.quantity_on_hand_base
            FROM inventory_balances ib
            JOIN batches ba ON ba.id=ib.batch_id
            WHERE ib.warehouse_id=h.warehouse_id AND ib.product_id=ln.product_id
              AND ib.quantity_on_hand_base > 0
            ORDER BY ba.expiry_date ASC NULLS LAST, ba.created_at ASC, ib.batch_id
            FOR UPDATE OF ib
        LOOP
            EXIT WHEN remaining <= 0;
            take_qty := LEAST(remaining, b.quantity_on_hand_base);
            INSERT INTO stock_movements(
                warehouse_id, product_id, batch_id, movement_type, direction,
                quantity_base, source_document_type, source_document_id,
                source_line_id, created_by, notes
            ) VALUES (
                h.warehouse_id, ln.product_id, b.batch_id, 'issue', 'OUT',
                take_qty, 'issue', h.id, ln.id, p_user_id, 'Posted by issue approval'
            );
            remaining := remaining - take_qty;
        END LOOP;
        IF remaining > 0 THEN
            RAISE EXCEPTION 'Insufficient available stock for product %, missing base quantity %', ln.product_id, remaining;
        END IF;
    END LOOP;
    UPDATE issues SET status='approved', approved_by=p_user_id, approved_at=now()
    WHERE id=p_issue_id;
END; $$;

CREATE OR REPLACE VIEW v_products_available_for_issue AS
SELECT w.id AS warehouse_id, p.id AS product_id, p.sku, p.name AS product_name,
       pu.id AS product_unit_id, u.code AS unit_code, u.name AS unit_name,
       pu.factor_to_base, pup.sale_price, pup.currency_code,
       COALESCE(v.quantity_on_hand_base,0) AS quantity_on_hand_base
FROM warehouses w
JOIN v_products_for_sales v ON v.warehouse_id=w.id
JOIN products p ON p.id=v.product_id
JOIN product_units pu ON pu.product_id=p.id AND pu.is_active AND pu.is_sale_allowed
JOIN units u ON u.id=pu.unit_id
LEFT JOIN product_unit_prices pup ON pup.product_unit_id=pu.id
WHERE w.is_active AND COALESCE(v.quantity_on_hand_base,0)>0;

CREATE OR REPLACE VIEW v_expiry_alerts AS
SELECT b.warehouse_id, b.product_id, p.sku, p.name AS product_name,
       b.id AS batch_id, b.batch_number, b.expiry_date,
       ib.quantity_on_hand_base,
       (b.expiry_date - current_date) AS days_until_expiry
FROM batches b
JOIN products p ON p.id=b.product_id
JOIN inventory_balances ib ON ib.batch_id=b.id
WHERE ib.quantity_on_hand_base>0 AND b.expiry_date IS NOT NULL
  AND b.expiry_date <= current_date + 30;

CREATE OR REPLACE VIEW v_supplier_statement_entries AS
SELECT r.supplier_id, r.currency_code, r.receipt_date AS entry_date,
       r.receipt_number AS document_number, 'توريد معتمد'::text AS description,
       COALESCE(SUM(ri.line_total),0)::numeric(24,6) AS debit,
       0::numeric(24,6) AS credit, r.id AS document_id
FROM receipts r JOIN receipt_items ri ON ri.receipt_id=r.id
WHERE r.status='approved'
GROUP BY r.supplier_id,r.currency_code,r.receipt_date,r.receipt_number,r.id
UNION ALL
SELECT sp.supplier_id, sp.currency_code, sp.payment_date, sp.payment_number,
       'سداد المورد', 0::numeric(24,6), sp.amount, sp.id
FROM supplier_payments sp;

CREATE OR REPLACE VIEW v_recipient_statement_entries AS
SELECT i.recipient_id, i.currency_code, i.issue_date AS entry_date,
       i.issue_number AS document_number, 'صرف معتمد'::text AS description,
       COALESCE(SUM(ii.line_total),0)::numeric(24,6) AS debit,
       0::numeric(24,6) AS credit, i.id AS document_id
FROM issues i JOIN issue_items ii ON ii.issue_id=i.id
WHERE i.status='approved'
GROUP BY i.recipient_id,i.currency_code,i.issue_date,i.issue_number,i.id
UNION ALL
SELECT rp.recipient_id, rp.currency_code, rp.payment_date, rp.payment_number,
       'تحصيل من المستلم', 0::numeric(24,6), rp.amount, rp.id
FROM recipient_payments rp;

CREATE INDEX ix_issues_recipient_date ON issues(recipient_id, issue_date DESC);
CREATE INDEX ix_supplier_payments_supplier_date ON supplier_payments(supplier_id, payment_date DESC);
CREATE INDEX ix_recipient_payments_recipient_date ON recipient_payments(recipient_id, payment_date DESC);

COMMIT;
